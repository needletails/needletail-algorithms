import Foundation
import Testing
import Atomics
@testable import NTKLoop

// MARK: - Test types

private struct Bundle: TaskObjectProtocol, Equatable {
    let value: Int
}

// MARK: - NTKLoop.run

@Suite("NTKLoop run")
struct NTKLoopRunTests {

    @Test("stops when stopRunning returns false")
    func stopsWhenStopRunningReturnsFalse() async throws {
        let loop = NTKLoop()
        let calls = ManagedAtomicCounter()

        try await loop.run(
            2,
            sleep: .milliseconds(10),
            checkImmediately: true
        ) {
            await calls.increment()
            return false
        }

        let count = await calls.currentValue()
        #expect(count == 1)
    }

    @Test("iterates multiple times when returning true")
    func iteratesMultipleTimesWhenReturningTrue() async throws {
        let loop = NTKLoop()
        let calls = ManagedAtomicCounter()
        let maxCalls = 5

        try await loop.run(
            2,
            sleep: .milliseconds(5),
            checkImmediately: true
        ) {
            let n = await calls.incrementAndGet()
            return n < maxCalls
        }

        let count = await calls.currentValue()
        #expect(count == maxCalls)
    }

    @Test("propagates thrown error")
    func propagatesThrownError() async {
        enum TestError: Error, Equatable { case boom }
        let loop = NTKLoop()

        await #expect(throws: TestError.self) {
            try await loop.run(
                2,
                sleep: .milliseconds(10),
                checkImmediately: true
            ) {
                throw TestError.boom
            }
        }
    }

    @Test("cancellation cancels underlying task")
    func cancellationCancelsUnderlyingTask() async {
        let loop = NTKLoop()
        var task: Task<Void, Error>?

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            task = Task {
                do {
                    try await loop.run(
                        60,
                        sleep: .seconds(5),
                        checkImmediately: true
                    ) {
                        cont.resume()
                        return true
                    }
                } catch is CancellationError {
                    // expected
                } catch {}
            }
        }
        task?.cancel()
        _ = await task?.result
    }

    @Test("nil expiresIn runs until callback returns false")
    func nilExpiresInRunsUntilCallbackReturnsFalse() async throws {
        let loop = NTKLoop()
        let count = ManagedAtomicCounter()
        let stopAt = 3

        try await loop.run(
            nil,
            sleep: .milliseconds(5),
            checkImmediately: true
        ) {
            let n = await count.incrementAndGet()
            return n < stopAt
        }

        let value = await count.currentValue()
        #expect(value == stopAt)
    }

    @Test("zero expiresIn exits quickly, callback at most once")
    func zeroExpiresInExitsQuickly() async throws {
        let loop = NTKLoop()
        let callCount = ManagedAtomic<Int>(0)

        try await loop.run(
            0,
            sleep: .milliseconds(10),
            checkImmediately: true
        ) {
            _ = callCount.wrappingIncrementThenLoad(ordering: .relaxed)
            return false
        }

        // Backward compat: deadline at "now" may allow 0 or 1 iteration.
        #expect(callCount.load(ordering: .relaxed) <= 1)
    }

    @Test("negative expiresIn exits quickly, callback at most once")
    func negativeExpiresInExitsQuickly() async throws {
        let loop = NTKLoop()
        let callCount = ManagedAtomic<Int>(0)

        try await loop.run(
            -1,
            sleep: .milliseconds(10),
            checkImmediately: true
        ) {
            _ = callCount.wrappingIncrementThenLoad(ordering: .relaxed)
            return false
        }

        // Backward compat: deadline in past may allow 0 or 1 iteration.
        #expect(callCount.load(ordering: .relaxed) <= 1)
    }

    @Test("checkImmediately calls before first sleep")
    func checkImmediatelyCallsBeforeFirstSleep() async throws {
        let loop = NTKLoop()
        let callCount = ManagedAtomicCounter()

        try await loop.run(
            1,
            sleep: .milliseconds(50),
            checkImmediately: true
        ) {
            let n = await callCount.incrementAndGet()
            return n < 1
        }

        let value = await callCount.currentValue()
        #expect(value == 1)
    }

    @Test("zero sleep still completes")
    func zeroSleepStillCompletes() async throws {
        let loop = NTKLoop()
        let count = ManagedAtomicCounter()

        try await loop.run(
            0.1,
            sleep: .zero,
            checkImmediately: false
        ) {
            let n = await count.incrementAndGet()
            return n < 3
        }

        let value = await count.currentValue()
        #expect(value >= 3)
    }

    @Test("respects expiry")
    func respectsExpiry() async throws {
        let loop = NTKLoop()
        let count = ManagedAtomicCounter()
        let start = Date()

        try await loop.run(
            0.15,
            sleep: .milliseconds(20),
            checkImmediately: false
        ) {
            _ = await count.incrementAndGet()
            return true
        }

        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.12, "Should run for roughly expiresIn")
        let iterations = await count.currentValue()
        #expect(iterations >= 3, "Should have multiple iterations before expiry")
    }
}

// MARK: - NTKLoop.runReturningLoop

@Suite("NTKLoop runReturningLoop")
struct NTKLoopRunReturningTests {

    @Test("returns bundle when stopRunning returns false")
    func returnsBundleWhenStopRunningReturnsFalse() async throws {
        let loop = NTKLoop()

        let result = try await loop.runReturningLoop(
            expiresIn: 2,
            sleep: .milliseconds(10),
            checkImmediately: true
        ) {
            (false, Bundle(value: 42))
        }

        #expect(result == Bundle(value: 42))
    }

    @Test("returns nil on expiry")
    func returnsNilOnExpiry() async throws {
        let loop = NTKLoop()
        let result = try await loop.runReturningLoop(
            expiresIn: 0.05,
            sleep: .milliseconds(100),
            checkImmediately: false
        ) {
            (true, Bundle(value: 1))
        }
        #expect(result == nil)
    }

    @Test("expiresIn 0 exits quickly, returns nil or single callback value")
    func returnsNilOrValueWhenExpiresInZero() async throws {
        let loop = NTKLoop()
        let callCount = ManagedAtomic<Int>(0)
        let result = try await loop.runReturningLoop(
            expiresIn: 0,
            sleep: .milliseconds(10),
            checkImmediately: true
        ) {
            _ = callCount.wrappingIncrementThenLoad(ordering: .relaxed)
            return (false, Bundle(value: 99))
        }
        // Backward compat: 0 deadline may run 0 or 1 iteration.
        #expect(callCount.load(ordering: .relaxed) <= 1)
        #expect(result == nil || result == Bundle(value: 99))
    }

    @Test("iterates then returns value")
    func iteratesThenReturnsValue() async throws {
        let loop = NTKLoop()
        let count = ManagedAtomic<Int>(0)

        let result = try await loop.runReturningLoop(
            expiresIn: 2,
            sleep: .milliseconds(5),
            checkImmediately: true
        ) {
            let n = count.wrappingIncrementThenLoad(ordering: .relaxed)
            if n >= 3 {
                return (false, Bundle(value: n))
            }
            return (true, nil)
        }

        #expect(result == Bundle(value: 3))
    }

    @Test("propagates error")
    func propagatesError() async {
        enum E: Error, Equatable { case err }
        let loop = NTKLoop()

        await #expect(throws: E.self) {
            let _: Bundle? = try await loop.runReturningLoop(
                expiresIn: 2,
                sleep: .milliseconds(10),
                checkImmediately: true
            ) {
                throw E.err
            }
        }
    }

    @Test("cancellation")
    func cancellation() async {
        let loop = NTKLoop()
        var task: Task<Void, Error>?

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            task = Task {
                do {
                    let _: Bundle? = try await loop.runReturningLoop(
                        expiresIn: 60,
                        sleep: .seconds(5),
                        checkImmediately: true
                    ) {
                        cont.resume()
                        return (true, nil)
                    }
                } catch is CancellationError {}
                catch {}
            }
        }
        task?.cancel()
        _ = await task?.result
    }
}

// MARK: - Helpers: timeInterval, execute

@Suite("NTKLoop helpers")
struct NTKLoopHelpersTests {

    @Test("timeInterval nil")
    func timeIntervalNil() {
        #expect(NTKLoop.timeInterval(nil) == nil)
    }

    @Test("timeInterval positive")
    func timeIntervalPositive() {
        let d = NTKLoop.timeInterval(10)
        #expect(d != nil)
        let delta = d!.timeIntervalSinceNow
        #expect(delta > 9.9)
        #expect(delta < 10.1)
    }

    @Test("timeInterval zero")
    func timeIntervalZero() {
        let d = NTKLoop.timeInterval(0)
        #expect(d != nil)
        #expect(d!.timeIntervalSinceNow <= 0.01)
    }

    @Test("execute respects canRun")
    func executeRespectsCanRun() async {
        let future = Date(timeIntervalSinceNow: 100)
        let whenCanRunFalse = await NTKLoop.execute(future, canRun: false)
        let whenCanRunTrue = await NTKLoop.execute(future, canRun: true)
        #expect(whenCanRunFalse == false)
        #expect(whenCanRunTrue == true)
    }

    @Test("execute respects expiry")
    func executeRespectsExpiry() async {
        let past = Date(timeIntervalSinceNow: -1)
        let withPast = await NTKLoop.execute(past, canRun: true)
        let withNil = await NTKLoop.execute(nil, canRun: true)
        #expect(withPast == false)
        #expect(withNil == true)
    }
}

// MARK: - RunSyncLoop

@Suite("RunSyncLoop")
struct RunSyncLoopTests {

    @Test("yields between iterations when sleep is zero")
    func yieldsBetweenIterationsWhenSleepIsZero() throws {
        let calls = ManagedAtomic<Int>(0)
        try RunSyncLoop.runSync(0.2, sleep: 0) {
            _ = calls.wrappingIncrementThenLoad(ordering: .relaxed)
            return calls.load(ordering: .relaxed) < 10
        }
        #expect(calls.load(ordering: .relaxed) >= 1)
    }

    @Test("stops when callback returns false")
    func stopsWhenCallbackReturnsFalse() throws {
        let count = ManagedAtomic<Int>(0)
        try RunSyncLoop.runSync(5, sleep: 0) {
            let n = count.wrappingIncrementThenLoad(ordering: .relaxed)
            return n < 4
        }
        #expect(count.load(ordering: .relaxed) == 4)
    }

    @Test("expires when time reached")
    func expiresWhenTimeReached() throws {
        let count = ManagedAtomic<Int>(0)
        let start = Date()
        try RunSyncLoop.runSync(0.1, sleep: 0.02) {
            _ = count.wrappingIncrementThenLoad(ordering: .relaxed)
            return true
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.09)
    }

    @Test("propagates error")
    func propagatesError() {
        struct E: Error {}
        #expect(throws: E.self) {
            try RunSyncLoop.runSync(5, sleep: 0) { throw E() }
        }
    }
}

// MARK: - Concurrency and stress

@Suite("NTKLoop concurrency")
struct NTKLoopConcurrencyTests {

    @Test("concurrent loops no shared mutable state")
    func concurrentLoopsNoSharedMutableState() async throws {
        let loop = NTKLoop()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let count = ManagedAtomic<Int>(0)
                    try? await loop.run(0.2, sleep: .milliseconds(5), checkImmediately: true) {
                        let n = count.wrappingIncrementThenLoad(ordering: .relaxed)
                        return n < 3
                    }
                }
            }
        }
    }

    @Test("stress many iterations")
    func stressManyIterations() async throws {
        let loop = NTKLoop()
        let count = ManagedAtomic<Int>(0)
        let iterations = 100

        try await loop.run(
            nil,
            sleep: .microseconds(100),
            checkImmediately: true
        ) {
            let n = count.wrappingIncrementThenLoad(ordering: .relaxed)
            return n < iterations
        }

        #expect(count.load(ordering: .relaxed) == iterations)
    }
}

// MARK: - Test helpers

private actor ManagedAtomicCounter {
    private var _count = 0
    func increment() { _count += 1 }
    func incrementAndGet() -> Int { _count += 1; return _count }
    func currentValue() -> Int { _count }
}
