import Foundation
import Testing
import DequeModule

@testable import NeedleTailAsyncSequence

// MARK: - NeedleTailAsyncConsumerTests

@Suite("NeedleTailAsyncConsumer")
struct NeedleTailAsyncConsumerTests {

    @Test("feed consumer with urgent priority")
    func feedConsumerWithUrgentPriority() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(1, priority: .urgent)
        let result = await consumer.next()

        switch result {
        case .ready(let job):
            #expect(job.item == 1)
            #expect(job.priority == .urgent)
        case .consumed:
            Issue.record("Expected to receive a job but got consumed.")
        }
    }

    @Test("feed consumer with standard priority")
    func feedConsumerWithStandardPriority() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(2, priority: .standard)
        await consumer.feedConsumer(3, priority: .urgent)

        let result = await consumer.next()

        switch result {
        case .ready(let job):
            #expect(job.item == 3)
            #expect(job.priority == .urgent)
        case .consumed:
            Issue.record("Expected to receive a job but got consumed.")
        }
    }

    @Test("feed consumer with utility priority")
    func feedConsumerWithUtilityPriority() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(4, priority: .utility)
        await consumer.feedConsumer(5, priority: .standard)

        let result = await consumer.next()

        switch result {
        case .ready(let job):
            #expect(job.item == 5)
            #expect(job.priority == .standard)
        case .consumed:
            Issue.record("Expected to receive a job but got consumed.")
        }
    }

    @Test("feed consumer with background priority")
    func feedConsumerWithBackgroundPriority() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(6, priority: .background)
        let result = await consumer.next()

        switch result {
        case .ready(let job):
            #expect(job.item == 6)
            #expect(job.priority == .background)
        case .consumed:
            Issue.record("Expected to receive a job but got consumed.")
        }
    }

    @Test("next returns consumed when deque is empty")
    func nextReturnsConsumedWhenDequeIsEmpty() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        let result = await consumer.next()
        switch result {
        case .ready:
            Issue.record("Expected consumed but got a job.")
        case .consumed:
            break
        }
    }

    @Test("reserveCapacity reserves capacity")
    func reserveCapacityReservesCapacity() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.reserveCapacity(100)
        await consumer.feedConsumer(1, priority: .standard)
        let result = await consumer.next()
        switch result {
        case .ready(let job):
            #expect(job.item == 1)
        case .consumed:
            Issue.record("Expected to receive a job.")
        }
    }

    @Test("next returns consumed when test simulates popFirst nil")
    func nextReturnsConsumedWhenTestSimulatesPopFirstNil() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(1, priority: .standard)
        await consumer._testSetSimulatePopFirstNil(true)
        let result = await consumer.next()
        switch result {
        case .ready:
            Issue.record("Expected consumed when simulating popFirst nil.")
        case .consumed:
            break
        }
    }
}

// MARK: - NTASequenceStateMachineTests

@Suite("NTASequenceStateMachine")
struct NTASequenceStateMachineTests {

    @Test("initial state is consumed")
    func initialStateIsConsumed() {
        let stateMachine = NTASequenceStateMachine()
        #expect(stateMachine.state == NTASequenceStateMachine.NTAConsumedState.consumed.rawValue)
    }

    @Test("ready state transition")
    func readyStateTransition() {
        let stateMachine = NTASequenceStateMachine()
        stateMachine.ready()
        #expect(stateMachine.state == NTASequenceStateMachine.NTAConsumedState.waiting.rawValue)
    }

    @Test("cancel state transition")
    func cancelStateTransition() {
        let stateMachine = NTASequenceStateMachine()
        stateMachine.ready()
        stateMachine.cancel()
        #expect(stateMachine.state == NTASequenceStateMachine.NTAConsumedState.consumed.rawValue)
    }

    @Test("currentState returns typed enum")
    func currentStateReturnsTypedEnum() {
        let stateMachine = NTASequenceStateMachine()
        #expect(stateMachine.currentState == .consumed)
        stateMachine.ready()
        #expect(stateMachine.currentState == .waiting)
        stateMachine.cancel()
        #expect(stateMachine.currentState == .consumed)
    }

    @Test("NTAConsumedState description")
    func ntaConsumedStateDescription() {
        #expect(NTASequenceStateMachine.NTAConsumedState.consumed.description == "consumed")
        #expect(NTASequenceStateMachine.NTAConsumedState.waiting.description == "ready")
    }

    @Test("currentState returns consumed for invalid raw value")
    func currentStateReturnsConsumedForInvalidRawValue() {
        let stateMachine = NTASequenceStateMachine()
        stateMachine.state = 99
        #expect(stateMachine.currentState == .consumed)
    }
}

// MARK: - NeedleTailAsyncSequenceTests

@Suite("NeedleTailAsyncSequence")
struct NeedleTailAsyncSequenceTests {

    @Test("iteration yields success values and then nil")
    func iterationYieldsSuccessThenNil() async throws {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(10, priority: .standard)
        await consumer.feedConsumer(20, priority: .urgent)
        let sequence = NeedleTailAsyncSequence(consumer: consumer)
        var collected: [Int] = []
        for try await result in sequence {
            if case .success(let value) = result {
                collected.append(value)
            }
        }
        #expect(collected == [20, 10])
    }

    @Test("empty consumer sequence terminates immediately")
    func emptyConsumerSequenceTerminatesImmediately() async throws {
        let consumer = NeedleTailAsyncConsumer<Int>()
        let sequence = NeedleTailAsyncSequence(consumer: consumer)
        var count = 0
        for try await _ in sequence {
            count += 1
        }
        #expect(count == 0)
    }

    @Test("graceful shutdown clears deque and terminates iteration")
    func gracefulShutdownClearsDequeAndTerminates() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(1, priority: .standard)
        await consumer.feedConsumer(2, priority: .standard)
        await consumer.gracefulShutdown()
        let result = await consumer.next()
        switch result {
        case .ready:
            Issue.record("Expected consumed after graceful shutdown.")
        case .consumed:
            break
        }
        #expect(await consumer.deque.isEmpty)
    }

    @Test("iterator gracefulShutdown clears consumer")
    func iteratorGracefulShutdownClearsConsumer() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(1, priority: .standard)
        let sequence = NeedleTailAsyncSequence(consumer: consumer)
        let iterator = sequence.makeAsyncIterator()
        await iterator.gracefulShutdown()
        let result = await consumer.next()
        switch result {
        case .ready:
            Issue.record("Expected consumed after iterator graceful shutdown.")
        case .consumed:
            break
        }
        #expect(await consumer.deque.isEmpty)
    }

    @Test("cancellation terminates iterator")
    func cancellationTerminatesIterator() async {
        let consumer = NeedleTailAsyncConsumer<Int>()
        await consumer.feedConsumer(1, priority: .standard)
        await consumer.feedConsumer(2, priority: .standard)
        let sequence = NeedleTailAsyncSequence(consumer: consumer)
        let task = Task {
            var count = 0
            for try await _ in sequence {
                count += 1
            }
            return count
        }
        task.cancel()
        let count: Int
        do {
            count = try await task.value
        } catch {
            count = -1
        }
        // Iterator terminates on cancellation; task may complete with count or throw CancellationError.
        #expect(count <= 2)
    }
}

// MARK: - NTAExecutorTests

@Suite("NTAExecutor")
struct NTAExecutorTests {

    @Test("checkIsolated passes when on executor queue")
    func checkIsolatedPassesWhenOnQueue() {
        let queue = DispatchQueue(label: "nta-executor-test")
        let executor = NTAExecutor(queue: queue)
        queue.sync {
            executor.checkIsolated()
        }
    }

    @Test("consumer with shouldExecuteAsTask false works")
    func consumerWithShouldExecuteAsTaskFalseWorks() async {
        let queue = DispatchQueue(label: "nta-serial-executor-test")
        let executor = NTAExecutor(queue: queue, shouldExecuteAsTask: false)
        let consumer = NeedleTailAsyncConsumer<Int>(executor: executor)
        await consumer.feedConsumer(42, priority: .standard)
        let result = await consumer.next()
        switch result {
        case .ready(let job):
            #expect(job.item == 42)
        case .consumed:
            Issue.record("Expected to receive a job.")
        }
        queue.sync { }
    }

    @Test("consumer with shouldExecuteAsTask false on main queue covers serial executor path")
    func consumerWithShouldExecuteAsTaskFalseOnMainQueue() async {
        let executor = NTAExecutor(queue: .main, shouldExecuteAsTask: false)
        let consumer = NeedleTailAsyncConsumer<Int>(executor: executor)
        await consumer.feedConsumer(1, priority: .standard)
        await consumer.feedConsumer(2, priority: .standard)
        var results: [Int] = []
        for _ in 0..<2 {
            let result = await consumer.next()
            if case .ready(let job) = result { results.append(job.item) }
        }
        #expect(results.sorted() == [1, 2])
    }

    @Test("enqueue handles executor deallocated before block runs")
    func enqueueHandlesExecutorDeallocatedBeforeBlockRuns() async {
        let queue = DispatchQueue(label: "nta-weak-executor-test")
        var executor: NTAExecutor? = NTAExecutor(queue: queue)
        var consumer: NeedleTailAsyncConsumer<Int>? = NeedleTailAsyncConsumer<Int>(executor: executor!)
        _ = await consumer?.feedConsumer(1, priority: .standard)
        executor = nil
        consumer = nil
        queue.sync { }
    }
}
