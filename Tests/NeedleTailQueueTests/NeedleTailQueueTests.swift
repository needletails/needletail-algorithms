import Foundation
import Testing
@testable import NeedleTailQueue

// MARK: - NeedleTailStack (actor)

@Suite("NeedleTailStack")
struct NeedleTailStackTests {

    @Test("FIFO order: dequeue returns elements in enqueue order")
    func fifoOrder() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2, 3])
        #expect(await stack.dequeue() == 1)
        #expect(await stack.dequeue() == 2)
        #expect(await stack.dequeue() == 3)
        #expect(await stack.dequeue() == nil)
    }

    @Test("peek does not remove")
    func peekDoesNotRemove() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(42)
        #expect(await stack.peek() == 42)
        #expect(await stack.peek() == 42)
        #expect(await stack.dequeue() == 42)
        #expect(await stack.peek() == nil)
    }

    @Test("popFirst removes from opposite end (newest first)")
    func popFirstRemoves() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2, 3])
        // popFirst() returns from the "first" end of internal dequeue (newest enqueued first)
        #expect(await stack.popFirst() == 3)
        #expect(await stack.popFirst() == 2)
        #expect(await stack.dequeue() == 1)  // dequeue returns oldest
        #expect(await stack.popFirst() == nil)
    }

    @Test("toArray returns FIFO order")
    func toArrayFifoOrder() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2, 3])
        let arr = await stack.toArray()
        #expect(arr == [1, 2, 3])
    }

    @Test("drain and clear empty the stack")
    func drainAndClear() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2, 3])
        await stack.drain()
        #expect(await stack.isEmpty() == true)
        #expect(await stack.dequeue() == nil)
        await stack.enqueue(4)
        await stack.clear()
        #expect(await stack.isEmpty() == true)
    }

    @Test("enqueue with both nil does nothing")
    func enqueueBothNil() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(nil, elements: nil)
        #expect(await stack.isEmpty() == true)
    }

    @Test("count and contains")
    func countAndContains() async {
        let stack = NeedleTailStack<Int>()
        #expect(await stack.count() == 0)
        await stack.enqueue(elements: [1, 2, 3])
        #expect(await stack.count() == 3)
        #expect(await stack.contains(2) == true)
        #expect(await stack.contains(99) == false)
    }

    @Test("isEmpty is false when stack has elements")
    func isEmptyWhenNonEmpty() async {
        let stack = NeedleTailStack<Int>()
        #expect(await stack.isEmpty() == true)
        await stack.enqueue(1)
        #expect(await stack.isEmpty() == false)
        _ = await stack.dequeue()
        #expect(await stack.isEmpty() == true)
    }

    @Test("toArray after partial dequeue returns remaining in FIFO order")
    func toArrayAfterPartialDequeue() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2, 3, 4])
        _ = await stack.dequeue()
        _ = await stack.dequeue()
        let arr = await stack.toArray()
        #expect(arr == [3, 4])
    }

    @Test("debugDescription returns string and contains NeedleTailStack")
    func debugDescription() async {
        let stack = NeedleTailStack<Int>()
        await stack.enqueue(elements: [1, 2])
        let desc = await stack.debugDescription()
        #expect(desc.contains("NeedleTailStack"))
        #expect(desc.contains("1"))
        #expect(desc.contains("2"))
    }
}

// MARK: - SyncStack (struct)

@Suite("SyncStack")
struct SyncStackTests {

    @Test("FIFO order: dequeue returns elements in enqueue order")
    func fifoOrder() {
        var sync = SyncStack<Int>()
        sync.enqueue(elements: [1, 2, 3])
        #expect(sync.dequeue() == 1)
        #expect(sync.dequeue() == 2)
        #expect(sync.dequeue() == 3)
        #expect(sync.dequeue() == nil)
    }

    @Test("peek does not remove")
    func peekDoesNotRemove() {
        var sync = SyncStack<Int>()
        sync.enqueue(42)
        #expect(sync.peek() == 42)
        #expect(sync.peek() == 42)
        #expect(sync.dequeue() == 42)
        #expect(sync.peek() == nil)
    }

    @Test("popFirst removes from opposite end (newest first)")
    func popFirstRemoves() {
        var sync = SyncStack<Int>()
        sync.enqueue(elements: [1, 2, 3])
        #expect(sync.popFirst() == 3)
        #expect(sync.popFirst() == 2)
        #expect(sync.dequeue() == 1)
        #expect(sync.popFirst() == nil)
    }

    @Test("peekFirst does not remove")
    func peekFirstDoesNotRemove() {
        var sync = SyncStack<Int>()
        sync.enqueue(elements: [1, 2, 3])
        // peekFirst returns next that popFirst would return (newest enqueued)
        #expect(sync.peekFirst() == 3)
        #expect(sync.peekFirst() == 3)
        #expect(sync.popFirst() == 3)
        #expect(sync.peekFirst() == 2)
    }

    @Test("drain empties the stack")
    func drain() {
        var sync = SyncStack<Int>()
        sync.enqueue(elements: [1, 2, 3])
        sync.drain()
        #expect(sync.isEmpty() == true)
        #expect(sync.dequeue() == nil)
    }

    @Test("isEmpty is false when stack has elements")
    func isEmptyWhenNonEmpty() {
        var sync = SyncStack<Int>()
        #expect(sync.isEmpty() == true)
        sync.enqueue(1)
        #expect(sync.isEmpty() == false)
        _ = sync.dequeue()
        #expect(sync.isEmpty() == true)
    }

    @Test("enqueue with both nil does nothing")
    func enqueueBothNil() {
        var sync = SyncStack<Int>()
        sync.enqueue(nil, elements: nil)
        #expect(sync.isEmpty() == true)
    }
}
