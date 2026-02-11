# NTKLoop

Time-bounded, cancellable run loops for Swift concurrency and synchronous polling.

## Overview

**NTKLoop** provides:

- **`NTKLoop`** (actor): Async run loops that repeat a callback until it returns "stop", a deadline is reached, or the task is cancelled. Supports configurable sleep, clock (continuous vs suspending), and optional "check immediately" before the first sleep.
- **`RunSyncLoop`**: Synchronous, blocking run loops for polling on a background thread with optional sleep to avoid busy-spinning.

Use NTKLoop for:

- Polling a condition or server until a result is ready or a timeout expires
- Running a repeating task with a fixed interval and a maximum duration
- Getting a single value when a loop stops (e.g. "first result" or "final state") via `runReturningLoop`

## Requirements

- Swift 6
- iOS 18+ / macOS 15+

## Adding to Your Project

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/needletails/needletail-algorithms.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "NTKLoop", package: "needletail-algorithms"),
    ]),
]
```

## Usage

### Async loop (fire-and-forget)

```swift
let loop = NTKLoop()

try await loop.run(
    30,                          // expire in 30 seconds (nil = no limit)
    sleep: .seconds(1),
    checkImmediately: true       // run callback once before first sleep
) {
    let done = await checkCondition()
    return !done                 // true = keep running, false = stop
}
```

### Async loop that returns a value

```swift
struct Result: TaskObjectProtocol { let id: String }

let loop = NTKLoop()
let value: Result? = try await loop.runReturningLoop(
    expiresIn: 10,
    sleep: .milliseconds(200),
    checkImmediately: true
) {
    let (item, done) = await fetchNext()
    if done {
        return (false, item)      // stop and return item
    }
    return (true, nil)           // keep running
}
// value is the returned item or nil if the loop expired
```

### Synchronous loop (e.g. background thread)

```swift
try RunSyncLoop.runSync(5, sleep: 0.1) {
    let shouldContinue = doWork()
    return shouldContinue
}
```

### Cancellation

Async loops respect Swift task cancellation. When the calling task is cancelled, the loop task is cancelled and the method throws `CancellationError`.

```swift
let task = Task {
    try await loop.run(60, sleep: .seconds(1)) { ... }
}
task.cancel()
// loop exits and run(...) throws CancellationError
```

### Clocks

- **Continuous (default)**: Sleep advances with wall clock time. Use for timers and real-time intervals.
- **Suspending**: Pass `suspendingClock: true` so sleep does not advance while the system is suspended (e.g. device asleep). Use for "run for N seconds of active time."

### Expiry semantics

- **`expiresIn: nil`** (run only): No time limit; loop runs until the callback returns `false` or the task is cancelled.
- **`expiresIn: 0` or negative**: Deadline is at or in the past; the loop may run zero or one iteration (backward compatible).
- **`expiresIn: positive`**: Loop stops when `Date() >= deadline`. The callback may be called up to and including that time.

### Sync loop and CPU usage

- **`sleep: 0`**: Uses `Thread.sleep(forTimeInterval: 0)` so the thread yields without busy-spinning.
- **`sleep: > 0`**: Sleeps for that many seconds between iterations. Use to throttle polling and avoid pegging the CPU.

## API summary

| API | Description |
|-----|-------------|
| `NTKLoop()` | Create an actor instance. |
| `run(_:sleep:tolerance:suspendingClock:checkImmediately:stopRunning:)` | Async loop; callback returns `true` to continue, `false` to stop. |
| `runReturningLoop(expiresIn:sleep:... stopRunning:)` | Async loop that returns a `TaskObjectProtocol?` when the callback signals stop or on expiry. |
| `NTKLoop.timeInterval(_:)` | Convert a `TimeInterval?` to a deadline `Date?`. |
| `NTKLoop.execute(_:canRun:)` | Low-level: returns whether the loop should continue (canRun and not expired). |
| `RunSyncLoop.runSync(_:sleep:stopRunning:)` | Synchronous loop; blocks until callback returns `false` or deadline. |
| `RunSyncLoop.timeInterval(_:)` | Deadline `Date` for a given interval. |
| `RunSyncLoop.executeSynchronously(_:canRun:)` | Sync condition check. |

## Thread safety

- **NTKLoop** is an actor; all methods are isolated to that actor. Safe to use from any concurrency context.
- **RunSyncLoop** is a `Sendable` class with static methods; use from any thread, but avoid long-running or blocking callbacks on the main thread.

## License

See the repository license.
