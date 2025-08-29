//  NeedleTailAsyncSequence.swift
//
//  Created by Cole M on 6/9/23.
//

import Foundation
import DequeModule
import Atomics
import NeedleTailLogger

/// A protocol that combines the requirements of TaskExecutor and SerialExecutor.
public protocol AnyExecutor: TaskExecutor & SerialExecutor {}

/// An asynchronous consumer that processes tasks of type T.
public actor NeedleTailAsyncConsumer<T: Sendable> {
    
    /// A nonisolated property to get the unowned executor.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    
    private let logger: NeedleTailLogger
    public var deque = Deque<TaskJob<T>>() // A deque to hold tasks.
    public var stateMachine = NTASequenceStateMachine() // State machine for managing task states.
    private let executor: any AnyExecutor // Type-erased executor.
    
    /// Initializes a new instance of NeedleTailAsyncConsumer.
    /// - Parameters:
    ///   - deque: A deque to hold tasks (default is an empty deque).
    ///   - logger: A logger for logging messages (default is a logger with a specific label).
    ///   - executor: An optional custom executor. If nil, a default executor is created.
    public init(
        deque: Deque<TaskJob<T>> = Deque<TaskJob<T>>(),
        logger: NeedleTailLogger = NeedleTailLogger( "[NeedleTailAsyncConsumer]"),
        executor: (any AnyExecutor)? = nil // Optional executor
    ) {
        self.deque = deque
        self.logger = logger
        self.executor = executor ?? NTAExecutor(queue: .init(label: "nta-consumer-executor"))
    }
    
    /// Reserves capacity in the deque for a specified number of tasks.
    /// - Parameter capacity: The number of tasks to reserve capacity for.
    @inline(__always)
    public func reserveCapacity(_ capacity: Int) async {
        deque.reserveCapacity(capacity)
    }
    
    /// Feeds a task into the consumer with a specified priority.
    /// - Parameters:
    ///   - item: The task item to be fed into the consumer.
    ///   - priority: The priority of the task (default is .standard).
    @inline(__always)
    public func feedConsumer(_ item: T, priority: Priority = .standard) async {
        logger.log(level: .trace, message: "Fed task with priority: \(priority)")
        let taskJob = TaskJob(item: item, priority: priority)
        
        switch priority {
        case .urgent:
            deque.prepend(taskJob)
        case .standard:
            insertTaskJob(taskJob, beforePriority: .utility)
        case .utility:
            insertTaskJob(taskJob, beforePriority: .background)
        case .background:
            deque.append(taskJob)
        }
    }
    
    /// Inserts a task job into the deque before a specified priority.
    /// - Parameters:
    ///   - taskJob: The task job to insert.
    ///   - beforePriority: The priority before which to insert the task job.
    private func insertTaskJob(_ taskJob: TaskJob<T>, beforePriority: Priority) {
        if let index = deque.firstIndex(where: { $0.priority == beforePriority }) {
            deque.insert(taskJob, at: index)
        } else {
            deque.append(taskJob)
        }
    }
    
    /// Retrieves the next task from the consumer.
    /// - Returns: The next task job or indicates that no tasks are available.
    @inline(__always)
    public func next() async -> NTASequenceStateMachine.NextNTAResult<TaskJob<T>> {
        if !deque.isEmpty {
            stateMachine.ready()
        } else {
            stateMachine.cancel()
        }
        switch stateMachine.state {
        case 0:
            return .consumed
        case 1:
            guard let item = deque.popFirst() else {
                return .consumed
            }
            return .ready(item)
        default:
            return .consumed
        }
    }
    
    /// Gracefully shuts down the consumer, removing all tasks and canceling the state machine.
    public func gracefulShutdown() async {
        deque.removeAll()
        stateMachine.cancel()
        _ = await next()
    }
}

/// An asynchronous sequence that produces results from a NeedleTailAsyncConsumer.
public struct NeedleTailAsyncSequence<ConsumerTypeValue: Sendable>: AsyncSequence, Sendable {
    
    public typealias Element = NTASequenceStateMachine.NTASequenceResult<ConsumerTypeValue>
    
    public let consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>
    
    /// Initializes a new instance of NeedleTailAsyncSequence.
    /// - Parameter consumer: The consumer to produce results from.
    public init(consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>) {
        self.consumer = consumer
    }
    
    /// Creates an asynchronous iterator for the sequence.
    /// - Returns: An iterator for the async sequence.
    public func makeAsyncIterator() -> Iterator<ConsumerTypeValue> {
        return Iterator(consumer: consumer)
    }
}

extension NeedleTailAsyncSequence {
    /// An iterator for the NeedleTailAsyncSequence.
    public struct Iterator<T: Sendable>: AsyncIteratorProtocol, Sendable {
        
        public typealias Element = NTASequenceStateMachine.NTASequenceResult<T>
        
        public let consumer: NeedleTailAsyncConsumer<T>
        
        /// Initializes a new instance of the iterator.
        /// - Parameter consumer: The consumer to iterate over.
        public init(consumer: NeedleTailAsyncConsumer<T>) {
            self.consumer = consumer
        }
        
        /// Gracefully shuts down the consumer associated with the iterator.
        public func gracefulShutdown() async {
            await consumer.gracefulShutdown()
        }
        
        /// Retrieves the next result from the consumer.
        /// - Returns: The next result or nil if no more results are available.
        public func next() async throws -> NTASequenceStateMachine.NTASequenceResult<T>? {
            let stateMachine = await consumer.stateMachine
            return await withTaskCancellationHandler {
                let result = await consumer.next()
                switch result {
                case .ready(let sequence):
                    // Transition to cancel if the deque is empty
                    if await consumer.deque.isEmpty {
                        _ = await consumer.next()
                    }
                    return .success(sequence.item)
                case .consumed:
                    return nil
                }
            } onCancel: {
                stateMachine.cancel()
            }
        }
    }
}

/// A state machine for managing the state of the NeedleTailAsyncConsumer.
public final class NTASequenceStateMachine: @unchecked Sendable {
    
    public init() {}
    
    /// Represents the consumed state of the state machine.
    public enum NTAConsumedState: Int, Sendable, CustomStringConvertible {
        case consumed, waiting
        
        public var description: String {
            switch self {
            case .consumed:
                return "consumed"
            case .waiting:
                return "ready"
            }
        }
    }
    
    /// Represents the result of a sequence operation.
    public enum NTASequenceResult<T: Sendable>: Sendable {
        case success(T), consumed
    }
    
    /// Represents the next result of a sequence operation.
    public enum NextNTAResult<T: Sendable>: Sendable {
        case ready(T), consumed
    }
    
    private let protectedState = ManagedAtomic<Int>(NTAConsumedState.consumed.rawValue)
    
    /// The current state of the state machine.
    public var state: NTAConsumedState.RawValue {
        get { protectedState.load(ordering: .acquiring) }
        set { protectedState.store(newValue, ordering: .relaxed) }
    }
    
    /// Marks the state machine as ready.
    public func ready() {
        state = 1
    }
    
    /// Cancels the state machine.
    public func cancel() {
        state = 0
    }
}

/// A job representing a task with an associated priority.
public struct TaskJob<T: Sendable>: Sendable {
    public var item: T
    public var priority: Priority
    
    /// Initializes a new task job.
    /// - Parameters:
    ///   - item: The task item.
    ///   - priority: The priority of the task.
    public init(item: T, priority: Priority) {
        self.item = item
        self.priority = priority
    }
}

/// An enumeration representing the priority levels of tasks.
public enum Priority: Int, Sendable, Codable {
    case urgent, standard, background, utility
}

extension Deque: Sendable {}

/// A protocol defining the requirements for a consumer.
/// A protocol defining the requirements for a consumer.
public protocol Consumer: Sendable {
    associatedtype T: Sendable
    func reserveCapacity(_ capacity: Int) async
    func feedConsumer(_ item: T, priority: Priority) async
    func next() async -> NTASequenceStateMachine.NextNTAResult<TaskJob<T>>
    func gracefulShutdown() async
}

/// A default executor that conforms to AnyExecutor.
public final class NTAExecutor: AnyExecutor {
    
    let queue: DispatchQueue
    let shouldExecuteAsTask: Bool
    
    /// Initializes a new instance of NTAExecutor.
    /// - Parameters:
    ///   - queue: The dispatch queue to execute tasks on.
    ///   - shouldExecuteAsTask: A flag indicating whether to execute as a task (default is true).
    init(queue: DispatchQueue, shouldExecuteAsTask: Bool = true) {
        self.queue = queue
        self.shouldExecuteAsTask = shouldExecuteAsTask
    }
    
    /// Converts the executor to an unowned task executor.
    /// - Returns: An unowned task executor.
    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
    
    /// Checks if the current execution context is isolated to the executor's queue.
    public func checkIsolated() {
        dispatchPrecondition(condition: .onQueue(queue))
    }
    
    /// Enqueues a job for execution.
    /// - Parameter job: The job to be executed.
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        self.queue.async { [weak self] in
            guard let self = self else { return }
            if self.shouldExecuteAsTask {
                job.runSynchronously(on: self.asUnownedTaskExecutor())
            } else {
                job.runSynchronously(on: self.asUnownedSerialExecutor())
            }
        }
    }
    
    /// Converts the executor to an unowned serial executor.
    /// - Returns: An unowned serial executor.
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(complexEquality: self)
    }
}
