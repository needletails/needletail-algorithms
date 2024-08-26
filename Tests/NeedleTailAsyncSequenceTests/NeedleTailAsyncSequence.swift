import XCTest
import DequeModule

@testable import NeedleTailAsyncSequence

final class NeedleTailAsyncConsumerTests: XCTestCase {
    
    var consumer: NeedleTailAsyncConsumer<Int>!
    
    override func setUp() {
        super.setUp()
        consumer = NeedleTailAsyncConsumer<Int>()
    }
    
    override func tearDown() {
        consumer = nil
        super.tearDown()
    }
    
    func testFeedConsumerWithUrgentPriority() async {
        await consumer.feedConsumer(1, priority: .urgent)
        let result = await consumer.next()
        
        switch result {
        case .ready(let job):
            XCTAssertEqual(job.item, 1)
            XCTAssertEqual(job.priority, .urgent)
        case .consumed:
            XCTFail("Expected to receive a job but got consumed.")
        }
    }
    
    func testFeedConsumerWithStandardPriority() async {
        await consumer.feedConsumer(2, priority: .standard)
        await consumer.feedConsumer(3, priority: .urgent) // Higher priority
        
        let result = await consumer.next()
        
        switch result {
        case .ready(let job):
            XCTAssertEqual(job.item, 3) // Should return the urgent job first
            XCTAssertEqual(job.priority, .urgent)
        case .consumed:
            XCTFail("Expected to receive a job but got consumed.")
        }
    }
    
    func testFeedConsumerWithUtilityPriority() async {
        await consumer.feedConsumer(4, priority: .utility)
        await consumer.feedConsumer(5, priority: .standard) // Should be inserted before utility
        
        let result = await consumer.next()
        
        switch result {
        case .ready(let job):
            XCTAssertEqual(job.item, 5) // Should return the standard job first
            XCTAssertEqual(job.priority, .standard)
        case .consumed:
            XCTFail("Expected to receive a job but got consumed.")
        }
    }
    
    func testFeedConsumerWithBackgroundPriority() async {
        await consumer.feedConsumer(6, priority: .background)
        let result = await consumer.next()
        
        switch result {
        case .ready(let job):
            XCTAssertEqual(job.item, 6)
            XCTAssertEqual(job.priority, .background)
        case .consumed:
            XCTFail("Expected to receive a job but got consumed.")
        }
    }
    
    func testNextReturnsConsumedWhenDequeIsEmpty() async {
        let result = await consumer.next()
        switch result {
        case .ready:
            XCTFail("Expected consumed but got a job.")
        case .consumed:
            XCTAssertTrue(true) // This is the expected outcome
        }
    }
}

final class NTASequenceStateMachineTests: XCTestCase {
    
    var stateMachine: NTASequenceStateMachine!
    
    override func setUp() {
        super.setUp()
        stateMachine = NTASequenceStateMachine()
    }
    
    override func tearDown() {
        stateMachine = nil
        super.tearDown()
    }
    
    func testInitialStateIsConsumed() {
        XCTAssertEqual(stateMachine.state, NTASequenceStateMachine.NTAConsumedState.consumed.rawValue)
    }
    
    func testReadyStateTransition() {
        stateMachine.ready()
        XCTAssertEqual(stateMachine.state, NTASequenceStateMachine.NTAConsumedState.waiting.rawValue)
    }
    
    func testCancelStateTransition() {
        stateMachine.ready()
        stateMachine.cancel()
        XCTAssertEqual(stateMachine.state, NTASequenceStateMachine.NTAConsumedState.consumed.rawValue)
    }
}
