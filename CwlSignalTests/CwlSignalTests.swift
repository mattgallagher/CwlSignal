//
//  CwlSignalTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/06/08.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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

private enum TestError: Error {
	case zeroValue
	case oneValue
	case twoValue
}

class SignalTests: XCTestCase {
	func testBasics() {
		var results = [Result<Int>]()
		let (i1, ep) = Signal<Int>.createPair { $0.subscribe { r in results.append(r) } }
		i1.send(result: .success(1))
		i1.send(value: 3)
		XCTAssert(ep.isClosed == false)
		ep.cancel()
		XCTAssert(ep.isClosed == true)
		i1.send(value: 5)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 3)
		withExtendedLifetime(ep) {}

		let (i2, ep2) = Signal<Int>.createPair { $0.transform { r, n in n.send(result: r) }.subscribe { r in results.append(r) } }
		i2.send(result: .success(5))
		i2.send(error: TestError.zeroValue)
		XCTAssert(i2.send(value: 0) == SignalError.cancelled)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error as? TestError == TestError.zeroValue)
		withExtendedLifetime(ep2) {}
		
		_ = Signal<Int>.preclosed().subscribe { r in results.append(r) }
		XCTAssert(results.at(4)?.isSignalClosed == true)
	}
	
	func testLifetimes() {
		weak var weakEndpoint1: SignalEndpoint<Int>? = nil
		weak var weakEndpoint2: SignalEndpoint<Int>? = nil
		weak var weakSignal1: Signal<Int>? = nil
		weak var weakSignal2: Signal<Int>? = nil
		var results1 = [Result<Int>]()
		var results2 = [Result<Int>]()
		do {
			let (input1, signal1) = Signal<Int>.createPair()
			weakSignal1 = signal1

			do {
				let endPoint = signal1.subscribe { (r: Result<Int>) in
					results1.append(r)
				}
				weakEndpoint1 = endPoint
				input1.send(result: .success(5))
				XCTAssert(weakEndpoint1 != nil)
				XCTAssert(weakSignal1 != nil)
				
				withExtendedLifetime(endPoint) {}
			}
			
			XCTAssert(weakEndpoint1 == nil)

			let (input2, signal2) = Signal<Int>.createPair()
			weakSignal2 = signal2

			do {
				do {
					let endPoint = signal2.subscribe { (r: Result<Int>) in
						results2.append(r)
					}
					weakEndpoint2 = endPoint
					endPoint.keepAlive()
				}
				input2.send(result: .success(5))
				XCTAssert(weakEndpoint2 != nil)
				XCTAssert(weakSignal2 != nil)
			}
			
			XCTAssert(weakEndpoint2 != nil)
			input2.close()
		}
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 5)
		XCTAssert(weakSignal1 == nil)

		XCTAssert(weakEndpoint2 == nil)

		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.error as? SignalError == .closed)
		XCTAssert(weakSignal2 == nil)
	}
	
	func testcreatePairAndSignal() {
		// Create a signal with default behavior
		let (input, signal) = Signal<Int>.createPair()
		
		// Make sure we get an .Inactive response before anything is connected
		XCTAssert(input.send(result: .success(321)) == SignalError.inactive)
		
		// Subscribe
		var results = [Result<Int>]()
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let ep1 = signal.subscribe(context: context) { r in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			results.append(r)
		}
		
		// Ensure we don't immediately receive anything
		XCTAssert(results.count == 0)
		
		// Adding a second subscriber cancels the first
		var results2 = [Result<Int>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.error as? SignalError == SignalError.duplicate)
		
		// Send a value and close
		XCTAssert(input.send(result: .success(123)) == nil)
		XCTAssert(input.send(result: .failure(SignalError.closed)) == nil)
		
		// Confirm sending worked
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 123)
		XCTAssert(results.at(1)?.error as? SignalError == SignalError.closed)
		
		// Confirm we can't send to a closed signal
		XCTAssert(input.send(result: .success(234)) == SignalError.cancelled)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}
	
	func testSignalPassthrough() {
		// Create a restartable
		let (input, s) = Signal<Int>.createPair()
		let signal = s.multicast()
		
		// Make sure we get an .Inactive response before anything is connected
		XCTAssert(input.send(result: .success(321)) == SignalError.inactive)
		
		// Subscribe send and close
		var results1 = [Result<Int>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		
		// Ensure we don't immediately receive anything
		XCTAssert(results1.count == 0)
		
		// Send a value and close
		XCTAssert(input.send(result: .success(123)) == nil)
		XCTAssert(results1.count == 1)
		XCTAssert(results1.at(0)?.value == 123)
		
		// Subscribe and send again, leaving open
		var results2 = [Result<Int>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		XCTAssert(input.send(result: .success(345)) == nil)
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(1)?.value == 345)
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.value == 345)
		
		// Add a third subscriber
		var results3 = [Result<Int>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		XCTAssert(input.send(result: .success(678)) == nil)
		XCTAssert(input.close() == nil)
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(2)?.value == 678)
		XCTAssert(results1.at(3)?.error as? SignalError == .closed)
		XCTAssert(results3.count == 2)
		XCTAssert(results3.at(0)?.value == 678)
		XCTAssert(results3.at(1)?.error as? SignalError == .closed)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(1)?.value == 678)
		XCTAssert(results2.at(2)?.error as? SignalError == .closed)
		
		XCTAssert(input.send(value: 0) == .cancelled)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	func testSignalContinuous() {
		// Create a signal
		let (input, s) = Signal<Int>.createPair()
		let signal = s.continuous()
		
		// Subscribe twice
		var results1 = [Result<Int>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int>]()
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
		var results3 = [Result<Int>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		XCTAssert(results3.count == 1)
		XCTAssert(results3.at(0)?.value == 123)
		
		// Send another
		XCTAssert(input.send(result: .success(234)) == nil)
		
		// Subscribe again, leaving open
		var results4 = [Result<Int>]()
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
		XCTAssert(input.send(result: .failure(SignalError.closed)) == nil)
		XCTAssert(results1.count == 3)
		XCTAssert(results1.at(2)?.error as? SignalError == SignalError.closed)
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(2)?.error as? SignalError == SignalError.closed)
		XCTAssert(results3.count == 3)
		XCTAssert(results3.at(2)?.error as? SignalError == SignalError.closed)
		XCTAssert(results4.count == 2)
		XCTAssert(results4.at(1)?.error as? SignalError == SignalError.closed)
		
		// Subscribe again, leaving open
		var results5 = [Result<Int>]()
		let ep5 = signal.subscribe { r in results5.append(r) }
		XCTAssert(results5.count == 1)
		XCTAssert(results5.at(0)?.error as? SignalError == SignalError.closed)
		
		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
		withExtendedLifetime(ep4) {}
		withExtendedLifetime(ep5) {}
	}
	
	func testSignalContinuousWithInitialValue() {
		// Create a signal
		let (input, s) = Signal<Int>.createPair()
		let signal = s.continuous(initialValue: 5)
		
		// Subscribe twice
		var results1 = [Result<Int>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int>]()
		let ep2 = signal.subscribe { r in results2.append(r) }
		
		// Ensure we immediately receive the initialValue
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
		let (input, s) = Signal<Int>.createPair()
		let signal = s.playback()
		
		// Send a value and leave open
		XCTAssert(input.send(value: 3) == nil)
		XCTAssert(input.send(value: 4) == nil)
		XCTAssert(input.send(value: 5) == nil)
		
		// Subscribe twice
		var results1 = [Result<Int>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int>]()
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
		XCTAssert(input.send(error: SignalError.closed) == nil)
		
		// Subscribe again
		var results3 = [Result<Int>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		
		XCTAssert(results1.count == 5)
		XCTAssert(results2.count == 5)
		XCTAssert(results3.count == 5)
		XCTAssert(results1.at(4)?.isSignalClosed == true)
		XCTAssert(results2.at(4)?.isSignalClosed == true)
		XCTAssert(results3.at(0)?.value == 3)
		XCTAssert(results3.at(1)?.value == 4)
		XCTAssert(results3.at(2)?.value == 5)
		XCTAssert(results3.at(3)?.value == 6)
		XCTAssert(results3.at(4)?.isSignalClosed == true)

		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	func testSignalCacheUntilActive() {
		// Create a signal
		let (input, s) = Signal<Int>.createPair()
		let signal = s.cacheUntilActive()
		
		// Send a value and leave open
		XCTAssert(input.send(result: .success(5)) == nil)
		
		do {
			// Subscribe once
			var results1 = [Result<Int>]()
			let ep1 = signal.subscribe { r in results1.append(r) }
			
			// Ensure we immediately receive the values
			XCTAssert(results1.count == 1)
			XCTAssert(results1.at(0)?.value == 5)
			
			// Subscribe again
			var results2 = [Result<Int>]()
			let ep2 = signal.subscribe { r in results2.append(r) }
			
			// Ensure error received
			XCTAssert(results2.count == 1)
			XCTAssert(results2.at(0)?.error as? SignalError == SignalError.duplicate)
			
			withExtendedLifetime(ep1) {}
			withExtendedLifetime(ep2) {}
		}
		
		// Send a value again
		XCTAssert(input.send(result: .success(7)) == nil)
		
		do {
			// Subscribe once
			var results3 = [Result<Int>]()
			let ep3 = signal.subscribe { r in results3.append(r) }
			
			// Ensure we get just the value sent after reactivation
			XCTAssert(results3.count == 1)
			XCTAssert(results3.at(0)?.value == 7)

			withExtendedLifetime(ep3) {}
		}
	}
	
	func testSignalBuffer() {
		// Create a signal
		let (input, s) = Signal<Int>.createPair()
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let signal = s.buffer(context: context, initialValues: [3, 4]) { (activationValues: inout Array<Int>, preclosed: inout Error?, result: Result<Int>) -> Void in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			if case .success(6) = result {
				activationValues = [7]
			}
		}
		
		// Send a value and leave open
		XCTAssert(input.send(value: 5) == nil)
		
		// Subscribe twice
		var results1 = [Result<Int>]()
		let ep1 = signal.subscribe { r in results1.append(r) }
		var results2 = [Result<Int>]()
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
		var results3 = [Result<Int>]()
		let ep3 = signal.subscribe { r in results3.append(r) }
		
		XCTAssert(results1.count == 3)
		XCTAssert(results2.count == 3)
		XCTAssert(results3.at(0)?.value == 7)

		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
		withExtendedLifetime(ep3) {}
	}
	
	func testPreclosed() {
		var results1 = [Result<Int>]()
		_ = Signal<Int>.preclosed(values: [1, 3, 5], error: TestError.oneValue).subscribe { r in
			results1.append(r)
		}
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 3)
		XCTAssert(results1.at(2)?.value == 5)
		XCTAssert(results1.at(3)?.error as? TestError == .oneValue)

		var results2 = [Result<Int>]()
		_ = Signal<Int>.preclosed().subscribe { r in
			results2.append(r)
		}
		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.error as? SignalError == .closed)
	}
	
	func testCapture() {
		let (input, s) = Signal<Int>.createPair()
		let signal = s.continuous()
		input.send(value: 1)
		
		let capture = signal.capture()
		var results = [Result<Int>]()
		let (subsequentInput, subsequentSignal) = Signal<Int>.createPair()
		let ep = subsequentSignal.subscribe { (r: Result<Int>) in
			results.append(r)
		}
		
		// Send a value between construction and join. This must be *blocked* in the capture queue.
		XCTAssert(input.send(value: 5) == nil)

		let (values, error) = capture.activation()
		do {
			try capture.join(toInput: subsequentInput)
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
		XCTAssert(results.at(2)?.isSignalClosed == true)

		withExtendedLifetime(ep) {}
	}
	
	func testCaptureAndSubscribe() {
		let (input, output) = Signal<Int>.createPair { signal in signal.continuous() }
		input.send(value: 1)
		input.send(value: 2)

		do {
			let capture = output.capture()
			let (values, error) = capture.activation()
			XCTAssert(values == [2])
			XCTAssert(error == nil)

			input.send(value: 3)

			var results = [Result<Int>]()
			_ = capture.subscribe { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0)?.value == 3)
		}

		do {
			let capture = output.capture()
			let (values, error) = capture.activation()
			XCTAssert(values == [3])
			XCTAssert(error == nil)

			input.send(value: 4)

			var results = [Result<Int>]()
			_ = capture.subscribe(onError: { (j, e, i) in }) { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0)?.value == 4)
		}

		withExtendedLifetime(input) {}
	}
	
	func testCaptureAndSubscribeValues() {
		let (input, output) = Signal<Int>.createPair { signal in signal.continuous() }
		input.send(value: 1)
		input.send(value: 2)

		do {
			let capture = output.capture()
			let (values, error) = capture.activation()
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
			let (values, error) = capture.activation()
			XCTAssert(values == [3])
			XCTAssert(error == nil)

			input.send(value: 4)

			var results = [Int]()
			_ = capture.subscribeValues(onError: { (j, e, i) in }) { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0) == 4)
		}
		
		withExtendedLifetime(input) {}
	}
	
	func testCaptureOnError() {
		let (input, s) = Signal<Int>.createPair()
		let signal = s.continuous()
		input.send(value: 1)
		
		let capture = signal.capture()
		var results = [Result<Int>]()
		let (subsequentInput, subsequentSignal) = Signal<Int>.createPair()
		let ep1 = subsequentSignal.subscribe { (r: Result<Int>) in
			results.append(r)
		}
		
		let (values, error) = capture.activation()
		
		do {
			try capture.join(toInput: subsequentInput) { (c: SignalCapture<Int>, e: Error, i: SignalInput<Int>) in
				XCTAssert(c === capture)
				XCTAssert(e as? SignalError == .closed)
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
		XCTAssert(results.at(1)?.error as? TestError == .twoValue)
		
		let (values2, error2) = capture.activation()
		XCTAssert(values2.count == 0)
		XCTAssert(error2 as? SignalError == .closed)
		
		let pc = Signal<Int>.preclosed(values: [], error: TestError.oneValue)
		let capture2 = pc.capture()
		let (values3, error3) = capture2.activation()

		var results2 = [Result<Int>]()
		let (subsequentInput2, subsequentSignal2) = Signal<Int>.createPair()
		let ep2 = subsequentSignal2.subscribe { (r: Result<Int>) in
			results2.append(r)
		}

		do {
			try capture2.join(toInput: subsequentInput2, resend: true) { (c, e, i) in
				XCTAssert(c === capture2)
				XCTAssert(e as? TestError == .oneValue)
				i.send(error: TestError.zeroValue)
			}
		} catch {
			XCTFail()
		}
		
		XCTAssert(values3 == [])
		XCTAssert(error3 as? TestError == .oneValue)

		XCTAssert(results2.count == 1)
		XCTAssert(results2.at(0)?.error as? TestError == .zeroValue)

		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}
	
	func testGenerate() {
		var count = 0
		var results = [Result<Int>]()
		weak var lifetimeCheck: Box<()>? = nil
		var nilCount = 0
		do {
			let closureLifetime = Box<()>()
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
					i.send(error: SignalError.closed)
				}
				withExtendedLifetime(closureLifetime) {}
			}
			
			do {
				let ep1 = s.subscribe { (r: Result<Int>) in
					results.append(r)
				}
				
				XCTAssert(results.count == 6)
				XCTAssert(results.at(0)?.value == 0)
				XCTAssert(results.at(1)?.value == 1)
				XCTAssert(results.at(2)?.value == 2)
				XCTAssert(results.at(3)?.value == 3)
				XCTAssert(results.at(4)?.value == 4)
				XCTAssert(results.at(5)?.error as? TestError == .zeroValue)
				withExtendedLifetime(ep1) {}
			}
			
			let ep2 = s.subscribe { (r: Result<Int>) in
				results.append(r)
			}
			
			XCTAssert(results.count == 12)
			XCTAssert(results.at(6)?.value == 10)
			XCTAssert(results.at(7)?.value == 11)
			XCTAssert(results.at(8)?.value == 12)
			XCTAssert(results.at(9)?.value == 13)
			XCTAssert(results.at(10)?.value == 14)
			XCTAssert(results.at(11)?.isSignalClosed == true)
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
		
		var results = [Result<Int>]()
		
		do {
			let (i1, s) = Signal<Int>.createPair()
			let ep = s.subscribe { results.append($0) }
			let d = try sequence1.join(toInput: i1)
			i1.send(value: 3)
			
			XCTAssert(results.count == 3)
			XCTAssert(results.at(0)?.value == 0)
			XCTAssert(results.at(1)?.value == 1)
			XCTAssert(results.at(2)?.value == 2)
			
			if let i2 = d.disconnect() {
				let d2 = try sequence2.join(toInput: i2)
				i2.send(value: 6)
				
				XCTAssert(results.count == 7)
				XCTAssert(results.at(3)?.value == 3)
				XCTAssert(results.at(4)?.value == 4)
				XCTAssert(results.at(5)?.value == 5)
				XCTAssert(results.at(6)?.error as? SignalError == .cancelled)
				
				if let i3 = d2.disconnect() {
					_ = try d.join(toInput: i3)
					i3.send(value: 3)
					
					XCTAssert(results.count == 7)
				} else {
					XCTFail()
				}
			} else {
				XCTFail()
			}
			withExtendedLifetime(ep) {}
		} catch {
			XCTFail()
		}
		
		withExtendedLifetime(firstInput) {}
		
		var results2 = [Result<Int>]()
		let (i4, ep2) = Signal<Int>.createPair { $0.subscribe {
			results2.append($0)
		} }

		do {
			try sequence3.join(toInput: i4) { d, e, i in
				XCTAssert(e as? SignalError == .cancelled)
				i.send(value: 7)
				i.close()
			}
		} catch {
			XCTFail()
		}
	
		XCTAssert(results2.count == 3)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.value == 7)
		XCTAssert(results2.at(2)?.error as? SignalError == .closed)
		
		withExtendedLifetime(ep2) {}
	}
	
	func testJunctionSignal() {
		var results = [Result<Int>]()
		var endpoints = [Cancellable]()

		do {
			let signal = Signal<Int>.generate { i in _ = i?.send(value: 5) }
			let (_, output) = signal.junctionSignal { (j, err, input) in
				XCTAssert(err as? SignalError == SignalError.cancelled)
				input.close()
			}
			endpoints += output.subscribe { r in results += r }
			XCTAssert(results.count == 2)
			XCTAssert(results.at(1)?.isSignalClosed == true)
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
			let (junction, output) = signal.junctionSignal()
			endpoints += output.subscribe { r in results += r }
			XCTAssert(results.count == 1)
			XCTAssert(results.at(0)?.value == 5)
			junction.rejoin()
			XCTAssert(results.count == 2)
			XCTAssert(results.at(1)?.value == 5)
			junction.rejoin { (j, err, i) in
				XCTAssert(err as? SignalError == SignalError.closed)
				i.send(error: TestError.zeroValue)
			}
			XCTAssert(results.count == 4)
			XCTAssert(results.at(3)?.error as? TestError == TestError.zeroValue)
			withExtendedLifetime(input) {}
		}
	}

	func testGraphLoop() {
		var results = [Result<Int>]()
		var looped = [Result<Int>]()
		weak var weakInput1: SignalInput<Int>? = nil
		weak var weakInput2: SignalInput<Int>? = nil
		weak var weakInput3: SignalInput<Int>? = nil
		weak var weakSignal1: Signal<Int>? = nil
		weak var weakSignal2: Signal<Int>? = nil
		weak var weakEndpoint: SignalEndpoint<Int>? = nil
		do {
			let (input1, signal1) = Signal<Int>.createPair()
			var (input2, signal2) = Signal<Int>.createPair()
			weakInput1 = input1
			weakInput2 = input2
			weakSignal1 = signal1
			weakSignal2 = signal2
			
			XCTAssert(weakInput1 != nil)
			XCTAssert(weakInput2 != nil)
			XCTAssert(weakSignal1 != nil)
			XCTAssert(weakSignal2 != nil)

			let combined = signal1.combine(second: signal2) { (cr: EitherResult2<Int, Int>, next: SignalNext<Int>) in
				switch cr {
				case .result1(let r): next.send(result: r)
				case .result2(let r): looped.append(r)
				}
			}.transform { r, n in n.send(result: r) }.continuous()
			do {
				try combined.join(toInput: input2)
				XCTFail()
			} catch SignalJoinError<Int>.loop(let i) {
				input2 = i
				weakInput3 = i
			} catch {
				XCTFail()
			}
			let ep2 = combined.subscribe { r in
				input2.send(result: r)
			}
			let ep = combined.subscribe { (r: Result<Int>) in
				results.append(r)
			}
			weakEndpoint = ep
			XCTAssert(weakEndpoint != nil)
			input1.send(value: 5)
			input1.close()
			withExtendedLifetime(ep) {}
			withExtendedLifetime(ep2) {}
		}
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)

		XCTAssert(looped.count == 1)
		XCTAssert(looped.at(0)?.value == 5)
		
		XCTAssert(weakInput1 == nil)
		XCTAssert(weakInput2 == nil)
		XCTAssert(weakInput3 == nil)
		XCTAssert(weakSignal1 == nil)
		XCTAssert(weakSignal2 == nil)
		XCTAssert(weakEndpoint == nil)
	}
	
	func testTransform() {
		let (input, signal) = Signal<Int>.createPair()
		var results = [Result<String>]()
		
		// Test using default behavior and context
		let ep1 = signal.transform { (r: Result<Int>, n: SignalNext<String>) in
			switch r {
			case .success(let v): n.send(value: "\(v)")
			case .failure(let e): n.send(error: e)
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
		
		results.removeAll()
		
		// Test using custom behavior and context
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let (input2, signal2) = Signal<Int>.createPair()
		let ep2 = signal2.transform(context: context) { (r: Result<Int>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch r {
			case .success(let v): n.send(value: "\(v)")
			case .failure(let e): n.send(error: e)
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(3)?.error as? SignalError == .cancelled)

		withExtendedLifetime(ep1) {}
		withExtendedLifetime(ep2) {}
	}

	func testTransformWithState() {
		let (input, signal) = Signal<Int>.createPair()
		var results = [Result<String>]()
		
		// Scope the creation of 't' so we can ensure it is removed before we re-add to the signal.
		do {
			// Test using default behavior and context
			let t = signal.transform(withState: 10) { (state: inout Int, r: Result<Int>, n: SignalNext<String>) in
				switch r {
				case .success(let v):
					XCTAssert(state == v + 10)
					state += 1
					n.send(value: "\(v)")
				case .failure(let e): n.send(error: e);
				}
			}
			
			let ep1 = t.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
		
		results.removeAll()
		
		// Test using custom context
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let (input2, signal2) = Signal<Int>.createPair()
		let ep2 = signal2.transform(withState: 10, context: context) { (state: inout Int, r: Result<Int>, n: SignalNext<String>) in
			switch r {
			case .success(let v):
				XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
				XCTAssert(state == v + 10)
				state += 1
				n.send(value: "\(v)")
			case .failure(let e): n.send(error: e);
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
	}
	
	func testEscapingTransformer() {
		var results = [Result<Double>]()
		let (input, signal) = Signal<Int>.createPair()
		var escapedNext: SignalNext<Double>? = nil
		var escapedValue: Int = 0
		let ep = signal.transform { (r: Result<Int>, n: SignalNext<Double>) in
			switch r {
			case .success(let v):
				escapedNext = n
				escapedValue = v
			case .failure(let e):
				n.send(error: e)
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
		escapedNext = nil
		
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 3)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))
		escapedNext = nil
		
		XCTAssert(results.count == 2)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))
		escapedNext = nil
		
		XCTAssert(results.count == 3)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(escapedNext == nil)
		XCTAssert(escapedValue == 5)
		
		withExtendedLifetime(ep) {}
	}
	
	func testEscapingTransformerWithState() {
		var results = [Result<Double>]()
		let (input, signal) = Signal<Int>.createPair()
		var escapedNext: SignalNext<Double>? = nil
		var escapedValue: Int = 0
		let ep = signal.transform(withState: 0) { ( s: inout Int, r: Result<Int>, n: SignalNext<Double>) in
			switch r {
			case .success(let v):
				escapedNext = n
				escapedValue = v
			case .failure(let e):
				n.send(error: e)
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
		escapedNext = nil
		
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 3)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))
		escapedNext = nil
		
		XCTAssert(results.count == 2)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(escapedNext != nil)
		XCTAssert(escapedValue == 5)
		
		_ = escapedNext?.send(value: Double(escapedValue * 2))
		escapedNext = nil
		
		XCTAssert(results.count == 3)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(escapedNext == nil)
		XCTAssert(escapedValue == 5)
		
		withExtendedLifetime(ep) {}
	}
	
	func testClosedTriangleGraphLeft() {
		var results = [Result<Int>]()
		let (input, signal) = Signal<Int>.createPair { s in s.multicast() }
		let left = signal.transform { (r: Result<Int>, n: SignalNext<Int>) in
			switch r {
			case .success(let v): n.send(value: v * 10)
			case .failure: n.send(error: TestError.oneValue)
			}
		}
		let (_, ep) = Signal<Int>.mergeSetAndSignal([left, signal], closesOutput: true) { s in s.subscribe { r in results.append(r) } }
		input.send(value: 3)
		input.send(value: 5)
		input.close()
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 30)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 50)
		XCTAssert(results.at(3)?.value == 5)
		XCTAssert(results.at(4)?.error as? TestError == .oneValue)
	}

	func testClosedTriangleGraphRight() {
		var results = [Result<Int>]()
		let (input, signal) = Signal<Int>.createPair { s in s.multicast() }
		let (mergeSet, signal2) = Signal<Int>.mergeSetAndSignal([signal], closesOutput: true)
		let ep = signal2.subscribe { r in results.append(r) }
		let right = signal.transform { (r: Result<Int>, n: SignalNext<Int>) in
			switch r {
			case .success(let v): n.send(value: v * 10)
			case .failure: n.send(error: TestError.oneValue)
			}
		}
		mergeSet.add(right, closesOutput: true)
		input.send(value: 3)
		input.send(value: 5)
		input.close()
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 30)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 50)
		XCTAssert(results.at(4)?.error as? SignalError == .closed)
	}

	func testMergeSet() {
		do {
			var results = [Result<Int>]()
			let (mergeSet, mergeSignal) = Signal<Int>.mergeSetAndSignal()
			let (input, ep) = Signal<Int>.createPair { $0.subscribe { r in results.append(r) } }
			let disconnector = try mergeSignal.join(toInput: input)
			
			let (input1, signal1) = Signal<Int>.createPair { $0.cacheUntilActive() }
			let (input2, signal2) = Signal<Int>.createPair { $0.cacheUntilActive() }
			let (input3, signal3) = Signal<Int>.createPair { $0.cacheUntilActive() }
			let (input4, signal4) = Signal<Int>.createPair { $0.cacheUntilActive() }
			mergeSet.add(signal1, closesOutput: false, removeOnDeactivate: false)
			mergeSet.add(signal2, closesOutput: true, removeOnDeactivate: false)
			mergeSet.add(signal3, closesOutput: false, removeOnDeactivate: true)
			mergeSet.add(signal4, closesOutput: false, removeOnDeactivate: false)
			
			input1.send(value: 3)
			input2.send(value: 4)
			input3.send(value: 5)
			input4.send(value: 9)
			input1.close()
			
			let reconnectable = disconnector.disconnect()
			try reconnectable.map { _ = try disconnector.join(toInput: $0) }
			
			mergeSet.remove(signal4)
			
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
			XCTAssert(results.at(6)?.isSignalClosed == true)
			
			withExtendedLifetime(ep) {}
		} catch {
			XCTFail()
		}
	}
	
	func testCombine2() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(second: signal2, context: context) { (cr: EitherResult2<Int, Double>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(2)?.value == "1 e: closed")
		XCTAssert(results.at(3)?.value == "2 v: 5.0")
		XCTAssert(results.at(4)?.value == "2 v: 7.0")
		XCTAssert(results.at(5)?.value == "2 e: closed")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine2WithState() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(withState: "", second: signal2, context: context) { (state: inout String, cr: EitherResult2<Int, Double>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			state += "\(results.count)"
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v) \(state)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e) \(state)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v) \(state)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e) \(state)")
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(2)?.value == "1 e: closed 012")
		XCTAssert(results.at(3)?.value == "2 v: 5.0 0123")
		XCTAssert(results.at(4)?.value == "2 v: 7.0 01234")
		XCTAssert(results.at(5)?.value == "2 e: closed 012345")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine3() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(second: signal2, third: signal3, context: context) { (cr: EitherResult3<Int, Double, Int8>, n: SignalNext<String>) in
			XCTAssert(DispatchQueue.getSpecific(key: specificKey) != nil)
			switch cr {
			case .result1(.success(let v)): n.send(value: "1 v: \(v)")
			case .result1(.failure(let e)): n.send(value: "1 e: \(e)")
			case .result2(.success(let v)): n.send(value: "2 v: \(v)")
			case .result2(.failure(let e)): n.send(value: "2 e: \(e)")
			case .result3(.success(let v)): n.send(value: "3 v: \(v)")
			case .result3(.failure(let e)): n.send(value: "3 e: \(e)")
			}
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(4)?.value == "1 e: closed")
		XCTAssert(results.at(5)?.value == "3 v: 17")
		XCTAssert(results.at(6)?.value == "3 e: closed")
		XCTAssert(results.at(7)?.value == "2 v: 7.0")
		XCTAssert(results.at(8)?.value == "2 e: closed")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine3WithState() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(withState: "", second: signal2, third: signal3, context: context) { (state: inout String, cr: EitherResult3<Int, Double, Int8>, n: SignalNext<String>) in
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
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(4)?.value == "1 e: closed 01234")
		XCTAssert(results.at(5)?.value == "3 v: 17 012345")
		XCTAssert(results.at(6)?.value == "3 e: closed 0123456")
		XCTAssert(results.at(7)?.value == "2 v: 7.0 01234567")
		XCTAssert(results.at(8)?.value == "2 e: closed 012345678")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine4() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		let (input4, signal4) = Signal<Int16>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(second: signal2, third: signal3, fourth: signal4, context: context) { (cr: EitherResult4<Int, Double, Int8, Int16>, n: SignalNext<String>) in
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
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(6)?.value == "1 e: closed")
		XCTAssert(results.at(7)?.value == "3 v: 17")
		XCTAssert(results.at(8)?.value == "3 e: closed")
		XCTAssert(results.at(9)?.value == "2 v: 7.0")
		XCTAssert(results.at(10)?.value == "2 e: closed")
		XCTAssert(results.at(11)?.value == "4 e: closed")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine4WithState() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		let (input4, signal4) = Signal<Int16>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(withState: "", second: signal2, third: signal3, fourth: signal4, context: context) { (state: inout String, cr: EitherResult4<Int, Double, Int8, Int16>, n: SignalNext<String>) in
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
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(6)?.value == "1 e: closed 0123456")
		XCTAssert(results.at(7)?.value == "3 v: 17 01234567")
		XCTAssert(results.at(8)?.value == "3 e: closed 012345678")
		XCTAssert(results.at(9)?.value == "2 v: 7.0 0123456789")
		XCTAssert(results.at(10)?.value == "2 e: closed 012345678910")
		XCTAssert(results.at(11)?.value == "4 e: closed 01234567891011")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine5() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		let (input4, signal4) = Signal<Int16>.createPair()
		let (input5, signal5) = Signal<Int32>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(second: signal2, third: signal3, fourth: signal4, fifth: signal5, context: context) { (cr: EitherResult5<Int, Double, Int8, Int16, Int32>, n: SignalNext<String>) in
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
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(6)?.value == "1 e: closed")
		XCTAssert(results.at(7)?.value == "3 v: 17")
		XCTAssert(results.at(8)?.value == "3 e: closed")
		XCTAssert(results.at(9)?.value == "2 v: 7.0")
		XCTAssert(results.at(10)?.value == "2 e: closed")
		XCTAssert(results.at(11)?.value == "4 e: closed")
		XCTAssert(results.at(12)?.value == "5 v: 23")
		XCTAssert(results.at(13)?.value == "5 e: oneValue")
		
		withExtendedLifetime(combined) {}
	}
	
	func testCombine5WithState() {
		var results = [Result<String>]()
		
		let (input1, signal1) = Signal<Int>.createPair()
		let (input2, signal2) = Signal<Double>.createPair()
		let (input3, signal3) = Signal<Int8>.createPair()
		let (input4, signal4) = Signal<Int16>.createPair()
		let (input5, signal5) = Signal<Int32>.createPair()
		
		let (context, specificKey) = Exec.syncQueueWithSpecificKey()
		let combined = signal1.combine(withState: "", second: signal2, third: signal3, fourth: signal4, fifth: signal5, context: context) { (state: inout String, cr: EitherResult5<Int, Double, Int8, Int16, Int32>, n: SignalNext<String>) in
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
		}.subscribe { (r: Result<String>) in
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
		XCTAssert(results.at(6)?.value == "1 e: closed 0123456")
		XCTAssert(results.at(7)?.value == "3 v: 17 01234567")
		XCTAssert(results.at(8)?.value == "3 e: closed 012345678")
		XCTAssert(results.at(9)?.value == "2 v: 7.0 0123456789")
		XCTAssert(results.at(10)?.value == "2 e: closed 012345678910")
		XCTAssert(results.at(11)?.value == "4 e: closed 01234567891011")
		XCTAssert(results.at(12)?.value == "5 v: 23 0123456789101112")
		XCTAssert(results.at(13)?.value == "5 e: oneValue 012345678910111213")
		
		withExtendedLifetime(combined) {}
	}
	
	@inline(never)
	private static func noinlineMapFunction(_ value: Int) -> Result<Int> {
		return Result<Int>.success(value)
	}
	
	func testSinglePerformance() {
		#if DEBUG
			let sequenceLength = 10_000
			let expected = 0.015 // +/- 0.15
			let upperThreshold = 0.5
		#else
			let sequenceLength = 10_000_000
			let expected = 3.0 // +/- 0.4
			let upperThreshold = 4.0
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
		(0..<sequenceLength).lazy.map(SignalTests.noinlineMapFunction).forEach { r in
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
		#if DEBUG
			let sequenceLength = 10_000
			let expected = 0.03 // +/- 0.15
			let upperThreshold = 0.5
		#else
			let sequenceLength = 10_000_000
			let expected = 6.0 // +/- 0.4
			let upperThreshold = 8.0
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
		(0..<sequenceLength).lazy.map(SignalTests.noinlineMapFunction).forEach { r in
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
		#if DEBUG
			let sequenceLength = 10_000
			let expected = 0.02 // +/- 0.15
		#else
			let sequenceLength = 1_000_000
			let expected = 3.3 // +/- 0.4
		#endif

		let t1 = mach_absolute_time()
		var count1 = 0
		
		let ex = expectation(description: "Waiting for signal")
		
	 		// A basic test designed to exercise (sequence -> SignalInput -> SignalNode -> SignalQueue) performance.
		let ep = Signal<Int>.generate { input in
			guard let i = input else { return }
			for v in 0..<sequenceLength {
				_ = i.send(value: v)
			}
		}.map(context: .default) { v in v }.subscribeValues(context: .main) { v in
			count1 += 1
			if count1 == sequenceLength {
				ex.fulfill()
			}
		}
		waitForExpectations(timeout: 1e2, handler: nil)
		withExtendedLifetime(ep) {}
	
		precondition(count1 == sequenceLength)
		let elapsed1 = 1e-9 * Double(mach_absolute_time() - t1)
		print("Performance is \(elapsed1) seconds versus expected \(expected). Rate is \(Double(sequenceLength) / elapsed1) per second.")
	}

	@inline(never)
	private static func noinlineMapToDepthFunction(_ value: Int, _ depth: Int) -> Result<Int> {
		var result = SignalTests.noinlineMapFunction(value)
		for _ in 0..<depth {
			switch result {
			case .success(let v): result = SignalTests.noinlineMapFunction(v)
			case .failure(let e): result = .failure(e)
			}
		}
		return result
	}
	
	func testDeepSyncPerformance() {
		#if DEBUG
			let sequenceLength = 10_000
			let expected = 0.02 // +/- 0.15
			let upperThreshold = 1.0
		#else
			let sequenceLength = 1_000_000
			let expected = 3.2 // +/- 0.4
			let upperThreshold = 6.5
		#endif
		let depth = 10
		let t = mach_absolute_time()
		var count = 0
		
		// Similar to the "Single" performance test but further inserts 100 map nodes between the initial node and the endpoint
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
		(0..<sequenceLength).lazy.map { SignalTests.noinlineMapToDepthFunction($0, depth) }.forEach { r in
			switch r {
			case .success: count2 += 1
			case .failure: break
			}
		}
		
		XCTAssert(count2 == sequenceLength)
		let elapsed2 = 1e-9 * Double(mach_absolute_time() - t2)
		print("Baseline is is \(elapsed2) seconds (\(elapsed / elapsed2) times faster).")
	}

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
		var allEndpoints = [String: SignalEndpoint<(thread: Int, iteration: Int, value: Int)>]()
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
			Exec.default.invoke {
				for i in 0..<iterations {
					let (input, s) = Signal<Int>.createPair()
					var signal = s.transform(withState: 0) { (count: inout Int, r: Result<Int>, n: SignalNext<(thread: Int, iteration: Int, value: Int)>) in
						switch r {
						case .success(let v): n.send(value: (thread: j, iteration: i, value: v))
						case .failure(let e): n.send(error: e)
						}
					}

					for d in 0..<depth {
						signal = signal.transform(withState: 0, context: .default) { (state: inout Int, r: Result<(thread: Int, iteration: Int, value: Int)>, n: SignalNext<(thread: Int, iteration: Int, value: Int)>) in
							switch r {
							case .success(let v):
								if v.value != state {
									XCTFail("Failed at depth \(d)")
								}
								state += 1
								n.send(value: v)
							case .failure(let e): n.send(error: e)
							}
						}
					}
					var results = [String]()
					let ep = signal.subscribe(context: .direct) { r in
						switch r {
						case .success(let v): results.append(triple(v.thread, v.iteration, v.value))
						case .failure(SignalError.closed):
							XCTAssert(results.count == sequenceLength)
							let expected = Array(0..<results.count).map { triple(j, i, $0) }
							let match = results == expected
							XCTAssert(match)
							if !match {
								print("Mismatched on completion:\n\(results)")
							}
							DispatchQueue.main.async {
								completionCount += 1
								XCTAssert(allEndpoints[double(j, i)] != nil)
								allEndpoints.removeValue(forKey: double(j, i))
								if completionCount + failureCount == iterations * threadCount {
									ex.fulfill()
								}
							}
						case .failure(let e):
							XCTAssert(e as? SignalError != .closed)
							let expected = Array(0..<results.count).map { triple(j, i, $0) }
							let match = results == expected
							XCTAssert(match)
							if !match {
								print("Mismatched on interruption:\n\(results)")
							}
							DispatchQueue.main.async {
								failureCount += 1
								XCTAssert(allEndpoints[double(j, i)] != nil)
								allEndpoints.removeValue(forKey: double(j, i))
								if completionCount + failureCount == iterations * threadCount {
									ex.fulfill()
								}
							}
						}
					}
					DispatchQueue.main.async { allEndpoints[double(j, i)] = ep }
					_ = junction.disconnect()
					_ = try? junction.join(toInput: input)
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
	
	func testIsSignalClosed() {
		let v1 = Result<Int>.success(5)
		let e1 = Result<Int>.failure(SignalError.cancelled)
		let e2 = Result<Int>.failure(SignalError.closed)
		XCTAssert(v1.isSignalClosed == false)
		XCTAssert(e1.isSignalClosed == false)
		XCTAssert(e2.isSignalClosed == true)
	}
}
