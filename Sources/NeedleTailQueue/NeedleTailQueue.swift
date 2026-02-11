//
//  NeedleTailQueue.swift
//
//
//  Created by Cole M on 4/16/22.
//
import Foundation
import Collections

public protocol NeedleTailQueue: Sendable {
    associatedtype Element: Sendable
    func enqueue(_ element: Element?, elements: [Element]?) async
    func dequeue() async -> Element?
    func popFirst() async -> Element?
    func drain() async
    func isEmpty() async -> Bool
    func peek() async -> Element?
}

/// A stack implementation using a double-ended queue (Deque) for efficient operations.
public actor NeedleTailStack<T: Sendable & Equatable>: NeedleTailQueue {
    
    // Initialize the stack with empty deques for enqueue and dequeue
    private var enqueueDeque = Deque<T>()
    private var dequeueDeque = Deque<T>()
    
    public init() {}
    
    /// Moves elements from enqueueDeque to dequeueDeque when dequeue side is empty (FIFO flip).
    private func flipToDequeueDequeIfNeeded() {
        guard dequeueDeque.isEmpty else { return }
        while !enqueueDeque.isEmpty {
            if let element = enqueueDeque.popLast() {
                dequeueDeque.append(element)
            }
        }
    }
    
    // MARK: - NeedleTailQueue Protocol Methods
    
    /// Enqueues an optional element or an array of elements into the stack.
    /// If both `element` and `elements` are nil, no change is made.
    /// - Parameters:
    ///   - element: An optional single element to enqueue.
    ///   - elements: An optional array of elements to enqueue.
    public func enqueue(_ element: T? = nil, elements: [T]? = nil) async {
        if let element = element {
            enqueueDeque.append(element)
        } else if let elements = elements {
            enqueueDeque.append(contentsOf: elements)
        }
    }
    
    /// Dequeues and returns the next element from the stack.
    /// - Returns: The next element, or `nil` if the stack is empty.
    public func dequeue() async -> T? {
        flipToDequeueDequeIfNeeded()
        return dequeueDeque.popLast()
    }
    
    /// Removes and returns the first element from the stack.
    /// - Returns: The first element, or `nil` if the stack is empty.
    public func popFirst() async -> T? {
        flipToDequeueDequeIfNeeded()
        return dequeueDeque.popFirst()
    }
    
    /// Clears all elements from the stack.
    public func drain() async {
        enqueueDeque.removeAll()
        dequeueDeque.removeAll()
    }
    
    /// Checks if the stack is empty.
    /// - Returns: A Boolean value indicating whether the stack is empty.
    public func isEmpty() async -> Bool {
        return enqueueDeque.isEmpty && dequeueDeque.isEmpty
    }
    
    /// Peeks at the next element in the stack without removing it.
    /// - Returns: The next element, or `nil` if the stack is empty.
    public func peek() async -> T? {
        return dequeueDeque.last ?? enqueueDeque.first
    }
    
    // MARK: - Additional Methods
    
    /// Returns the total number of elements in the stack.
    /// - Returns: The total count of elements in the stack.
    public func count() async -> Int {
        return enqueueDeque.count + dequeueDeque.count
    }
    
    /// Clears all elements from the stack.
    public func clear() async {
        await drain()
    }
    
    /// Checks if a specific element exists in the stack.
    /// - Parameter element: The element to check for.
    /// - Returns: A Boolean value indicating whether the element exists in the stack.
    public func contains(_ element: T) async -> Bool {
        return enqueueDeque.contains(element) || dequeueDeque.contains(element)
    }
    
    /// Returns the elements in FIFO order (order in which they would be dequeued).
    /// - Returns: An array containing the elements of the stack.
    public func toArray() async -> [T] {
        return Array(dequeueDeque.reversed()) + Array(enqueueDeque)
    }
    
    /// Provides a string representation of the stack for debugging purposes.
    /// - Returns: A string representation of the stack.
    public func debugDescription() async -> String {
        let elements = await toArray()
        return "NeedleTailStack: \(elements)"
    }
}


public enum ConsumptionState: Sendable {
    case consuming, enquing, dequing, draining, ready, empty
}

public protocol SyncQueue: Sendable {
    associatedtype Element
    mutating func enqueue(_ element: Element?, elements: [Element]?)
    mutating func dequeue() -> Element?
    mutating func popFirst() -> Element?
    mutating func drain()
    mutating func isEmpty() -> Bool
    mutating func peek() -> Element?
}


public struct SyncStack<T: Sendable>: SyncQueue, Sendable  {
    
    public init() {}
    
    public var enqueueStack: [T] = []
    public var dequeueStack: [T] = []
    public var consumptionState = ConsumptionState.empty
    
    public mutating func isEmpty() -> Bool {
        return dequeueStack.isEmpty && enqueueStack.isEmpty
    }
    
    public mutating func peek() -> T? {
        return !dequeueStack.isEmpty ? dequeueStack.last : enqueueStack.first
    }

    /// Peeks at the first element (next from popFirst) without removing it.
    /// - Returns: The first element, or `nil` if the stack is empty.
    public func peekFirst() -> T? {
        if !dequeueStack.isEmpty {
            return dequeueStack.first
        }
        return enqueueStack.last
    }

    public mutating func enqueue(_ element: T? = nil, elements: [T]? = nil) {
        consumptionState = .enquing
        if let element = element {
            enqueueStack.append(element)
        } else if let elements = elements {
            enqueueStack.append(contentsOf: elements)
        }
    }
    
    public mutating func dequeue() -> T? {
        consumptionState = .draining
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        
        if !dequeueStack.isEmpty {
            return dequeueStack.popLast()
        } else {
            consumptionState = .ready
            return nil
        }
    }
    
    public mutating func popFirst() -> T? {
        consumptionState = .draining
        if dequeueStack.isEmpty {
            dequeueStack = enqueueStack.reversed()
            enqueueStack.removeAll()
        }
        if !dequeueStack.isEmpty {
            return dequeueStack.removeFirst()
        } else {
            consumptionState = .ready
            return nil
        }
    }

    
    public mutating func drain() {
        enqueueStack.removeAll()
        dequeueStack.removeAll()
    }
}
