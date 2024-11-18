//
//  NeedleTailAsyncSequence.swift
//
//
//  Created by Cole M on 6/9/23.
//

import DequeModule
import Atomics
import NeedleTailLogger

public struct NeedleTailAsyncSequence<ConsumerTypeValue: Sendable>: AsyncSequence, Sendable {
    
    public typealias Element = NTASequenceStateMachine.NTASequenceResult<ConsumerTypeValue>
    
    public let consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>
    
    public init(consumer: NeedleTailAsyncConsumer<ConsumerTypeValue>) {
        self.consumer = consumer
    }
    
    public func makeAsyncIterator() -> Iterator<ConsumerTypeValue> {
        return Iterator(consumer: consumer)
    }
}

extension NeedleTailAsyncSequence {
    public struct Iterator<T: Sendable>: AsyncIteratorProtocol, Sendable {
        
        public typealias Element = NTASequenceStateMachine.NTASequenceResult<T>
        
        public let consumer: NeedleTailAsyncConsumer<T>
        
        public init(consumer: NeedleTailAsyncConsumer<T>) {
            self.consumer = consumer
        }
        
        public func next() async throws -> NTASequenceStateMachine.NTASequenceResult<T>? {
            let stateMachine = await consumer.stateMachine
            return await withTaskCancellationHandler {
                let result = await consumer.next()
                switch result {
                case .ready(let sequence):
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

public struct TaskJob<T: Sendable>: Sendable {
    public var item: T
    public var priority: Priority
    
    public init(item: T, priority: Priority) {
        self.item = item
        self.priority = priority
    }
}

public enum Priority: Int, Sendable, Codable {
    case urgent, standard, background, utility
}

extension Deque: Sendable {}

public actor NeedleTailAsyncConsumer<T: Sendable> {
    private let logger = NeedleTailLogger(.init(label: "[NeedleTailAsyncConsumer]"))
    public var deque = Deque<TaskJob<T>>()
    public var stateMachine = NTASequenceStateMachine()
    
    public init(deque: Deque<TaskJob<T>> = Deque<TaskJob<T>>()) {
        self.deque = deque
    }
    
    public func feedConsumer(_ item: T, priority: Priority = .standard) async {
        await logger.log(level: .trace, message: "Fed task with priority: \(priority)")
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
    
    private func insertTaskJob(_ taskJob: TaskJob<T>, beforePriority: Priority) {
        if let index = deque.firstIndex(where: { $0.priority == beforePriority }) {
            deque.insert(taskJob, at: index)
        } else {
            deque.append(taskJob)
        }
    }
    
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
            guard let item = deque.popFirst() else { return .consumed }
            return .ready(item)
        default:
            return .consumed
        }
    }
}

public final class NTASequenceStateMachine: @unchecked Sendable {
    
    public init() {}
    
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
    
    public enum NTASequenceResult<T: Sendable>: Sendable {
        case success(T), consumed
    }
    
    public enum NextNTAResult<T: Sendable>: Sendable {
        case ready(T), consumed
    }
    
    private let protectedState = ManagedAtomic<Int>(NTAConsumedState.consumed.rawValue)
    
    public var state: NTAConsumedState.RawValue {
        get { protectedState.load(ordering: .acquiring) }
        set { protectedState.store(newValue, ordering: .relaxed) }
    }
    
    public func ready() {
        state = 1
    }
    
    public func cancel() {
        state = 0
    }
}

// MARK: - Testing Considerations
// 1. Test `NeedleTailAsyncConsumer` to ensure tasks are fed and retrieved in the correct order based on priority.
// 2. Test cancellation behavior in `next()` to ensure that it properly cancels ongoing operations.
// 3. Test the `feedConsumer` method to ensure that tasks are inserted correctly based on their priority.
// 4. Test the `NTASequenceStateMachine` to ensure that state transitions occur as expected.

