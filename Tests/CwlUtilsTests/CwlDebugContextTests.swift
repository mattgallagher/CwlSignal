//
//  CwlDebugContextTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/09/13.
//  Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation
import XCTest
import CwlUtils

class DebugContextTests: XCTestCase {
	func testDirectInvoke() {
		let coordinator = DebugContextCoordinator()
		var checkpoint = false
		coordinator.direct.invoke {
			checkpoint = true
			
			XCTAssert(coordinator.currentThread == .unspecified)
			XCTAssert(coordinator.currentTime == 0)
		}
		XCTAssert(checkpoint)
	}

	func testDirectInvokeAsync() {
		let coordinator = DebugContextCoordinator()
		var checkpoint = false
		coordinator.direct.invokeAsync {
			checkpoint = true
			
			XCTAssert(coordinator.currentThread == .global)
			XCTAssert(coordinator.currentTime == 1)
		}
		XCTAssert(!checkpoint)
		coordinator.runScheduledTasks()
		XCTAssert(checkpoint)
	}

	func testDirectInvokeAndWait() {
		let coordinator = DebugContextCoordinator()
		var checkpoint = false
		coordinator.direct.invokeAndWait {
			checkpoint = true
			
			XCTAssert(coordinator.currentThread == .unspecified)
			XCTAssert(coordinator.currentTime == 0)
		}
		XCTAssert(checkpoint)
	}

	func testDirectSingleTimer() {
		let coordinator = DebugContextCoordinator()
		var checkpoint1 = false
		var checkpoint2 = false
		var timer2: Lifetime? = nil
		let timer1 = coordinator.direct.singleTimer(interval: .seconds(10), leeway: .seconds(0)) {
			checkpoint1 = true
			
			XCTAssert(coordinator.currentThread == .global)
			XCTAssert(coordinator.currentTime == 10_000_000_000)

			timer2 = coordinator.direct.singleTimer(interval: .seconds(10), leeway: .seconds(0)) {
				checkpoint2 = true
				
				XCTAssert(coordinator.currentThread == .global)
				XCTAssert(coordinator.currentTime == 20_000_000_000)
			}
			XCTAssert(!checkpoint2)
		}
		XCTAssert(!checkpoint1)
		coordinator.runScheduledTasks()
		XCTAssert(checkpoint1)
		XCTAssert(checkpoint2)
		withExtendedLifetime(timer1) {}
		withExtendedLifetime(timer2) {}

		var timer3 = coordinator.direct.singleTimer(interval: .seconds(10), leeway: .seconds(0)) {
			XCTFail()
		}
		timer3.cancel()
		coordinator.runScheduledTasks()
	}

	func testDirectSingleTimerWithParameter() {
		let coordinator = DebugContextCoordinator()
		var checkpoint1 = false
		let timer1 = coordinator.direct.singleTimer(parameter: 23, interval: .seconds(10), leeway: .seconds(0)) { p in
			checkpoint1 = true
			
			XCTAssert(p == 23)
			XCTAssert(coordinator.currentThread == .global)
			XCTAssert(coordinator.currentTime == 10_000_000_000)
		}
		XCTAssert(!checkpoint1)
		coordinator.runScheduledTasks()
		XCTAssert(checkpoint1)
		withExtendedLifetime(timer1) {}
	}

	func testDirectPeriodicTimer() {
		let coordinator = DebugContextCoordinator()
		var results = [(Int, UInt64)]()
		var timer1: Lifetime? = nil
		timer1 = coordinator.direct.periodicTimer(interval: .seconds(3), leeway: .seconds(0)) {
			results.append((0, coordinator.currentTime))
			
			if results.count >= 9 {
				timer1?.cancel()
			}
		}
		var timer2: Lifetime? = nil
		timer2 = coordinator.direct.periodicTimer(interval: .seconds(10), leeway: .seconds(0)) {
			results.append((1, coordinator.currentTime))
			
			if results.count >= 9 {
				timer2?.cancel()
			}
		}
		coordinator.runScheduledTasks()
		XCTAssert(results.count == 10)
		XCTAssert(results.at(0).map { $0.0 == 0 && $0.1 == 3_000_000_000 } == true)
		XCTAssert(results.at(1).map { $0.0 == 0 && $0.1 == 6_000_000_000 } == true)
		XCTAssert(results.at(2).map { $0.0 == 0 && $0.1 == 9_000_000_000 } == true)
		XCTAssert(results.at(3).map { $0.0 == 1 && $0.1 == 10_000_000_000 } == true)
		XCTAssert(results.at(4).map { $0.0 == 0 && $0.1 == 12_000_000_000 } == true)
		XCTAssert(results.at(5).map { $0.0 == 0 && $0.1 == 15_000_000_000 } == true)
		XCTAssert(results.at(6).map { $0.0 == 0 && $0.1 == 18_000_000_000 } == true)
		XCTAssert(results.at(7).map { $0.0 == 1 && $0.1 == 20_000_000_000 } == true)
		XCTAssert(results.at(8).map { $0.0 == 0 && $0.1 == 21_000_000_000 } == true)
		XCTAssert(results.at(9).map { $0.0 == 1 && $0.1 == 30_000_000_000 } == true)
	}

	func testDirectPeriodicTimerWithParameter() {
		let coordinator = DebugContextCoordinator()
		var results = [(Int, UInt64)]()
		var timer1: Lifetime? = nil
		timer1 = coordinator.direct.periodicTimer(parameter: 23, interval: .seconds(3), leeway: .seconds(0)) { p in
			XCTAssert(p == 23)
			results.append((0, coordinator.currentTime))
			
			if results.count >= 9 {
				timer1?.cancel()
			}
		}
		var timer2: Lifetime? = nil
		timer2 = coordinator.direct.periodicTimer(parameter: 45, interval: .seconds(10), leeway: .seconds(0)) { p in
			XCTAssert(p == 45)
			results.append((1, coordinator.currentTime))
			
			if results.count >= 9 {
				timer2?.cancel()
			}
		}
		coordinator.runScheduledTasks()
		XCTAssert(results.count == 10)
		XCTAssert(results.at(0).map { $0.0 == 0 && $0.1 == 3_000_000_000 } == true)
		XCTAssert(results.at(1).map { $0.0 == 0 && $0.1 == 6_000_000_000 } == true)
		XCTAssert(results.at(2).map { $0.0 == 0 && $0.1 == 9_000_000_000 } == true)
		XCTAssert(results.at(3).map { $0.0 == 1 && $0.1 == 10_000_000_000 } == true)
		XCTAssert(results.at(4).map { $0.0 == 0 && $0.1 == 12_000_000_000 } == true)
		XCTAssert(results.at(5).map { $0.0 == 0 && $0.1 == 15_000_000_000 } == true)
		XCTAssert(results.at(6).map { $0.0 == 0 && $0.1 == 18_000_000_000 } == true)
		XCTAssert(results.at(7).map { $0.0 == 1 && $0.1 == 20_000_000_000 } == true)
		XCTAssert(results.at(8).map { $0.0 == 0 && $0.1 == 21_000_000_000 } == true)
		XCTAssert(results.at(9).map { $0.0 == 1 && $0.1 == 30_000_000_000 } == true)
	} 
	
	func testMainInvoke() {
		let coordinator1 = DebugContextCoordinator(initialThread: .main)
		var checkpoint1 = false
		coordinator1.main.invoke {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 0)
		}
		XCTAssert(checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)

		let coordinator2 = DebugContextCoordinator()
		var checkpoint2 = false
		coordinator2.main.invoke {
			checkpoint2 = true
			
			XCTAssert(coordinator2.currentThread == .main)
			XCTAssert(coordinator2.currentTime == 1)
		}
		XCTAssert(!checkpoint2)
		coordinator2.runScheduledTasks()
		XCTAssert(checkpoint2)
	}
	
	func testMainAsyncInvoke() {
		let coordinator1 = DebugContextCoordinator(initialThread: .main)
		var checkpoint1 = false
		coordinator1.mainAsync.invoke {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(!checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)
	}
	
	func testDefaultInvoke() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.global.invoke {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .global)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(!checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)
	}
	
	func testSyncQueueInvoke() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.syncQueue
		
		if case .custom(_ as DebugContext) = ec {
			ec.invoke {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 0)
			}
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}
	
	func testAsyncQueueInvoke() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.asyncQueue
		if case .custom(_ as DebugContext) = ec {
			ec.invoke {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 1)
			}
			XCTAssert(!checkpoint1)
			coordinator1.runScheduledTasks()
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}
	
	func testMainInvokeAsync() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.main.invokeAsync {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(!checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)

		let coordinator2 = DebugContextCoordinator()
		var checkpoint2 = false
		coordinator2.main.invokeAsync {
			checkpoint2 = true
			
			XCTAssert(coordinator2.currentThread == .main)
			XCTAssert(coordinator2.currentTime == 1)
		}
		XCTAssert(!checkpoint2)
		coordinator2.runScheduledTasks()
		XCTAssert(checkpoint2)
	}
	
	func testMainAsyncInvokeAsync() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.mainAsync.invokeAsync {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(!checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)
	}
	
	func testDefaultInvokeAsync() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.global.invokeAsync {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .global)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(!checkpoint1)
		coordinator1.runScheduledTasks()
		XCTAssert(checkpoint1)
	}
	
	func testSyncQueueInvokeAsync() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.syncQueue
		if case .custom(_ as DebugContext) = ec {
			ec.invokeAsync {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 1)
			}
			XCTAssert(!checkpoint1)
			coordinator1.runScheduledTasks()
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}
	
	func testAsyncQueueInvokeAsync() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.asyncQueue
		if case .custom(_ as DebugContext) = ec {
			ec.invokeAsync {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 1)
			}
			XCTAssert(!checkpoint1)
			coordinator1.runScheduledTasks()
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}
	
	func testMainInvokeAndWait() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.main.invokeAndWait {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(checkpoint1)

		let coordinator2 = DebugContextCoordinator()
		var checkpoint2 = false
		coordinator2.main.invokeAndWait {
			checkpoint2 = true
			
			XCTAssert(coordinator2.currentThread == .main)
			XCTAssert(coordinator2.currentTime == 1)
		}
		XCTAssert(checkpoint2)
	}
	
	func testMainAsyncInvokeAndWait() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.mainAsync.invokeAndWait {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .main)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(checkpoint1)
	}
	
	func testDefaultInvokeAndWait() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		coordinator1.global.invokeAndWait {
			checkpoint1 = true
			
			XCTAssert(coordinator1.currentThread == .global)
			XCTAssert(coordinator1.currentTime == 1)
		}
		XCTAssert(checkpoint1)
	}
	
	func testSyncQueueInvokeAndWait() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.syncQueue
		if case .custom(_ as DebugContext) = ec {
			ec.invokeAndWait {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 0)
			}
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}
	
	func testAsyncQueueInvokeAndWait() {
		let coordinator1 = DebugContextCoordinator()
		var checkpoint1 = false
		let ec = coordinator1.asyncQueue
		if case .custom(_ as DebugContext) = ec {
			ec.invokeAndWait {
				checkpoint1 = true
				
				XCTAssert(coordinator1.currentThread.matches(ec))
				XCTAssert(coordinator1.currentTime == 1)
			}
			XCTAssert(checkpoint1)
		} else {
			XCTFail()
		}
	}

	#if false
		func testTimeoutServiceSuccessHostTime() {
			let ex = expectation(description: "Waiting for timeout callback")
			
			// Use our debug `StringService`
			let service = TimeoutService(work: dummyAsyncWork(duration: 2.0))
			
			// Set up the time data we need
			let startTime = mach_absolute_time()
			let timeoutTime = 1.0
			let targetTime = UInt64(timeoutTime * Double(NSEC_PER_SEC))
			let leeway = UInt64(0.01 * Double(NSEC_PER_SEC))
			
			service.start(timeout: timeoutTime) { r in
				// Measure and test the time elapsed
				let endTime = mach_absolute_time()
				XCTAssert(endTime - startTime > targetTime - leeway)
				XCTAssert(endTime - startTime < targetTime + leeway)
				
				XCTAssert(r.value == nil)
				ex.fulfill()
			}
			
			// Wait for all scheduled actions to occur
			waitForExpectations(timeout: 10, handler: nil)
		}
	#endif
	
	func testTimeoutServiceSuccess() {
		let coordinator = DebugContextCoordinator()

		var result: Result<String>? = nil
		let service = TimeoutService(context: coordinator.global, work: dummyAsyncWork(duration: 2.0))
		service.start(timeout: 10) { r in
			result = r
		}
		coordinator.runScheduledTasks()
		coordinator.reset()
		withExtendedLifetime(service) {}
		XCTAssert(result?.value == dummySuccessResponse)
	}

	func testTimeoutServiceCancelled() {
		let coordinator = DebugContextCoordinator()
		// Test the service released case
		do {
			let service = TimeoutService(context: coordinator.global, work: dummyAsyncWork(duration: 2.0))
			service.start(timeout: 10) { r in
				XCTFail()
			}
		}
		coordinator.runScheduledTasks()
	}

	func testTimeoutServiceTimeout() {
		let coordinator = DebugContextCoordinator()
		let context = coordinator.syncQueue

		// Construct the `TimeoutService` using our debug context
		let service = TimeoutService(context: context, work: dummyAsyncWork(duration: 2.0))

		// Run the `connect` function
		let timeoutTime = 1.0
		var result: Result<String>? = nil
		service.start(timeout: timeoutTime) { r in
			result = r
			XCTAssert(coordinator.currentTime == UInt64(timeoutTime * Double(NSEC_PER_SEC)))
			XCTAssert(coordinator.currentThread.matches(context))
		}

		// Perform all scheduled tasks immediately
		coordinator.runScheduledTasks()

		// Ensure we got the correct result
		XCTAssert(result?.error as? TimeoutService.Timeout != nil)

		withExtendedLifetime(service) {}
	}
}

class TimeoutService {
	struct Timeout: Error {}
	
	// This service performs one action at a time, lifetime tied to the service
	// The service retains the timeout timer which, in turn, returns the
	// underlying service
	var currentAction: Lifetime? = nil
	
	// Define the interface for the underlying connection
	typealias ResultHandler = (Result<String>) -> Void
	typealias WorkFunction = (Exec, @escaping ResultHandler) -> Lifetime

	// This is the configurable connection to the underlying service
	let work: WorkFunction

	// Every action for this service should occur in in this queue
	let context: Exec
	
	// Construction of the Service lets us specify the underlying service
	init(context: Exec = .global, work: @escaping WorkFunction = NetworkService.init) {
		self.work = work
		self.context = context.serialized()
	}

	// This `TimeoutService` invokes the `underlyingConnect` and starts a timer
	func start(timeout seconds: Double, handler: @escaping ResultHandler) {
		var previousAction: Lifetime? = nil
		context.invokeAndWait {
			previousAction = self.currentAction

			let current = AggregateLifetime()
			
			// Run the underlying connection
			let underlyingAction = self.work(self.context) { [weak current] result in
				// Cancel the timer if the success occurs first
				current?.cancel()
				handler(result)
			}
			
			// Run the timeout timer
			let timer = self.context.singleTimer(interval: .interval(seconds)) { [weak current] in
				// Cancel the connection if the timer fires first
				current?.cancel()
				handler(.failure(Timeout()))
			}
			
			current += timer
			current += underlyingAction
			self.currentAction = current
		}
		
		// Good rule of thumb: never release lifetime objects inside a mutex
		withExtendedLifetime(previousAction) {}
	}
}

let dummySuccessResponse = "Here's a string"
func dummyAsyncWork(duration: Double) -> TimeoutService.WorkFunction {
	return { exec, handler in
		exec.singleTimer(interval: .interval(duration)) {
			handler(.success(dummySuccessResponse))
		}
	}
}


// Dummy network service used to fulfill interface requirements. Obviously, doesn't really connect to the network but you could imagine something that fetches an HTTP resource.
class NetworkService: Lifetime {
	var timer: Lifetime
	init(context: Exec, handler: @escaping TimeoutService.ResultHandler) {
		timer = context.singleTimer(interval: .interval(5.0)) {
			handler(.success(dummySuccessResponse))
		}
	}
	func cancel() {
		timer.cancel()
	}
}
