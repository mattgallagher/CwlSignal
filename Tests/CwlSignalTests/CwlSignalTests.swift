//
//  CwlSignalTests.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2016/06/08.
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
import CwlSignal
import CwlPreconditionTesting

#if SWIFT_PACKAGE
	import CwlUtils
#endif

private enum TestError: Error {
	case zeroValue
	case oneValue
	case twoValue
}

class SignalTests: XCTestCase {
	func testBasics() {
		var results = [Result<Int, SignalEnd>]()
		let (i1, out) = Signal<Int>.create { $0.subscribe { r in results.append(r) } }
		i1.send(result: .success(1))
		i1.send(value: 3)
		XCTAssert(out.isClosed == false)
		out.cancel()
		XCTAssert(out.isClosed == true)
		i1.send(value: 5)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 3)
		withExtendedLifetime(out) {}
		
		let (i2, ep2) = Signal<Int>.create { $0.transform { r, n in n.send(result: r) }.subscribe { r in results.append(r) } }
		i2.send(result: .success(5))
		i2.send(end: .other(TestError.zeroValue))
		XCTAssert(i2.send(value: 0) == SignalSendError.disconnected)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error?.otherError as? TestError == TestError.zeroValue)
		ep2.cancel()
		
		_ = Signal<Int>.preclosed().subscribe { r in results.append(r) }
		XCTAssert(results.at(4)?.error?.isComplete == true)
	}
	
	func testKeepAlive() {
		var results = [Result<Int, SignalEnd>]()
		let (i, _) = Signal<Int>.create { $0.subscribeWhile { r in
			results.append(r)
			return r.value != 7
		} }
		i.send(value: 5)
		i.send(value: 7)
		i.send(value: 9)
		i.close()
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.value == 7)

		// A lazily generated sequence of strings
		let generatedSignal = Signal<String>.generate { input in
			if let i = input {
				i.send(value: "🤖")
				i.send(value: "🎃")
				i.send(value: "😡")
				i.send(value: "😈")
			}
		}

		// A subscribeAndKeepAlive retains itself (i.e. doesn't return an output that you must hold) until the signal is closed or until you return false
		var results2 = Array<String>()
		generatedSignal.subscribeValuesWhile {
			results2 += $0
			return $0 == "😡" ? false : true
		}
		
		XCTAssert(results2.count == 3)
	}
	
	func testLifetimes() {
		weak var weakOutput1: SignalOutput<Int>? = nil
		weak var weakToken: NSObject? = nil
		weak var weakSignal1: Signal<Int>? = nil
		weak var weakSignal2: Signal<Int>? = nil
		var results1 = [Result<Int, SignalEnd>]()
		var results2 = [Result<Int, SignalEnd>]()
		do {
			let (input1, signal1) = Signal<Int>.create()
			weakSignal1 = signal1
			
			do {
				let endPoint = signal1.subscribe { (r: Result<Int, SignalEnd>) in
					results1.append(r)
				}
				weakOutput1 = endPoint
				input1.send(result: .success(5))
				XCTAssert(weakOutput1 != nil)
				XCTAssert(weakSignal1 != nil)
				
				withExtendedLifetime(endPoint) {}
			}
			
			XCTAssert(weakOutput1 == nil)
			
			let (input2, signal2) = Signal<Int>.create()
			weakSignal2 = signal2
			
			do {
				do {
					let token = NSObject()
					signal2.subscribeUntilEnd { (r: Result<Int, SignalEnd>) in
						withExtendedLifetime(token) {}
						results2.append(r)
					}
					weakToken = token
				}
				input2.send(result: .success(5))
				XCTAssert(weakToken != nil)
				XCTAssert(weakSignal2 != nil)
			}
			
			XCTAssert(weakToken != nil)
			input2.close()
		}
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 5)
		XCTAssert(weakSignal1 == nil)
		
		XCTAssert(weakToken == nil)
		
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.error?.isComplete == true)
		XCTAssert(weakSignal2 == nil)
	}
	
	func testCreate() {
		// Create a signal with default behavior
		let (input, signal) = Signal<Int>.create()
		
		// Make sure we get an .Inactive response before anything is connected
		XCTAssert(input.send(result: .success(321)) == SignalSendError.inactive)
		
		// Subscribe
		var results = [Result<Int, SignalEnd>]()
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let ep1 = signal.subscribe(context: context) { r in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			results.append(r)
		}
		
		// Ensure we don't immediately receive anything
		XCTAssert(results.count == 0)
		
		// Adding a second subscriber results in an assertion failure at DEBUG time or a SignalSendError.duplicate otherwise
		let e = catchBadInstruction {
			var results2 = [Result<Int, SignalEnd>]()
			let ep2 = signal.subscribe { r in results2.append(r) }
			#if DEBUG
				XCTFail()
			#else
				XCTAssert(results2.count == 1)
				if case .some(.duplicate) = results2.at(0)?.error?.otherError as? SignalBindError<Int> {
				} else {
					XCTFail()
				}
			#endif
			withExtendedLifetime(ep2) {}
		}
		#if DEBUG
			XCTAssert(e != nil)
		#endif
		
		// Send a value and close
		XCTAssert(input.send(result: .success(123)) == nil)
		XCTAssert(input.send(result: .failure(SignalEnd.complete)) == nil)
		
		// Confirm sending worked
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 123)
		XCTAssert(results.at(1)?.error?.isComplete == true)
		
		// Confirm we can't send to a closed signal
		XCTAssert(input.send(result: .success(234)) == .disconnected)
		
		withExtendedLifetime(ep1) {}
	}
	
	func testSignalPassthrough() {
		// Create a restartable
		let (input, s) = Signal<Int>.create()
		let signal = s.multicast()
		
		// We should already be active, even without listeners.
		XCTAssert(input.send(result: .success(321)) == nil)
		
		// Subscribe send and close
		var results1 = [Result<Int, SignalEnd>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		
		// Ensure we don't immediately receive anything
		XCTAssert(results1.count == 0)
		
		// Send a value and close
		XCTAssert(input.send(result: .success(123)) == nil)
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 123)
		
		// Subscribe and send again, leaving open
		var results2 = [Result<Int, SignalEnd>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		XCTAssert(input.send(result: .success(345)) == nil)
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(1)?.value == 345)
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.value == 345)
		
		// Add a third subscriber
		var results3 = [Result<Int, SignalEnd>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		XCTAssert(input.send(result: .success(678)) == nil)
		XCTAssert(input.close() == nil)
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(2)?.value == 678)
		XCTAssert(results1.at(3)?.error?.isComplete == true)
		XCTAssert(results3.count == 2)
		XCTAssert(results3.at(0)?.value == 678)
		XCTAssert(results3.at(1)?.error?.isComplete == true)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(1)?.value == 678)
		XCTAssert(results2.at(2)?.error?.isComplete == true)
		
		XCTAssert(input.send(value: 0) == .disconnected)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	func testSignalContinuous() {
		// Create a signal
		let (input, s) = Signal<Int>.create()
		let signal = s.continuous()
		
		// Subscribe twice
		var results1 = [Result<Int, SignalEnd>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int, SignalEnd>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		
		// Ensure we don't immediately receive anything
		XCTAssert(results1.count == 0)
		XCTAssert(results2.count == 0)
		
		// Send a value and leave open
		XCTAssert(input.send(result: .success(123)) == nil)
		
		// Confirm receipt
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 123)
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.value == 123)
		
		// Subscribe again
		var results3 = [Result<Int, SignalEnd>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		XCTAssert(results3.count == 1)
		XCTAssert(results3.at(0)?.value == 123)
		
		// Send another
		XCTAssert(input.send(result: .success(234)) == nil)
		
		// Subscribe again, leaving open
		var results4 = [Result<Int, SignalEnd>]()
		let ep4 = signal.subscribe { r in results4.append(r) }
		XCTAssert(results4.count == 1)
		XCTAssert(results4.at(0)?.value == 234)
		
		// Confirm receipt
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(1)?.value == 234)
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(1)?.value == 234)
		XCTAssert(results3.count == 2)
		XCTAssert(results3.at(1)?.value == 234)
		XCTAssert(results4.count == 1)
		XCTAssert(results4.at(0)?.value == 234)
		
		// Close
		XCTAssert(input.send(result: .failure(SignalEnd.complete)) == nil)
		XCTAssert(results1.count == 3)
		XCTAssert(results1.at(2)?.error?.isComplete == true)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(2)?.error?.isComplete == true)
		XCTAssert(results3.count == 3)
		XCTAssert(results3.at(2)?.error?.isComplete == true)
		XCTAssert(results4.count == 2)
		XCTAssert(results4.at(1)?.error?.isComplete == true)
		
		// Subscribe again, leaving open
		var results5 = [Result<Int, SignalEnd>]()
		let ep5 = signal.subscribe { r in results5.append(r) }
		XCTAssert(results5.count == 1)
		XCTAssert(results5.at(0)?.error?.isComplete == true)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
		withExtendedLifetime(ep4) {}
		withExtendedLifetime(ep5) {}
	}
	
	func testSignalContinuousWithinitial() {
		// Create a signal
		let (input, s) = Signal<Int>.create()
		let signal = s.continuous(initialValue: 5)
		
		// Subscribe twice
		var results1 = [Result<Int, SignalEnd>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int, SignalEnd>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		
		// Ensure we immediately receive the initial
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 5)
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.value == 5)
		
		// Send a value and leave open
		XCTAssert(input.send(result: .success(123)) == nil)
		
		// Confirm receipt
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(1)?.value == 123)
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(1)?.value == 123)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}
	
	func testSignalPlayback() {
		// Create a signal
		let (input, s) = Signal<Int>.create()
		let signal = s.playback()
		
		// Send a value and leave open
		XCTAssert(input.send(value: 3) == nil)
		XCTAssert(input.send(value: 4) == nil)
		XCTAssert(input.send(value: 5) == nil)
		
		// Subscribe twice
		var results1 = [Result<Int, SignalEnd>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int, SignalEnd>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		
		// Ensure we immediately receive the values
		XCTAssert(results1.count == 3)
		XCTAssert(results1.at(0)?.value == 3)
		XCTAssert(results1.at(1)?.value == 4)
		XCTAssert(results1.at(2)?.value == 5)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(0)?.value == 3)
		XCTAssert(results2.at(1)?.value == 4)
		XCTAssert(results2.at(2)?.value == 5)
		
		// Send a value and leave open
		XCTAssert(input.send(result: .success(6)) == nil)
		
		// Confirm receipt
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(3)?.value == 6)
		XCTAssert(results2.count == 4)
		XCTAssert(results2.at(3)?.value == 6)
		
		// Close
		XCTAssert(input.send(end: SignalEnd.complete) == nil)
		
		// Subscribe again
		var results3 = [Result<Int, SignalEnd>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		
		XCTAssert(results1.count == 5)
		XCTAssert(results2.count == 5)
		XCTAssert(results3.count == 5)
		XCTAssert(results1.at(4)?.error?.isComplete == true)
		XCTAssert(results2.at(4)?.error?.isComplete == true)
		XCTAssert(results3.at(0)?.value == 3)
		XCTAssert(results3.at(1)?.value == 4)
		XCTAssert(results3.at(2)?.value == 5)
		XCTAssert(results3.at(3)?.value == 6)
		XCTAssert(results3.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	func testSignalCacheUntilActive() {
		// Create a signal
		let (input, s) = Signal<Int>.create()
		let signal = s.cacheUntilActive()
		
		// Send a value and leave open
		XCTAssert(input.send(result: .success(5)) == nil)
		
		do {
			// Subscribe once
			var results1 = [Result<Int, SignalEnd>]()
			let ep1 = signal.subscribe { r in results1.append(r) }
			
			// Ensure we immediately receive the values
			XCTAssert(results1.count == 1)
			XCTAssert(results1.at(0)?.value == 5)
			
			// Subscribe again
			let e = catchBadInstruction {
				var results2 = [Result<Int, SignalEnd>]()
				let ep2 = signal.subscribe { r in results2.append(r) }
				
				#if DEBUG
					XCTFail()
				#else
					// Ensure error received
					XCTAssert(results2.count == 1)
					if case .some(.duplicate) = results2.at(0)?.error?.otherError as? SignalBindError<Int> {
					} else {
						XCTFail()
					}
				#endif
				
				withExtendedLifetime(ep2) {}
			}
			#if DEBUG
				XCTAssert(e != nil)
			#endif
			
			withExtendedLifetime(ep1) {}
		}
		
		// Send a value again
		XCTAssert(input.send(result: .success(7)) == nil)
		
		do {
			// Subscribe once
			var results3 = [Result<Int, SignalEnd>]()
			let ep3 = signal.subscribe { r in results3.append(r) }
			
			// Ensure we get just the value sent after reactivation
			XCTAssert(results3.count == 1)
			XCTAssert(results3.at(0)?.value == 7)
			
			withExtendedLifetime(ep3) {}
		}
	}
	
	func testSignalCustomActivation() {
		// Create a signal
		let (input, s) = Signal<Int>.create()
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let signal = s.customActivation(initialValues: [3, 4], context: context) { (activationValues: inout Array<Int>, preclosed: inout SignalEnd?, result: Result<Int, SignalEnd>) -> Void in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			if case .success(6) = result {
				activationValues = [7]
			}
		}
		
		// Send a value and leave open
		XCTAssert(input.send(value: 5) == nil)
		
		// Subscribe twice
		var results1 = [Result<Int, SignalEnd>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int, SignalEnd>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		
		// Ensure we immediately receive the values
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == 3)
		XCTAssert(results1.at(1)?.value == 4)
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == 3)
		XCTAssert(results2.at(1)?.value == 4)
		
		// Send a value and leave open
		XCTAssert(input.send(value: 6) == nil)
		
		// Confirm receipt
		XCTAssert(results1.count == 3)
		XCTAssert(results1.at(2)?.value == 6)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(2)?.value == 6)
		
		// Subscribe again
		var results3 = [Result<Int, SignalEnd>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		
		XCTAssert(results1.count == 3)
		XCTAssert(results2.count == 3)
		XCTAssert(results3.at(0)?.value == 7)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	enum State: Equatable {
		static func ==(lhs: State, rhs: State) -> Bool {
			switch (lhs, rhs) {
			case (.inserted(let vl, let il), .inserted(let vr, let ir)): return vl == vr && il == ir
			case (.deleted(let vl, let il), .deleted(let vr, let ir)): return vl == vr && il == ir
			case (.reset(let al), .reset(let ar)): return al == ar
			default: return false
			}
		}
		
		case inserted(value: Int, index: Int)
		case deleted(value: Int, index: Int)
		case reset([Int])
		
		var array: [Int] {
			switch self {
			case .reset(let a): return a
			default: return []
			}
		}
	}
	
	func testReduce() {
		enum StackOperation {
			case push(Int)
			case pop
		}
		
		let (input, signal) = Signal<StackOperation>.create()
		let reduced = signal.reduce(initialState: [0, 1, 2]) { (state: [Int], message: StackOperation) throws -> [Int] in
			switch message {
			case .push(let value):
				if state.count == 5 {
					throw TestError.zeroValue
				}
				return state.appending(value)
			case .pop: return Array(state.dropLast())
			}
		}
		
		var results1 = [Result<[Int], SignalEnd>]()
		reduced.subscribeUntilEnd { r in
			results1.append(r)
		}
		
		input.send(value: .push(3))
		input.send(value: .pop)
		input.send(value: .pop)
		
		var results2 = [Result<[Int], SignalEnd>]()
		reduced.subscribeUntilEnd { r in
			results2.append(r)
		}
		
		input.send(value: .push(1))
		input.send(value: .push(2))
		input.send(value: .push(3))
		input.send(value: .push(5))
		
		XCTAssert(results1.count == 8)
		XCTAssert(results1.at(0)?.value == [0, 1, 2])
		XCTAssert(results1.at(1)?.value == [0, 1, 2, 3])
		XCTAssert(results1.at(2)?.value == [0, 1, 2])
		XCTAssert(results1.at(3)?.value == [0, 1])
		XCTAssert(results1.at(4)?.value == [0, 1, 1])
		XCTAssert(results1.at(5)?.value == [0, 1, 1, 2])
		XCTAssert(results1.at(6)?.value == [0, 1, 1, 2, 3])
		XCTAssertEqual(results1.at(7)?.error?.otherError as? TestError, TestError.zeroValue)
		
		XCTAssert(results2.count == 5)
		XCTAssert(results2.at(0)?.value == [0, 1])
		XCTAssert(results2.at(1)?.value == [0, 1, 1])
		XCTAssert(results2.at(2)?.value == [0, 1, 1, 2])
		XCTAssert(results2.at(3)?.value == [0, 1, 1, 2, 3])
		XCTAssert(results2.at(4)?.error?.otherError as? TestError == TestError.zeroValue)
	}
	
	func testReduceWithInitializer() {
		enum StackOperation {
			case push(Int)
			case pop
		}
		
		let (input, signal) = Signal<StackOperation>.create()
		let initializer = { (message: StackOperation) -> [Int]? in
			switch message {
			case .push(let p): return Array(repeating: 1, count: p)
			case .pop: return nil
			}
		}
		let reduced = signal.reduce(initializer: initializer) { (state: [Int], message: StackOperation) throws -> [Int] in
			switch message {
			case .push(let value):
				if state.count == 5 {
					throw TestError.zeroValue
				}
				return state.appending(value)
			case .pop: return Array(state.dropLast())
			}
		}
		
		var results1 = [Result<[Int], SignalEnd>]()
		reduced.subscribeUntilEnd { r in
			results1.append(r)
		}
		
		input.send(value: .pop)
		input.send(value: .pop)
		input.send(value: .push(3))
		input.send(value: .pop)
		input.send(value: .pop)
		
		var results2 = [Result<[Int], SignalEnd>]()
		reduced.subscribeUntilEnd { r in
			results2.append(r)
		}
		
		input.send(value: .push(1))
		input.send(value: .push(2))
		input.send(value: .push(3))
		input.send(value: .push(5))
		input.send(value: .push(8))
		
		XCTAssert(results1.count == 8)
		XCTAssert(results1.at(0)?.value == [1, 1, 1])
		XCTAssert(results1.at(1)?.value == [1, 1])
		XCTAssert(results1.at(2)?.value == [1])
		XCTAssert(results1.at(3)?.value == [1, 1])
		XCTAssert(results1.at(4)?.value == [1, 1, 2])
		XCTAssert(results1.at(5)?.value == [1, 1, 2, 3])
		XCTAssert(results1.at(6)?.value == [1, 1, 2, 3, 5])
		XCTAssertEqual(results1.at(7)?.error?.otherError as? TestError, TestError.zeroValue)
		
		XCTAssert(results2.count == 6)
		XCTAssert(results2.at(0)?.value == [1])
		XCTAssert(results2.at(1)?.value == [1, 1])
		XCTAssert(results2.at(2)?.value == [1, 1, 2])
		XCTAssert(results2.at(3)?.value == [1, 1, 2, 3])
		XCTAssert(results2.at(4)?.value == [1, 1, 2, 3, 5])
		XCTAssert(results2.at(5)?.error?.otherError as? TestError == TestError.zeroValue)
	}
	
	func testPreclosed() {
		var results1 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.preclosed(1, 3, 5, end: .other(TestError.oneValue)).subscribe { r in
			results1.append(r)
		}
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 3)
		XCTAssert(results1.at(2)?.value == 5)
		XCTAssert(results1.at(3)?.error?.otherError as? TestError == .oneValue)
		
		var results2 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.preclosed().subscribe { r in
			results2.append(r)
		}
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.error?.isComplete == true)
		
		var results3 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.preclosed(7).subscribe { r in
			results3.append(r)
		}
		XCTAssert(results3.count == 2)
		XCTAssert(results3.at(0)?.value == 7)
		XCTAssert(results3.at(1)?.error?.isComplete == true)
	}
	
	func testCapture() {
		let (input, s) = Signal<Int>.create()
		let signal = s.continuous()
		input.send(value: 1)
		
		let capture = signal.capture()
		var results = [Result<Int, SignalEnd>]()
		let (subsequentInput, subsequentSignal) = Signal<Int>.create()
		let out = subsequentSignal.subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		
		// Send a value between construction and bind. This must be *blocked* in the capture queue.
		XCTAssert(input.send(value: 5) == nil)
		
		let (values, error) = (capture.values, capture.end)
		do {
			try capture.bind(to: subsequentInput)
		} catch {
			XCTFail()
		}
		
		input.send(value: 3)
		input.close()
		
		XCTAssert(values == [1])
		XCTAssert(error == nil)
		
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testCaptureAndSubscribe() {
		let (input, output) = Signal<Int>.create { signal in signal.continuous() }
		input.send(value: 1)
		input.send(value: 2)
		
		do {
			let capture = output.capture()
			let (values, error) = (capture.values, capture.end)
			XCTAssert(values == [2])
			XCTAssert(error == nil)
			
			input.send(value: 3)
			
			var results = [Result<Int, SignalEnd>]()
			_ = capture.resume().subscribe { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0)?.value == 3)
		}
		
		do {
			let capture = output.capture()
			let (values, error) = (capture.values, capture.end)
			XCTAssert(values == [3])
			XCTAssert(error == nil)
			
			input.send(value: 4)
			
			var results = [Result<Int, SignalEnd>]()
			let l = capture.resume(onEnd: { (j, e, i) in
				i.send(5, 6, 7)
			}).subscribe { r in results += r }
			
			input.close()
			
			XCTAssert(results.count == 5)
			XCTAssert(results.at(0)?.value == 4)
			XCTAssert(results.at(1)?.value == 5)
			XCTAssert(results.at(2)?.value == 6)
			XCTAssert(results.at(3)?.value == 7)
			XCTAssert(results.at(4)?.error?.isCancelled == true)
			withExtendedLifetime(l) {}
		}
		
		withExtendedLifetime(input) {}
	}
	
	func testCaptureAndSubscribeValues() {
		let (input, output) = Signal<Int>.create { signal in signal.continuous() }
		input.send(value: 1)
		input.send(value: 2)
		
		do {
			let capture = output.capture()
			let (values, error) = (capture.values, capture.end)
			XCTAssert(values == [2])
			XCTAssert(error == nil)
			
			input.send(value: 3)
			
			var results = [Int]()
			_ = capture.subscribeValues { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0) == 3)
		}
		
		do {
			let capture = output.capture()
			let (values, error) = (capture.values, capture.end)
			XCTAssert(values == [3])
			XCTAssert(error == nil)
			
			input.send(value: 4)
			
			var results = [Int]()
			_ = capture.subscribeValues { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0) == 4)
		}
		
		withExtendedLifetime(input) {}
	}
	
	func testCaptureOnError() {
		let (input, s) = Signal<Int>.create()
		let signal = s.continuous()
		input.send(value: 1)
		
		let capture = signal.capture()
		var results = [Result<Int, SignalEnd>]()
		let (subsequentInput, subsequentSignal) = Signal<Int>.create()
		let ep1 = subsequentSignal.subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		
		let (values, error) = (capture.values, capture.end)
		
		do {
			try capture.bind(to: subsequentInput) { (c: SignalCapture<Int>, e: SignalEnd, i: SignalInput<Int>) in
				XCTAssert(c === capture)
				XCTAssert(e.isComplete)
				i.send(error: TestError.twoValue)
			}
		} catch {
			XCTFail()
		}
		
		input.send(value: 3)
		input.close()
		
		XCTAssert(values == [1])
		XCTAssert(error == nil)
		
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.error?.otherError as? TestError == .twoValue)
		
		let (values2, error2) = (capture.values, capture.end)
		XCTAssert(values2.count == 0)
		XCTAssert(error2?.isComplete == true)
		
		let pc = Signal<Int>.preclosed(end: .other(TestError.oneValue))
		let capture2 = pc.capture()
		let (values3, error3) = (capture2.values, capture2.end)
		
		var results2 = [Result<Int, SignalEnd>]()
		let (subsequentInput2, subsequentSignal2) = Signal<Int>.create()
		let ep2 = subsequentSignal2.subscribe { (r: Result<Int, SignalEnd>) in
			results2.append(r)
		}
		
		do {
			try capture2.bind(to: subsequentInput2, resend: true) { (c, e, i) in
				XCTAssert(c === capture2)
				XCTAssert(e.otherError as? TestError == .oneValue)
				i.send(error: TestError.zeroValue)
			}
		} catch {
			XCTFail()
		}
		
		XCTAssert(values3 == [])
		XCTAssert(error3?.otherError as? TestError == .oneValue)
		
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.error?.otherError as? TestError == .zeroValue)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}
	
	func testGenerate() {
		var count = 0
		var results = [Result<Int, SignalEnd>]()
		weak var lifetimeCheck: Box<Void>? = nil
		var nilCount = 0
		do {
			let closureLifetime = Box<Void>(())
			lifetimeCheck = closureLifetime
			let (context, specificKey) = Exec.syncQueueWithSpecificKey()
			let s = Signal<Int>.generate(context: context) { input in
				XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
				guard let i = input else {
					switch (results.count, nilCount) {
					case (0, 0), (6, 0), (12, 1): nilCount += 1
					default: XCTFail()
					}
					return
				}
				if count == 0 {
					count += 1
					for j in 0..<5 {
						i.send(value: j)
					}
					i.send(error: TestError.zeroValue)
				} else {
					for j in 10..<15 {
						i.send(value: j)
					}
					i.send(end: SignalEnd.complete)
				}
				withExtendedLifetime(closureLifetime) {}
			}
			
			do {
				let ep1 = s.subscribe { (r: Result<Int, SignalEnd>) in
					results.append(r)
				}
				
				XCTAssert(results.count == 6)
				XCTAssert(results.at(0)?.value == 0)
				XCTAssert(results.at(1)?.value == 1)
				XCTAssert(results.at(2)?.value == 2)
				XCTAssert(results.at(3)?.value == 3)
				XCTAssert(results.at(4)?.value == 4)
				XCTAssert(results.at(5)?.error?.otherError as? TestError == .zeroValue)
				withExtendedLifetime(ep1) {}
			}
			
			let ep2 = s.subscribe { (r: Result<Int, SignalEnd>) in
				results.append(r)
			}
			
			XCTAssert(results.count == 12)
			XCTAssert(results.at(6)?.value == 10)
			XCTAssert(results.at(7)?.value == 11)
			XCTAssert(results.at(8)?.value == 12)
			XCTAssert(results.at(9)?.value == 13)
			XCTAssert(results.at(10)?.value == 14)
			XCTAssert(results.at(11)?.error?.isComplete == true)
			XCTAssert(lifetimeCheck != nil)
			
			withExtendedLifetime(ep2) {}
		}
		XCTAssert(nilCount == 2)
		XCTAssert(lifetimeCheck == nil)
	}
	
	func testJoinDisconnect() {
		var firstInput: SignalInput<Int>? = nil
		let sequence1 = Signal<Int>.generate { (input) in
			if let i = input {
				firstInput = i
				for x in 0..<3 {
					i.send(value: x)
				}
			}
		}
		let sequence2 = Signal<Int>.generate { (input) in
			if let i = input {
				for x in 3..<6 {
					i.send(value: x)
				}
			}
		}
		let sequence3 = Signal<Int>.generate { (input) in
			if let i = input {
				i.send(value: 5)
			}
		}
		
		var results = [Result<Int, SignalEnd>]()
		
		do {
			let (i1, s) = Signal<Int>.create()
			let out = s.subscribe { results.append($0) }
			let d = sequence1.junction()
			try d.bind(to: i1)
			i1.send(value: 3)
			
			XCTAssert(results.count == 3)
			XCTAssert(results.at(0)?.value == 0)
			XCTAssert(results.at(1)?.value == 1)
			XCTAssert(results.at(2)?.value == 2)
			
			if let i2 = d.disconnect() {
				let d2 = sequence2.junction()
				try d2.bind(to: i2)
				i2.send(value: 6)
				
				XCTAssert(results.count == 7)
				XCTAssert(results.at(3)?.value == 3)
				XCTAssert(results.at(4)?.value == 4)
				XCTAssert(results.at(5)?.value == 5)
				XCTAssert(results.at(6)?.error?.isCancelled == true)
				
				if let i3 = d2.disconnect() {
					_ = try d.bind(to: i3)
					i3.send(value: 3)
					
					XCTAssert(results.count == 7)
				} else {
					XCTFail()
				}
			} else {
				XCTFail()
			}
			withExtendedLifetime(out) {}
		} catch {
			XCTFail()
		}
		
		withExtendedLifetime(firstInput) {}
		
		var results2 = [Result<Int, SignalEnd>]()
		let (i4, ep2) = Signal<Int>.create { $0.subscribe {
			results2.append($0)
		} }
		
		do {
			try sequence3.junction().bind(to: i4) { d, e, i in
				XCTAssert(e.isCancelled == true)
				i.send(value: 7)
				i.close()
			}
		} catch {
			XCTFail()
		}
		
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.value == 7)
		XCTAssert(results2.at(2)?.error?.isComplete == true)
		
		withExtendedLifetime(ep2) {}
	}
	
	func testJunctionSignal() {
		var results = [Result<Int, SignalEnd>]()
		var outputs = [Lifetime]()
		
		do {
			let signal = Signal<Int>.generate { i in _ = i?.send(value: 5) }
			let (junctionInput, output) = Signal<Int>.create()
			try! signal.junction().bind(to: junctionInput) { (j, err, input) in
				XCTAssert(err.isCancelled)
				input.close()
			}
			outputs += output.subscribe { r in results += r }
			XCTAssert(results.count == 2)
			XCTAssert(results.at(1)?.error?.isComplete == true)
		}
		
		results.removeAll()
		
		do {
			var input: SignalInput<Int>?
			var count = 0
			let signal = Signal<Int>.generate { inp in
				if let i = inp {
					input = i
					i.send(value: 5)
					count += 1
					if count == 3 {
						i.close()
					}
				}
			}
			let (junctionInput, output) = Signal<Int>.create()
			let junction = signal.junction()
			try! junction.bind(to: junctionInput)
			outputs += output.subscribe { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0)?.value == 5)
			junction.rebind()
			XCTAssert(results.count == 2)
			XCTAssert(results.at(1)?.value == 5)
			junction.rebind { (j, err, i) in
				XCTAssert(err.isComplete == true)
				i.send(error: TestError.zeroValue)
			}
			XCTAssert(results.count == 4)
			XCTAssert(results.at(3)?.error?.otherError as? TestError == TestError.zeroValue)
			withExtendedLifetime(input) {}
		}
	}
	
	func testGraphLoop() {
		do {
			let (input1, signal1) = Signal<Int>.create()
			let (input2, signal2) = Signal<Int>.create()
			let signal3 = signal2.map { $0 }
			
			let combined = signal1.combine(signal3) { (cr: EitherResult2<Int, Int>, next: SignalNext<Int>) in
				switch cr {
				case .result1(let r): next.send(result: r)
				case .result2(let r): next.send(result: r)
				}
			}.transform { r, n in n.send(result: r) }.continuous()
			
			let ex = catchBadInstruction {
				combined.bind(to: input2)
				XCTFail()
			}
			XCTAssert(ex != nil)
			withExtendedLifetime(input1) {}
		}
	}
	
	func testTransform() {
		let (input, signal) = Signal<Int>.create()
		var results = [Result<String, SignalEnd>]()
		
		// Test using default behavior and context
		let ep1 = signal.transform { (r: Result<Int, SignalEnd>, n: SignalNext<String>) in
			switch r {
			case .success(let v): n.send(value: "\(v)")
			case .failure(let e): n.send(end: e)
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.close()
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == "0")
		XCTAssert(results.at(1)?.value == "1")
		XCTAssert(results.at(2)?.value == "2")
		XCTAssert(results.at(3)?.error?.isComplete == true)
		
		results.removeAll()
		
		// Test using custom behavior and context
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let (input2, signal2) = Signal<Int>.create()
		let ep2 = signal2.transform(context: context) { (r: Result<Int, SignalEnd>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch r {
			case .success(let v): n.send(value: "\(v)")
			case .failure(let e): n.send(end: e)
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input2.send(value: 0)
		input2.send(value: 1)
		input2.send(value: 2)
		input2.cancel()
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == "0")
		XCTAssert(results.at(1)?.value == "1")
		XCTAssert(results.at(2)?.value == "2")
		XCTAssert(results.at(3)?.error?.isCancelled == true)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}
	
	func testTransformWithState() {
		let (input, signal) = Signal<Int>.create()
		var results = [Result<String, SignalEnd>]()
		
		// Scope the creation of 't' so we can ensure it is removed before we re-add to the signal.
		do {
			// Test using default behavior and context
			let t = signal.transform(initialState: 10) { (state: inout Int, r: Result<Int, SignalEnd>, n: SignalNext<String>) in
				switch r {
				case .success(let v):
					XCTAssert(state == v + 10)
					state += 1
					n.send(value: "\(v)")
				case .failure(let e): n.send(end: e);
				}
			}
			
			let ep1 = t.subscribe { (r: Result<String, SignalEnd>) in
				results.append(r)
			}
			
			input.send(value: 0)
			input.send(value: 1)
			input.send(value: 2)
			input.close()
			
			withExtendedLifetime(ep1) {}
		}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == "0")
		XCTAssert(results.at(1)?.value == "1")
		XCTAssert(results.at(2)?.value == "2")
		XCTAssert(results.at(3)?.error?.isComplete == true)
		
		results.removeAll()
		
		// Test using custom context
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let (input2, signal2) = Signal<Int>.create()
		let ep2 = signal2.transform(initialState: 10, context: context) { (state: inout Int, r: Result<Int, SignalEnd>, n: SignalNext<String>) in
			switch r {
			case .success(let v):
				XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
				XCTAssert(state == v + 10)
				state += 1
				n.send(value: "\(v)")
			case .failure(let e): n.send(end: e);
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input2.send(value: 0)
		input2.send(value: 1)
		input2.send(value: 2)
		input2.close()
		
		withExtendedLifetime(ep2) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == "0")
		XCTAssert(results.at(1)?.value == "1")
		XCTAssert(results.at(2)?.value == "2")
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testEscapingTransformer() {
		var results = [Result<Double, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		var escapedNext: SignalNext<Double>? = nil
		var escapedValue: Int = 0
		let out = signal.transform { (r: Result<Int, SignalEnd>, n: SignalNext<Double>) in
			switch r {
			case .success(let v):
				escapedNext = n
				escapedValue = v
			case .failure(let e):
				n.send(end: e)
			}
		}.subscribe {
			results.append($0)
		}
		
		input.send(value: 1)
		XCTAssert(results.count == 0)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 1)
		
		input.send(value: 3)
		XCTAssert(results.count == 0)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 1)
		
		input.send(value: 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))
		
		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }
		
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 3)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))

		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }

		XCTAssert(results.count == 2)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))

		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }

		XCTAssert(results.count == 3)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(escapedNext == nil)
		XCTAssert(escapedValue == 5)
		
		withExtendedLifetime(out) {}
	}
	
	func testEscapingTransformerWithState() {
		var results = [Result<Double, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		var escapedNext: SignalNext<Double>? = nil
		var escapedValue: Int = 0
		let out = signal.transform(initialState: 0) { (s: inout Int, r: Result<Int, SignalEnd>, n: SignalNext<Double>) in
			switch r {
			case .success(let v):
				escapedNext = n
				escapedValue = v
			case .failure(let e):
				n.send(end: e)
			}
		}.subscribe {
			results.append($0)
		}
		
		input.send(value: 1)
		XCTAssert(results.count == 0)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 1)
		
		input.send(value: 3)
		XCTAssert(results.count == 0)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 1)
		
		input.send(value: 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))

		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }

		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 3)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))

		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }

		XCTAssert(results.count == 2)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))

		// Since releasing `escapedNext` will immediately cause `escapedNext` to be overwritten (clashing with the assign to `nil`) we need to copy to a non-shared location, clear the shared `escapedNext` first, then release the copy.
		withExtendedLifetime(escapedNext) { escapedNext = nil }

		XCTAssert(results.count == 3)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(escapedNext == nil)
		XCTAssert(escapedValue == 5)
		
		withExtendedLifetime(out) {}
	}
	
	func testClosedTriangleGraphLeft() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create { s in s.multicast() }
		let left = signal.transform { (r: Result<Int, SignalEnd>, n: SignalNext<Int>) in
			switch r {
			case .success(let v): n.send(value: v * 10)
			case .failure: n.send(error: TestError.oneValue)
			}
		}
		let (mergedInput, mergedSignal) = Signal<Int>.createMergedInput()
		mergedInput.add(left, closePropagation: .all)
		mergedInput.add(signal, closePropagation: .all)
		let out = mergedSignal.subscribe { r in results.append(r) }
		input.send(value: 3)
		input.send(value: 5)
		input.close()
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 30)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 50)
		XCTAssert(results.at(3)?.value == 5)
		XCTAssert(results.at(4)?.error?.otherError as? TestError == .oneValue)
	}
	
	func testClosedTriangleGraphRight() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create { s in s.multicast() }
		let (mergedInput, mergedSignal) = Signal<Int>.createMergedInput()
		mergedInput.add(signal, closePropagation: .all)
		let out = mergedSignal.subscribe { r in results.append(r) }
		let right = signal.transform { (r: Result<Int, SignalEnd>, n: SignalNext<Int>) in
			switch r {
			case .success(let v): n.send(value: v * 10)
			case .failure: n.send(error: TestError.oneValue)
			}
		}
		mergedInput.add(right, closePropagation: .all)
		input.send(value: 3)
		input.send(value: 5)
		input.close()
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 30)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 50)
		XCTAssert(results.at(4)?.error?.isComplete == true)
	}
	
	func testMergeSet() {
		do {
			var results = [Result<Int, SignalEnd>]()
			let (mergedInput, mergeSignal) = Signal<Int>.createMergedInput()
			let (input, out) = Signal<Int>.create { $0.subscribe { r in results.append(r) } }
			let disconnector = mergeSignal.junction()
			try disconnector.bind(to: input)
		
			let (input1, signal1) = Signal<Int>.create { $0.cacheUntilActive() }
			let (input2, signal2) = Signal<Int>.create { $0.cacheUntilActive() }
			let (input3, signal3) = Signal<Int>.create { $0.cacheUntilActive() }
			let (input4, signal4) = Signal<Int>.create { $0.cacheUntilActive() }
			mergedInput.add(signal1, closePropagation: .none, removeOnDeactivate: false)
			mergedInput.add(signal2, closePropagation: .all, removeOnDeactivate: false)
			mergedInput.add(signal3, closePropagation: .none, removeOnDeactivate: true)
			mergedInput.add(signal4, closePropagation: .none, removeOnDeactivate: false)
		
			input1.send(value: 3)
			input2.send(value: 4)
			input3.send(value: 5)
			input4.send(value: 9)
			input1.close()
		
			let reconnectable = disconnector.disconnect()
			try reconnectable.map { try disconnector.bind(to: $0) }
		
			mergedInput.remove(signal4)
		
			input1.send(value: 6)
			input2.send(value: 7)
			input3.send(value: 8)
			input4.send(value: 10)
			input2.close()
			input3.close()
		
			XCTAssert(results.count == 7)
			XCTAssert(results.at(0)?.value == 3)
			XCTAssert(results.at(1)?.value == 4)
			XCTAssert(results.at(2)?.value == 5)
			XCTAssert(results.at(3)?.value == 9)
			XCTAssert(results.at(4)?.value == 7)
			XCTAssert(results.at(5)?.value == 8)
			XCTAssert(results.at(6)?.error?.isComplete == true)
		
			withExtendedLifetime(out) {}
		} catch {
			XCTFail()
		}
	}
	
	func testSingleInput() {
		var results = Array<Result<Int, SignalEnd>>()
		let mergeSet = Signal<Int>.mergedChannel().subscribe { r in
			results.append(r)
		}
		mergeSet.input.send(value: 5)
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 5)
	}
	
	func testCombine2() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, context: context) { (cr: EitherResult2<Int, Double>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input1.send(value: 1)
		input1.send(value: 3)
		input1.close()
		input2.send(value: 5.0)
		input2.send(value: 7.0)
		input2.close()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "1 v: 1")
		XCTAssert(results.at(1)?.value == "1 v: 3")
		XCTAssert(results.at(2)?.value == "1 e: complete")
		XCTAssert(results.at(3)?.value == "2 v: 5.0")
		XCTAssert(results.at(4)?.value == "2 v: 7.0")
		XCTAssert(results.at(5)?.value == "2 e: complete")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine2WithState() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, initialState: "", context: context) { (state: inout String, cr: EitherResult2<Int, Double>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			state += "\(results.count)"
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v) \(state)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e) \(state)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v) \(state)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e) \(state)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input1.send(value: 1)
		input1.send(value: 3)
		input1.close()
		input2.send(value: 5.0)
		input2.send(value: 7.0)
		input2.close()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "1 v: 1 0")
		XCTAssert(results.at(1)?.value == "1 v: 3 01")
		XCTAssert(results.at(2)?.value == "1 e: complete 012")
		XCTAssert(results.at(3)?.value == "2 v: 5.0 0123")
		XCTAssert(results.at(4)?.value == "2 v: 7.0 01234")
		XCTAssert(results.at(5)?.value == "2 e: complete 012345")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine3() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, context: context) { (cr: EitherResult3<Int, Double, Int8>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		
		XCTAssert(results.count == 9)
		XCTAssert(results.at(0)?.value == "3 v: 13")
		XCTAssert(results.at(1)?.value == "1 v: 1")
		XCTAssert(results.at(2)?.value == "2 v: 5.0")
		XCTAssert(results.at(3)?.value == "1 v: 3")
		XCTAssert(results.at(4)?.value == "1 e: complete")
		XCTAssert(results.at(5)?.value == "3 v: 17")
		XCTAssert(results.at(6)?.value == "3 e: complete")
		XCTAssert(results.at(7)?.value == "2 v: 7.0")
		XCTAssert(results.at(8)?.value == "2 e: complete")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine3WithState() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, initialState: "", context: context) { (state: inout String, cr: EitherResult3<Int, Double, Int8>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			state += "\(results.count)"
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v) \(state)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e) \(state)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v) \(state)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e) \(state)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v) \(state)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e) \(state)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		
		XCTAssert(results.count == 9)
		XCTAssert(results.at(0)?.value == "3 v: 13 0")
		XCTAssert(results.at(1)?.value == "1 v: 1 01")
		XCTAssert(results.at(2)?.value == "2 v: 5.0 012")
		XCTAssert(results.at(3)?.value == "1 v: 3 0123")
		XCTAssert(results.at(4)?.value == "1 e: complete 01234")
		XCTAssert(results.at(5)?.value == "3 v: 17 012345")
		XCTAssert(results.at(6)?.value == "3 e: complete 0123456")
		XCTAssert(results.at(7)?.value == "2 v: 7.0 01234567")
		XCTAssert(results.at(8)?.value == "2 e: complete 012345678")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine4() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		let (input4, signal4) = Signal<Int16>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, signal4, context: context) { (cr: EitherResult4<Int, Double, Int8, Int16>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e)")
			case .result4(.success(let v)): n.send(value: "4 v: \(v)")
			case .result4(.failure(let e)): n.send(value: "4 e: \(e)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input4.send(value: 11)
		input4.send(value: 19)
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		input4.close()
		
		XCTAssert(results.count == 12)
		XCTAssert(results.at(0)?.value == "4 v: 11")
		XCTAssert(results.at(1)?.value == "4 v: 19")
		XCTAssert(results.at(2)?.value == "3 v: 13")
		XCTAssert(results.at(3)?.value == "1 v: 1")
		XCTAssert(results.at(4)?.value == "2 v: 5.0")
		XCTAssert(results.at(5)?.value == "1 v: 3")
		XCTAssert(results.at(6)?.value == "1 e: complete")
		XCTAssert(results.at(7)?.value == "3 v: 17")
		XCTAssert(results.at(8)?.value == "3 e: complete")
		XCTAssert(results.at(9)?.value == "2 v: 7.0")
		XCTAssert(results.at(10)?.value == "2 e: complete")
		XCTAssert(results.at(11)?.value == "4 e: complete")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine4WithState() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		let (input4, signal4) = Signal<Int16>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, signal4, initialState: "", context: context) { (state: inout String, cr: EitherResult4<Int, Double, Int8, Int16>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			state += "\(results.count)"
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v) \(state)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e) \(state)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v) \(state)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e) \(state)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v) \(state)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e) \(state)")
			case .result4(.success(let v)): n.send(value: "4 v: \(v) \(state)")
			case .result4(.failure(let e)): n.send(value: "4 e: \(e) \(state)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input4.send(value: 11)
		input4.send(value: 19)
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		input4.close()
		
		XCTAssert(results.count == 12)
		XCTAssert(results.at(0)?.value == "4 v: 11 0")
		XCTAssert(results.at(1)?.value == "4 v: 19 01")
		XCTAssert(results.at(2)?.value == "3 v: 13 012")
		XCTAssert(results.at(3)?.value == "1 v: 1 0123")
		XCTAssert(results.at(4)?.value == "2 v: 5.0 01234")
		XCTAssert(results.at(5)?.value == "1 v: 3 012345")
		XCTAssert(results.at(6)?.value == "1 e: complete 0123456")
		XCTAssert(results.at(7)?.value == "3 v: 17 01234567")
		XCTAssert(results.at(8)?.value == "3 e: complete 012345678")
		XCTAssert(results.at(9)?.value == "2 v: 7.0 0123456789")
		XCTAssert(results.at(10)?.value == "2 e: complete 012345678910")
		XCTAssert(results.at(11)?.value == "4 e: complete 01234567891011")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine5() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		let (input4, signal4) = Signal<Int16>.create()
		let (input5, signal5) = Signal<Int32>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, signal4, signal5, context: context) { (cr: EitherResult5<Int, Double, Int8, Int16, Int32>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e)")
			case .result4(.success(let v)): n.send(value: "4 v: \(v)")
			case .result4(.failure(let e)): n.send(value: "4 e: \(e)")
			case .result5(.success(let v)): n.send(value: "5 v: \(v)")
			case .result5(.failure(let e)): n.send(value: "5 e: \(e)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input4.send(value: 11)
		input4.send(value: 19)
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		input4.close()
		input5.send(value: 23)
		input5.send(error: TestError.oneValue)
		
		XCTAssert(results.count == 14)
		XCTAssert(results.at(0)?.value == "4 v: 11")
		XCTAssert(results.at(1)?.value == "4 v: 19")
		XCTAssert(results.at(2)?.value == "3 v: 13")
		XCTAssert(results.at(3)?.value == "1 v: 1")
		XCTAssert(results.at(4)?.value == "2 v: 5.0")
		XCTAssert(results.at(5)?.value == "1 v: 3")
		XCTAssert(results.at(6)?.value == "1 e: complete")
		XCTAssert(results.at(7)?.value == "3 v: 17")
		XCTAssert(results.at(8)?.value == "3 e: complete")
		XCTAssert(results.at(9)?.value == "2 v: 7.0")
		XCTAssert(results.at(10)?.value == "2 e: complete")
		XCTAssert(results.at(11)?.value == "4 e: complete")
		XCTAssert(results.at(12)?.value == "5 v: 23")
		XCTAssertEqual(results.at(13)?.value, "5 e: \(SignalEnd.other(TestError.oneValue))")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine5WithState() {
		var results = [Result<String, SignalEnd>]()
		
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Double>.create()
		let (input3, signal3) = Signal<Int8>.create()
		let (input4, signal4) = Signal<Int16>.create()
		let (input5, signal5) = Signal<Int32>.create()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(signal2, signal3, signal4, signal5, initialState: "", context: context) { (state: inout String, cr: EitherResult5<Int, Double, Int8, Int16, Int32>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			state += "\(results.count)"
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v) \(state)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e) \(state)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v) \(state)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e) \(state)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v) \(state)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e) \(state)")
			case .result4(.success(let v)): n.send(value: "4 v: \(v) \(state)")
			case .result4(.failure(let e)): n.send(value: "4 e: \(e) \(state)")
			case .result5(.success(let v)): n.send(value: "5 v: \(v) \(state)")
			case .result5(.failure(let e)): n.send(value: "5 e: \(e) \(state)")
			}
		}.subscribe { (r: Result<String, SignalEnd>) in
			results.append(r)
		}
		
		input4.send(value: 11)
		input4.send(value: 19)
		input3.send(value: 13)
		input1.send(value: 1)
		input2.send(value: 5.0)
		input1.send(value: 3)
		input1.close()
		input3.send(value: 17)
		input3.close()
		input2.send(value: 7.0)
		input2.close()
		input4.close()
		input5.send(value: 23)
		input5.send(error: TestError.oneValue)
		
		XCTAssert(results.count == 14)
		XCTAssert(results.at(0)?.value == "4 v: 11 0")
		XCTAssert(results.at(1)?.value == "4 v: 19 01")
		XCTAssert(results.at(2)?.value == "3 v: 13 012")
		XCTAssert(results.at(3)?.value == "1 v: 1 0123")
		XCTAssert(results.at(4)?.value == "2 v: 5.0 01234")
		XCTAssert(results.at(5)?.value == "1 v: 3 012345")
		XCTAssert(results.at(6)?.value == "1 e: complete 0123456")
		XCTAssert(results.at(7)?.value == "3 v: 17 01234567")
		XCTAssert(results.at(8)?.value == "3 e: complete 012345678")
		XCTAssert(results.at(9)?.value == "2 v: 7.0 0123456789")
		XCTAssert(results.at(10)?.value == "2 e: complete 012345678910")
		XCTAssert(results.at(11)?.value == "4 e: complete 01234567891011")
		XCTAssert(results.at(12)?.value == "5 v: 23 0123456789101112")
		XCTAssert(results.at(13)?.value == "5 e: \(SignalEnd.other(TestError.oneValue)) 012345678910111213")
		
		withExtendedLifetime(combined) {}
	}
	
	func testIsSignalClosed() {
		let v1 = Result<Int, SignalEnd>.success(5)
		let e1 = Result<Int, SignalEnd>.failure(.cancelled)
		let e2 = Result<Int, SignalEnd>.failure(SignalEnd.complete)
		let e3 = Result<Int, SignalEnd>.failure(.other(SignalReactiveError.timeout))
		XCTAssert(v1.isComplete == false)
		XCTAssert(e1.error?.isCancelled == true)
		XCTAssert(e2.error?.isComplete == true)
		XCTAssert(e3.isComplete == false)
	}
	
	func testToggle() {
		var results = [Result<Bool, SignalEnd>]()
		let (i, out) = Signal<Void>.channel().toggle(initialState: true).subscribe {
			results.append($0)
		}
		i.send(value: ())
		i.send(value: ())
		i.close()
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == true)
		XCTAssert(results.at(1)?.value == false)
		XCTAssert(results.at(2)?.value == true)
		XCTAssert(results.at(3)?.error?.isComplete == true)
		out.cancel()
	}
	
	func testOptionalToArray() {
		var results = [Result<[Int], SignalEnd>]()
		let (i, out) = Signal<Int?>.channel().optionalToArray().subscribe {
			results.append($0)
		}
		i.send(value: 1)
		i.send(value: nil)
		i.send(value: 2)
		i.send(value: nil)
		i.close()
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.count == 1)
		XCTAssert(results.at(0)?.value?.at(0) == 1)
		XCTAssert(results.at(1)?.value?.count == 0)
		XCTAssert(results.at(2)?.value?.count == 1)
		XCTAssert(results.at(2)?.value?.at(0) == 2)
		XCTAssert(results.at(3)?.value?.count == 0)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		out.cancel()
	}
	
	func testReactivateDeadlockBugAndStartWithActivationBug() {
		// This bug runs `if itemContextNeedsRefresh` in `send(result:predecessor:activationCount:activated:)` multiple times across different activations and deadlocks if the previous handler is released incorrectly.
		// It also tests startWith to ensure that it correctly sends *before* activation values, even though it normally sends during normal phase.
		var results = [Result<String?, SignalEnd>]()
		let sig1 = Signal<String?>.create { s in s.continuous(initialValue: "hello") }
		let sig2 = sig1.composed.startWith("boop")
		for _ in 1...3 {
			let out = sig2.subscribe(context: .main) { r in results.append(r) }
			out.cancel()
		}
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value.flatMap { $0 } == "boop")
		XCTAssert(results.at(1)?.value.flatMap { $0 } == "hello")
		XCTAssert(results.at(2)?.value.flatMap { $0 } == "boop")
		XCTAssert(results.at(3)?.value.flatMap { $0 } == "hello")
		XCTAssert(results.at(4)?.value.flatMap { $0 } == "boop")
		XCTAssert(results.at(5)?.value.flatMap { $0 } == "hello")
		withExtendedLifetime(sig1.input) {}
	}
	
	func testDeferActivation() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.continuous(initialValue: 3).deferActivation().map(context: coordinator.mainAsync) { $0 * 2 }.subscribe { r in
			results.append(r)
		}
		XCTAssert(results.isEmpty)
		coordinator.runScheduledTasks()
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 6)
		
		XCTAssert(coordinator.currentTime == 1)
		
		withExtendedLifetime(input) { }
		withExtendedLifetime(out) { }
	}
	
	func testDropActivation() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let out = signal.continuous(initialValue: 3).dropActivation().subscribe { r in
			results.append(r)
		}
		XCTAssert(results.isEmpty)
		input.send(value: 5)
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 5)
		
		withExtendedLifetime(input) { }
		withExtendedLifetime(out) { }
	}
	
	func testReconnector() {
		var results = [Result<Int, SignalEnd>]()
		var input: SignalInput<Int>? = nil
		let upstream = Signal<Int>.generate { i in
			input = i
		}
		var (reconnector, downstream) = upstream.reconnector()
		let out = downstream.subscribe { r in
			results.append(r)
		}
		input?.send(0, 1, 2)
		reconnector.disconnect()
		input?.send(3, 4, 5)
		reconnector.reconnect()
		input?.send(6, 7, 8)
		reconnector.disconnect()
		reconnector.disconnect()
		input?.send(9, 10, 11)
		reconnector.reconnect()
		reconnector.reconnect()
		input?.send(12, 13, 14)
		
		XCTAssert(results.count == 9)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 6)
		XCTAssert(results.at(4)?.value == 7)
		XCTAssert(results.at(5)?.value == 8)
		XCTAssert(results.at(6)?.value == 12)
		XCTAssert(results.at(7)?.value == 13)
		XCTAssert(results.at(8)?.value == 14)
		
		withExtendedLifetime(input) {}
		withExtendedLifetime(out) {}
	}
	
	func testDeadlockBug() {
		let context = Exec.asyncQueue()
		
		let signal1 = Signal.from([1])
			.continuous()
		
		let signal2 = signal1
			.map(context: context) { 2 * $0 }
			.continuous()
		
		let ex = expectation(description: "Waiting to ensure deadlock doesn't occur")
		var results = [Result<Int, SignalEnd>]()
		let ep = signal2.subscribe {
			results.append($0)
			ex.fulfill()
		}
		withExtendedLifetime(ep) {
			waitForExpectations(timeout: 2) { error in }
		}
		XCTAssert(results.at(0)?.error?.isComplete == true)
	}
}

class SignalTimingTests: XCTestCase {
	@inline(never)
	private static func noinlineMapFunction(_ value: Int) -> Result<Int, SignalEnd> {
		return Result<Int, SignalEnd>.success(value)
	}
	
	#if !SWIFT_PACKAGE
		func testSinglePerformance() {
			var sequenceLength = 10_000_000
			var expected = 4.3 // +/- 0.4
			var upperThreshold = 5.0
			
			// Override the test parameters when running in Debug.
			#if DEBUG
				sequenceLength = 10_000
				expected = 0.015 // +/- 0.15
				upperThreshold = 0.5
			#endif
			
			let t = mach_absolute_time()
			var count = 0
			
			// A basic test designed to exercise (sequence -> SignalInput -> SignalNode -> SignalQueue) performance.
			_ = Signal<Int>.generate(context: .direct) { input in
				guard let i = input else { return }
				for v in 0..<sequenceLength {
					if let _ = i.send(value: v) { break }
				}
				i.close()
			}.subscribe { r in
				switch r {
				case .success: count += 1
				case .failure: break
				}
			}
			
			XCTAssert(count == sequenceLength)
			let elapsed = 1e-9 * Double(mach_absolute_time() - t)
			XCTAssert(elapsed < upperThreshold)
			print("Performance is \(elapsed) seconds versus expected \(expected). Rate is \(Double(sequenceLength) / elapsed) per second.")
			
			// Approximate analogue to Signal architecture (sequence -> lazy map to Result -> iterate -> unwrap)
			let t2 = mach_absolute_time()
			var count2 = 0
			(0..<sequenceLength).lazy.map(SignalTimingTests.noinlineMapFunction).forEach { r in
				switch r {
				case .success: count2 += 1
				case .failure: break
				}
			}
			
			XCTAssert(count2 == sequenceLength)
			let elapsed2 = 1e-9 * Double(mach_absolute_time() - t2)
			print("Baseline is is \(elapsed2) seconds (\(elapsed / elapsed2) times faster).")
		}
		
		func testSyncMapPerformance() {
			var sequenceLength = 10_000_000
			var expected = 10.0 // +/- 0.4
			var upperThreshold = 12.0
			
			// Override the test parameters when running in Debug.
			#if DEBUG
				sequenceLength = 10_000
				expected = 0.03
				upperThreshold = 0.5
			#endif
			
			let t = mach_absolute_time()
			var count = 0
			
			// A basic test designed to exercise (sequence -> SignalInput -> SignalNode -> SignalQueue) performance.
			_ = Signal<Int>.generate(context: .direct) { input in
				guard let i = input else { return }
				for v in 0..<sequenceLength {
					if let _ = i.send(value: v) { break }
				}
				i.close()
			}.map { v in v }.subscribe { r in
				switch r {
				case .success: count += 1
				case .failure: break
				}
			}
			
			XCTAssert(count == sequenceLength)
			let elapsed = 1e-9 * Double(mach_absolute_time() - t)
			XCTAssert(elapsed < upperThreshold)
			print("Performance is \(elapsed) seconds versus expected \(expected). Rate is \(Double(sequenceLength) / elapsed) per second.")
			
			// Approximate analogue to Signal architecture (sequence -> lazy map to Result -> iterate -> unwrap)
			let t2 = mach_absolute_time()
			var count2 = 0
			(0..<sequenceLength).lazy.map(SignalTimingTests.noinlineMapFunction).forEach { r in
				switch r {
				case .success: count2 += 1
				case .failure: break
				}
			}
			
			XCTAssert(count2 == sequenceLength)
			let elapsed2 = 1e-9 * Double(mach_absolute_time() - t2)
			print("Baseline is is \(elapsed2) seconds (\(elapsed / elapsed2) times faster).")
		}
		
		func testAsyncMapPerformance() {
			var sequenceLength = 1_000_000
			var expected = 9.9 // +/- 0.4
			
			// Override the test parameters when running in Debug.
			#if DEBUG
				sequenceLength = 10_000
				expected = 0.2
			#endif
			
			let t1 = mach_absolute_time()
			var count1 = 0
			
			let ex = expectation(description: "Waiting for signal")
			
			// A basic test designed to exercise (sequence -> SignalInput -> SignalNode -> SignalQueue) performance.
			let out = Signal<Int>.generate { input in
				guard let i = input else { return }
				for v in 0..<sequenceLength {
					_ = i.send(value: v)
				}
			}.map(context: .global) { v in v }.subscribeValues(context: .main) { v in
				count1 += 1
				if count1 == sequenceLength {
					ex.fulfill()
				}
			}
			waitForExpectations(timeout: 1e2, handler: nil)
			withExtendedLifetime(out) {}
			
			precondition(count1 == sequenceLength)
			let elapsed1 = 1e-9 * Double(mach_absolute_time() - t1)
			print("Performance is \(elapsed1) seconds versus expected \(expected). Rate is \(Double(sequenceLength) / elapsed1) per second.")
		}
	
		@inline(never)
		private static func noinlineMapToDepthFunction(_ value: Int, _ depth: Int) -> Result<Int, SignalEnd> {
			var result = SignalTimingTests.noinlineMapFunction(value)
			for _ in 0..<depth {
				switch result {
				case .success(let v): result = SignalTimingTests.noinlineMapFunction(v)
				case .failure(let e): result = .failure(e)
				}
			}
			return result
		}
		
		func testDeepSyncPerformance() {
			var sequenceLength = 1_000_000
			var expected = 3.4 // +/- 0.4
			var upperThreshold = 6.5
			
			// Override the test parameters when running with Debug Assertions.
			// This is a hack but it avoids the need for conditional compilation options.
			#if DEBUG
				sequenceLength = 10_000
				expected = 0.2 // +/- 0.15
				upperThreshold = 3.0
			#endif
			
			let depth = 10
			let t = mach_absolute_time()
			var count = 0
			
			// Similar to the "Single" performance test but further inserts 100 map nodes between the initial node and the output
			var signal = Signal<Int>.generate { (input) in
				if let i = input {
					for x in 0..<sequenceLength {
						i.send(value: x)
					}
				}
			}
			
			for _ in 0..<depth {
				signal = signal.transform { r, n in n.send(result: r) }
			}
			_ = signal.subscribe { r in
				switch r {
				case .success: count += 1
				case .failure: break
				}
			}
			
			XCTAssert(count == sequenceLength)
			let elapsed = 1e-9 * Double(mach_absolute_time() - t)
			XCTAssert(elapsed < upperThreshold)
			print("Performance is \(elapsed) seconds versus expected \(expected). Rate is \(Double(sequenceLength * depth) / elapsed) per second.")
			
			let t2 = mach_absolute_time()
			var count2 = 0
			
			// Again, as close an equivalent as possible
			(0..<sequenceLength).lazy.map { SignalTimingTests.noinlineMapToDepthFunction($0, depth) }.forEach { r in
				switch r {
				case .success: count2 += 1
				case .failure: break
				}
			}
			
			XCTAssert(count2 == sequenceLength)
			let elapsed2 = 1e-9 * Double(mach_absolute_time() - t2)
			print("Baseline is is \(elapsed2) seconds (\(elapsed / elapsed2) times faster).")
		}
	#endif
	
	func testAsynchronousJoinAndDetach() {
		#if true
			let numRuns = 10
		#else
			// I've occasionally needed a very high number here to fully exercise some obscure threading bugs. It's not exactly time efficient for common usage.
			let numRuns = 10000
		#endif
		for run in 1...numRuns {
			asynchronousJoinAndDetachRun(run: run)
		}
	}
	
	func asynchronousJoinAndDetachRun(run: Int) {
		// This is a multi-threaded graph manipulation test.
		// Four threads continually try to disconnect the active graph and attach their own subgraph.
		// Important expectations:
		//  1. some should succeed to completion
		//  2. some should be interrupted
		//  3. streams of values should never arrive out-of-order
		// NOTE: Parameter tweaking may be required here.
		// This method tests thread contention over over a SignalJunction. Doing so may require tweaking of the following parameters to ensure the appropriate amount of contention occurs. A good target is an average of 25% completion and a range between 10% and 50% completion – this should ensure the test remains reliable under a wide range of host conditions.
		let sequenceLength = 10
		let iterations = 50
		let threadCount = 4
		let depth = 10
		var completionCount = 0
		var failureCount = 0
		var allOutputs = [String: SignalOutput<(thread: Int, iteration: Int, value: Int)>]()
		let junction = Signal<Int>.generate { (input) in
			if let i = input {
				for x in 0..<sequenceLength {
					i.send(value: x)
				}
				i.close()
			}
		}.junction()
		
		let triple = { (j: Int, i: Int, v: Int) -> String in
			return "Thread \(j), iteration \(i), value \(v)"
		}
		let double = { (j: Int, i: Int) -> String in
			return "Thread \(j), iteration \(i)"
		}
		let ex = expectation(description: "Waiting for thread completions")
		
		for j in 0..<threadCount {
			Exec.global.invoke {
				for i in 0..<iterations {
					let (input, s) = Signal<Int>.createMergedInput()
					var signal = s.transform(initialState: 0) { (count: inout Int, r: Result<Int, SignalEnd>, n: SignalNext<(thread: Int, iteration: Int, value: Int)>) in
						switch r {
						case .success(let v): n.send(value: (thread: j, iteration: i, value: v))
						case .failure(let e): n.send(end: e)
						}
					}
					
					for d in 0..<depth {
						signal = signal.transform(initialState: 0, context: .global) { (state: inout Int, r: Result<(thread: Int, iteration: Int, value: Int), SignalEnd>, n: SignalNext<(thread: Int, iteration: Int, value: Int)>) in
							switch r {
							case .success(let v):
								if v.value != state {
									XCTFail("Failed at depth \(d)")
								}
								state += 1
								n.send(value: v)
							case .failure(let e): n.send(end: e)
							}
						}
					}
					var results = [String]()
					let out = signal.subscribe(context: .direct) { r in
						switch r {
						case .success(let v): results.append(triple(v.thread, v.iteration, v.value))
						case .failure(SignalEnd.complete):
							XCTAssert(results.count == sequenceLength)
							let expected = Array(0..<results.count).map { triple(j, i, $0) }
							let match = results == expected
							XCTAssert(match)
							if !match {
								print("Mismatched on completion:\n\(results)")
							}
							DispatchQueue.main.async {
								completionCount += 1
								XCTAssert(allOutputs[double(j, i)] != nil)
								allOutputs.removeValue(forKey: double(j, i))
								if completionCount + failureCount == iterations * threadCount {
									ex.fulfill()
								}
							}
						case .failure(let e):
							XCTAssert(e.isComplete == false)
							let expected = Array(0..<results.count).map { triple(j, i, $0) }
							let match = results == expected
							XCTAssert(match)
							if !match {
								print("Mismatched on interruption:\n\(results)")
							}
							DispatchQueue.main.async {
								failureCount += 1
								XCTAssert(allOutputs[double(j, i)] != nil)
								allOutputs.removeValue(forKey: double(j, i))
								if completionCount + failureCount == iterations * threadCount {
									ex.fulfill()
								}
							}
						}
					}
					DispatchQueue.main.async { allOutputs[double(j, i)] = out }
					_ = junction.disconnect()
					_ = try? junction.bind(to: input, closePropagation: .all)
				}
			}
		}
		
		// This timeout is relatively low. It's helpful to get a failure message within a reasonable time.
		waitForExpectations(timeout: 1e1, handler: nil)
		
		XCTAssert(completionCount + failureCount == iterations * threadCount)
		XCTAssert(completionCount > threadCount)
		XCTAssert(completionCount < (iterations - 1) * threadCount)
		
		print("Finished run \(run) with completion count \(completionCount) of \(iterations * threadCount) (roughly 25% completion desired)")
	}
}
