//
//  NTKLoop.swift
//  NeedleTailAlgorithms
//
//  Time-bounded, cancellable async and sync run loops with configurable sleep and clock.
//

import Foundation

// MARK: - TaskObjectProtocol

/// Protocol for values returned from `runReturningLoop`. Conforming types must be `Sendable`.
public protocol TaskObjectProtocol: Sendable {}

// MARK: - NTKLoop

/// A time-bounded, cancellable run loop that repeatedly executes a callback until it returns "stop",
/// the deadline expires, or the task is cancelled.
///
/// Use `run(_:sleep:tolerance:suspendingClock:checkImmediately:stopRunning:)` for fire-and-forget loops,
/// or `runReturningLoop(expiresIn:sleep:...)` when you need a single value when the loop stops.
///
/// - **Cancellation**: Loops respect Swift concurrency cancellation. When the calling task is cancelled,
///   the loop task is cancelled and the method throws `CancellationError`.
/// - **Clocks**: Use `suspendingClock: true` so sleep does not count toward system uptime (e.g. when the device is asleep).
/// - **Expiry**: Pass `nil` for `expiresIn` (run only) for no time limit; pass a positive value in seconds.
///   Zero or negative yields a deadline at or in the past; the loop may run zero or one iteration.
public actor NTKLoop {

    public init() {}

    /// Result of the internal loop condition (finished vs still running).
    /// - Note: Case `runnning` is kept for backward compatibility (historical typo).
    public enum LoopResult: Sendable {
        case finished
        case runnning
    }

    /// Errors thrown by the loop API.
    public enum Errors: Error, Sendable {
        /// Return value could not be produced (reserved for future use).
        case cannotGetReturnable
    }

    // MARK: - Time and condition helpers

    /// Returns the deadline date for a given time interval from now.
    ///
    /// - Parameter timeInterval: Duration in seconds from now. `nil` means no deadline.
    /// - Returns: `Date(timeIntervalSinceNow: timeInterval)` or `nil` if `timeInterval` is `nil`.
    ///   For zero or negative, the returned date is at or in the past (loop may run zero or one iteration).
    public static func timeInterval(_ timeInterval: TimeInterval?) -> Date? {
        guard let timeInterval else { return nil }
        return Date(timeIntervalSinceNow: timeInterval)
    }

    /// Determines whether the loop should continue: `canRun` must be true and the expiry date (if any) must not be passed.
    ///
    /// - Parameters:
    ///   - expriedDate: Deadline; loop stops when `Date() >= expriedDate`. Pass `nil` for no time limit.
    ///   - canRun: When `false`, the loop stops regardless of time.
    /// - Returns: `true` to continue the loop, `false` to exit.
    public static func execute(
        _ expriedDate: Date?,
        canRun: Bool
    ) async -> Bool {
        guard canRun else { return false }
        guard let expriedDate else { return true }
        return expriedDate >= Date()
    }

    // MARK: - Async run (void)

    /// Runs a loop until the callback returns `false`, the deadline is reached, or the task is cancelled.
    ///
    /// Each iteration: optionally sleep, then call `stopRunning()`. The callback’s return value means
    /// "continue running" (`true`) or "stop and exit" (`false`). Errors from the callback are propagated.
    ///
    /// - Parameters:
    ///   - expiresIn: Maximum run time in seconds. `nil` = no limit. Zero or negative = deadline at or in the past (may run 0 or 1 iteration).
    ///   - sleep: Delay between iterations. Use `.zero` for minimal delay (still yields to the executor).
    ///   - tolerance: Allowed tolerance for the sleep (system may wake slightly early).
    ///   - suspendingClock: If `true`, use `.suspending` clock so sleep doesn’t advance while the system is suspended.
    ///   - checkImmediately: If `true`, call `stopRunning()` once before the first sleep; otherwise sleep first, then call.
    ///   - stopRunning: Called each iteration. Return `true` to continue, `false` to stop. Throws cancel the loop.
    /// - Throws: Any error thrown by `stopRunning`, or `CancellationError` if the task is cancelled.
    public func run(
        _ expiresIn: TimeInterval?,
        sleep: Duration,
        tolerance: Duration = .zero,
        suspendingClock: Bool = false,
        checkImmediately: Bool = false,
        stopRunning: @Sendable @escaping () async throws -> Bool
    ) async throws {
        let task = Task<Void, Error> {
            try Task.checkCancellation()
            let date = NTKLoop.timeInterval(expiresIn)
            var canRun = true
            var didInitialCheck = false

            while await NTKLoop.execute(date, canRun: canRun) {
                try Task.checkCancellation()

                if checkImmediately, !didInitialCheck {
                    didInitialCheck = true
                    canRun = try await stopRunning()
                    continue
                }

                if suspendingClock {
                    try await Task.sleep(until: .now + sleep, tolerance: tolerance, clock: .suspending)
                } else {
                    try await Task.sleep(until: .now + sleep, tolerance: tolerance, clock: .continuous)
                }

                canRun = try await stopRunning()
            }
        }
        defer { task.cancel() }

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Async run (returning value)

    /// Runs a loop like `run` but returns a value of type `T?` when the callback signals stop or when the loop expires.
    ///
    /// The callback returns `(continueRunning, value)`. When `continueRunning` is `false`, the loop exits and returns `value`.
    /// If the deadline is reached first, the loop returns `nil`.
    ///
    /// - Parameters:
    ///   - expiresIn: Maximum run time in seconds. Zero or negative gives a deadline at or in the past (may return without running or after one iteration).
    ///   - sleep: Delay between iterations.
    ///   - tolerance: Sleep tolerance.
    ///   - suspendingClock: Use suspending clock when `true`.
    ///   - checkImmediately: If `true`, call the callback once before the first sleep.
    ///   - stopRunning: Returns `(true, _)` to continue, `(false, value)` to stop and return `value`.
    /// - Returns: The value returned with `(false, value)` from the callback, or `nil` if the loop expired or never ran.
    /// - Throws: Errors from the callback or `CancellationError` on cancellation.
    public func runReturningLoop<T: TaskObjectProtocol>(
        expiresIn: TimeInterval,
        sleep: Duration,
        tolerance: Duration = .zero,
        suspendingClock: Bool = false,
        checkImmediately: Bool = false,
        stopRunning: @Sendable @escaping () async throws -> (Bool, T?)
    ) async throws -> T? {
        let task = Task<T?, Error> {
            try Task.checkCancellation()
            let date = NTKLoop.timeInterval(expiresIn)
            var canRun = true
            var didInitialCheck = false

            while await NTKLoop.execute(date, canRun: canRun) {
                try Task.checkCancellation()

                if checkImmediately, !didInitialCheck {
                    didInitialCheck = true
                    let (isRunning, bundle) = try await stopRunning()
                    canRun = isRunning
                    if !isRunning { return bundle }
                    continue
                }

                if suspendingClock {
                    try await Task.sleep(until: .now + sleep, tolerance: tolerance, clock: .suspending)
                } else {
                    try await Task.sleep(until: .now + sleep, tolerance: tolerance, clock: .continuous)
                }

                let (isRunning, bundle) = try await stopRunning()
                canRun = isRunning
                if !isRunning { return bundle }
            }

            return nil
        }
        defer { task.cancel() }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

// MARK: - RunSyncLoop

/// Synchronous, time-bounded run loop. Runs on the current thread and blocks until the callback returns `false` or the deadline is reached.
///
/// Use for polling on a background thread. Avoid calling from the main thread if the callback or sleep can be long.
/// When `sleep` is zero, `Thread.sleep(forTimeInterval: 0)` is used so the loop yields without busy-spinning.
public final class RunSyncLoop: Sendable {

    /// Result of the synchronous loop condition.
    /// - Note: Case `runnning` is kept for backward compatibility (historical typo).
    public enum LoopResult: Sendable {
        case finished
        case runnning
    }

    /// Deadline date for the given interval from now.
    public static func timeInterval(_ timeInterval: TimeInterval) -> Date {
        Date(timeIntervalSinceNow: timeInterval)
    }

    /// Whether the sync loop should continue: `canRun` must be true and current time must be before the expiry date.
    public static func executeSynchronously(
        _ expriedDate: Date,
        canRun: Bool
    ) -> Bool {
        guard canRun else { return false }
        return expriedDate >= Date()
    }

    /// Runs a synchronous loop until the callback returns `false` or the deadline is reached.
    ///
    /// - Parameters:
    ///   - expiresIn: Maximum run time in seconds.
    ///   - sleep: Seconds to sleep between iterations. Use `0` to yield without a fixed delay.
    ///   - stopRunning: Return `true` to continue, `false` to stop. Thrown errors propagate.
    /// - Throws: Any error thrown by `stopRunning`.
    public static func runSync(
        _ expiresIn: TimeInterval,
        sleep: TimeInterval = 0,
        stopRunning: @Sendable @escaping () throws -> Bool
    ) throws {
        let date = RunSyncLoop.timeInterval(expiresIn)
        var canRun = true
        while RunSyncLoop.executeSynchronously(date, canRun: canRun) {
            canRun = try stopRunning()
            if canRun {
                if sleep > 0 {
                    Thread.sleep(forTimeInterval: sleep)
                } else {
                    Thread.sleep(forTimeInterval: 0)
                }
            }
        }
    }
}
