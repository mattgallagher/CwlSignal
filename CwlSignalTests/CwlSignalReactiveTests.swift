//
//  CwlSignalReactiveTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/09/08.
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
import CwlUtils

private enum TestError: Error {
	case zeroValue
	case oneValue
	case twoValue
}

class SignalReactiveTests: XCTestCase {
	func testNever() {
		var results = [Result<Int>]()
		let ep = Signal.never().subscribe { r in
			results.append(r)
		}
		XCTAssert(results.isEmpty)
		XCTAssert(ep.isClosed == false)
		ep.cancel()
		XCTAssert(results.isEmpty)
		XCTAssert(ep.isClosed == true)
	}
	
	func testFromSequence() {
		var results = [Result<Int>]()
		let capture = Signal<Int>.fromSequence([1, 3, 5, 7, 11]).capture()
		let (input, signal) = Signal<Int>.createInput()
		let ep = signal.subscribe { r in results.append(r) }
		let (values, error) = capture.activation()
		do {
			try capture.join(toInput: input)
		} catch {
			input.send(error: error)
		}
		withExtendedLifetime(ep) {}
		XCTAssert(values.isEmpty)
		XCTAssert(error == nil)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 7)
		XCTAssert(results.at(4)?.value == 11)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testInterval() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		let ep = intervalSignal(seconds: 0.01, context: coordinator.direct).subscribe { r in
			results.append(r)
			if let v = r.value, v == 3 {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.error as? SignalError == .cancelled)
		XCTAssert(coordinator.currentTime == 40_000_000)
	}
	
	func testRepeatCollection() {
		var results = [Result<Int>]()
		_ = Signal.repeatCollection([1, 3, 5, 7, 11], count: 3).subscribe { r in results.append(r) }
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 7)
		XCTAssert(results.at(4)?.value == 11)
		XCTAssert(results.at(5)?.value == 1)
		XCTAssert(results.at(6)?.value == 3)
		XCTAssert(results.at(7)?.value == 5)
		XCTAssert(results.at(8)?.value == 7)
		XCTAssert(results.at(9)?.value == 11)
		XCTAssert(results.at(10)?.value == 1)
		XCTAssert(results.at(11)?.value == 3)
		XCTAssert(results.at(12)?.value == 5)
		XCTAssert(results.at(13)?.value == 7)
		XCTAssert(results.at(14)?.value == 11)
		XCTAssert(results.at(15)?.isSignalClosed == true)
	}
	
	func testStart() {
		var results = [Result<Int>]()
		_ = Signal<Int>.start() { 5 }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.isSignalClosed == true)
	}
	
	func testTimer() {
		var results = [Result<()>]()
		let coordinator = DebugContextCoordinator()
		let ep = timerSignal(seconds: 0.01, context: coordinator.direct).subscribe { r in
			results.append(r)
			if r.isError {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}
		
		XCTAssert(coordinator.currentTime == 10_000_000)
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value != nil)
		XCTAssert(results.at(1)?.isSignalClosed == true)
	}
	
	func testBufferCount() {
		var results = [Result<[Int]>]()
		let signal = Signal<Int>.fromSequence(1...10)
		_ = signal.buffer(count: 3, skip: 2).subscribe {
			results.append($0)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value.map { (v: [Int]) -> Bool in v == [1, 2, 3] } == true)
		XCTAssert(results.at(1)?.value.map { (v: [Int]) -> Bool in v == [3, 4, 5] } == true)
		XCTAssert(results.at(2)?.value.map { (v: [Int]) -> Bool in v == [5, 6, 7] } == true)
		XCTAssert(results.at(3)?.value.map { (v: [Int]) -> Bool in v == [7, 8, 9] } == true)
		XCTAssert(results.at(4)?.value.map { (v: [Int]) -> Bool in v == [9, 10] } == true)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testBufferSeconds() {
		var results = [Result<[Int]>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		let ep = signal.buffer(seconds: 0.02, count: 3, context: coordinator.direct).subscribe { r in
			results.append(r)
			if results.count == 4 {
				coordinator.stop()
			}
		}
		XCTAssert(results.isEmpty)
		
		for i in 1...10 {
			input.send(value: i)
		}
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value.map { (v: [Int]) -> Bool in v == [1, 2, 3] } == true)
		XCTAssert(results.at(1)?.value.map { (v: [Int]) -> Bool in v == [4, 5, 6] } == true)
		XCTAssert(results.at(2)?.value.map { (v: [Int]) -> Bool in v == [7, 8, 9] } == true)

		coordinator.runScheduledTasks()

		XCTAssert(coordinator.currentTime == 20_000_000)
		
		withExtendedLifetime(input) { }
		withExtendedLifetime(ep) { }
	}
	
	func testFlatMap() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([1, 3, 5, 7, 11]).flatMap { v in
			return Signal<Int>.generate(context: .direct) { input in
				guard let i = input else { return }
				for v in 0...v {
					if let _ = i.send(value: v) {
						break
					}
				}
				i.close()
			}
		}.subscribe { r in
			results.append(r)
		}
		XCTAssert(results.count == 33)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 0)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 2)
		XCTAssert(results.at(5)?.value == 3)
		XCTAssert(results.at(6)?.value == 0)
		XCTAssert(results.at(7)?.value == 1)
		XCTAssert(results.at(8)?.value == 2)
		XCTAssert(results.at(9)?.value == 3)
		XCTAssert(results.at(10)?.value == 4)
		XCTAssert(results.at(11)?.value == 5)
		XCTAssert(results.at(12)?.value == 0)
		XCTAssert(results.at(13)?.value == 1)
		XCTAssert(results.at(14)?.value == 2)
		XCTAssert(results.at(15)?.value == 3)
		XCTAssert(results.at(16)?.value == 4)
		XCTAssert(results.at(17)?.value == 5)
		XCTAssert(results.at(18)?.value == 6)
		XCTAssert(results.at(19)?.value == 7)
		XCTAssert(results.at(20)?.value == 0)
		XCTAssert(results.at(21)?.value == 1)
		XCTAssert(results.at(22)?.value == 2)
		XCTAssert(results.at(23)?.value == 3)
		XCTAssert(results.at(24)?.value == 4)
		XCTAssert(results.at(25)?.value == 5)
		XCTAssert(results.at(26)?.value == 6)
		XCTAssert(results.at(27)?.value == 7)
		XCTAssert(results.at(28)?.value == 8)
		XCTAssert(results.at(29)?.value == 9)
		XCTAssert(results.at(30)?.value == 10)
		XCTAssert(results.at(31)?.value == 11)
		XCTAssert(results.at(32)?.error as? SignalError == .cancelled)
	}
	
	func testGroupBy() {
		var results = Dictionary<Int, Array<Result<Int>>>()
		_ = Signal.fromSequence(1...20).groupBy { v in v % 3 }.subscribe { r in
			if let v = r.value {
				results[v.0] = Array<Result<Int>>()
				v.1.subscribe { r in
					results[v.0]!.append(r)
				}.keepAlive()
			} else {
				XCTAssert(r.isSignalClosed)
			}
		}
		XCTAssert(results.count == 3)
		let r1 = results[0]
		let r2 = results[1]
		let r3 = results[2]
		XCTAssert(r1?.count == 7)
		XCTAssert(r1?.at(0)?.value == 3)
		XCTAssert(r1?.at(1)?.value == 6)
		XCTAssert(r1?.at(2)?.value == 9)
		XCTAssert(r1?.at(3)?.value == 12)
		XCTAssert(r1?.at(4)?.value == 15)
		XCTAssert(r1?.at(5)?.value == 18)
		XCTAssert(r1?.at(6)?.isSignalClosed == true)
		XCTAssert(r2?.count == 8)
		XCTAssert(r2?.at(0)?.value == 1)
		XCTAssert(r2?.at(1)?.value == 4)
		XCTAssert(r2?.at(2)?.value == 7)
		XCTAssert(r2?.at(3)?.value == 10)
		XCTAssert(r2?.at(4)?.value == 13)
		XCTAssert(r2?.at(5)?.value == 16)
		XCTAssert(r2?.at(6)?.value == 19)
		XCTAssert(r2?.at(7)?.isSignalClosed == true)
		XCTAssert(r3?.count == 8)
		XCTAssert(r3?.at(0)?.value == 2)
		XCTAssert(r3?.at(1)?.value == 5)
		XCTAssert(r3?.at(2)?.value == 8)
		XCTAssert(r3?.at(3)?.value == 11)
		XCTAssert(r3?.at(4)?.value == 14)
		XCTAssert(r3?.at(5)?.value == 17)
		XCTAssert(r3?.at(6)?.value == 20)
		XCTAssert(r3?.at(7)?.isSignalClosed == true)
	}
	
	func testMap() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence(1...5).map { v in v * 2 }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 6)
		XCTAssert(results.at(3)?.value == 8)
		XCTAssert(results.at(4)?.value == 10)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testScan() {
		var results = [Result<Int>]()
		Signal.fromSequence(1...5).scan(2) { a, v in a + v }.subscribe { r in results.append(r) }.keepAlive()
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 5)
		XCTAssert(results.at(2)?.value == 8)
		XCTAssert(results.at(3)?.value == 12)
		XCTAssert(results.at(4)?.value == 17)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testWindow() {
		var results = Array<Array<Result<Int>>>()
		let coordinator = DebugContextCoordinator()
		let (input, ep) = Signal<Int>.createInput { s in
			s.window(seconds: 0.2, count: 5, context: coordinator.direct).subscribe { r in
				if let v = r.value {
					let index = results.count
					results.append(Array<Result<Int>>())
					v.subscribe { r in
						results[index].append(r)
					}.keepAlive()
				} else {
					XCTAssert(r.isSignalClosed)
				}
			}
		}
		for i in 1...12 {
			input.send(value: i)
		}
		let delay = coordinator.direct.singleTimer(interval: .fromSeconds(0.5)) {
			input.send(value: 13)
			input.close()
		}
		XCTAssert(results.count == 3)
		let r1 = results.at(0)
		let r2 = results.at(1)
		let r3 = results.at(2)
		XCTAssert(r1?.count == 6)
		XCTAssert(r1?.at(0)?.value == 1)
		XCTAssert(r1?.at(1)?.value == 2)
		XCTAssert(r1?.at(2)?.value == 3)
		XCTAssert(r1?.at(3)?.value == 4)
		XCTAssert(r1?.at(4)?.value == 5)
		XCTAssert(r1?.at(5)?.isSignalClosed == true)
		XCTAssert(r2?.count == 6)
		XCTAssert(r2?.at(0)?.value == 6)
		XCTAssert(r2?.at(1)?.value == 7)
		XCTAssert(r2?.at(2)?.value == 8)
		XCTAssert(r2?.at(3)?.value == 9)
		XCTAssert(r2?.at(4)?.value == 10)
		XCTAssert(r2?.at(5)?.isSignalClosed == true)
		XCTAssert(r3?.count == 2)
		XCTAssert(r3?.at(0)?.value == 11)
		XCTAssert(r3?.at(1)?.value == 12)
		coordinator.runScheduledTasks()

		XCTAssert(coordinator.currentTime == 500_000_000)
		XCTAssert(results.count == 4)
		let r4 = results.at(3)
		XCTAssert(r4?.count == 2)
		XCTAssert(r4?.at(0)?.value == 13)
		XCTAssert(r4?.at(1)?.error as? SignalError == .cancelled)
		
		withExtendedLifetime(ep) { }
		withExtendedLifetime(delay) { }
		withExtendedLifetime(input) { }
	}
	
	func testDebounce() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		var delayedInputs = [Cancellable]()
		let delays: [Int] = [4, 8, 12, 16, 60, 64, 68, 72, 120, 124, 128, 170, 174, 220, 224]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.main.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		
		let ep = signal.debounce(seconds: 0.02, context: coordinator.direct).take(5).subscribe { r in
			results.append(r)
			if r.error != nil {
				coordinator.stop()
			}
		}
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) { }
		withExtendedLifetime(delayedInputs) { }
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 7)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(results.at(3)?.value == 12)
		XCTAssert(results.at(4)?.value == 14)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testThrottleFirst() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		var delayedInputs = [Cancellable]()
		let delays: [Int] = [4, 8, 12, 16, 60, 64, 68, 72, 120, 124, 128, 170, 174, 220, 224]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.main.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}

		let ep = signal.throttleFirst(seconds: 0.02, context: coordinator.direct).take(5).subscribe { r in
			results.append(r)
			if r.error != nil {
				coordinator.stop()
			}
		}
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) { }
		withExtendedLifetime(delayedInputs) { }
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 8)
		XCTAssert(results.at(3)?.value == 11)
		XCTAssert(results.at(4)?.value == 13)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testDistinct() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 0, 1, 2, 3, 5, 5, 1, 0, 2, 7, 5]).distinct().subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 5)
		XCTAssert(results.at(5)?.value == 7)
		XCTAssert(results.at(6)?.isSignalClosed == true)
	}
	
	func testDistinctUntilChanged() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 0, 1, 1, 1, 5, 5, 1, 0, 0, 7]).distinctUntilChanged().subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.value == 7)
		XCTAssert(results.at(6)?.isSignalClosed == true)
	}
	
	func testDistinctUntilChangedWithComparator() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 1, 0, 1, 2, 3, 3, 5]).distinctUntilChanged() { a, b in a + 1 == b }.subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 0)
		XCTAssert(results.at(2)?.value == 3)
		XCTAssert(results.at(3)?.value == 5)
		XCTAssert(results.at(4)?.isSignalClosed == true)
	}
	
	func testElementAt() {
		var r0 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).elementAt(3).subscribe { (r: Result<Int>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 8)
		XCTAssert(r0.at(1)?.isSignalClosed == true)
		
		var r1 = [Result<Int>]()
		_ = Signal<Int>.preclosed(values: [12, 13, 14, 15, 16], error: SignalError.cancelled).elementAt(5).subscribe { (r: Result<Int>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 1)
		XCTAssert(r1.at(0)?.error as? SignalError == SignalError.cancelled)
	}
	
	func testFilter() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 0, 1, 2, 3, 5, 5, 1, 4, 6, 0, 2, 7, 5]).filter() { v in (v % 2) == 0 }.subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 8)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 0)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 4)
		XCTAssert(results.at(4)?.value == 6)
		XCTAssert(results.at(5)?.value == 0)
		XCTAssert(results.at(6)?.value == 2)
		XCTAssert(results.at(7)?.isSignalClosed == true)
	}
	
	func testOfType() {
		var results = [Result<NSString>]()
		let sequence: [AnyObject] = [NSString(string: "hello"), NSObject(), NSString(string: "world")]
		_ = Signal.fromSequence(sequence).ofType(NSString.self).subscribe { (r: Result<NSString>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == "hello")
		XCTAssert(results.at(1)?.value == "world")
		XCTAssert(results.at(2)?.isSignalClosed == true)
	}
	
	func testFirst() {
		var r0 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).first().subscribe { (r: Result<Int>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 5)
		XCTAssert(r0.at(1)?.isSignalClosed == true)
		
		var r1 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).first() { v in v > 7 }.subscribe { (r: Result<Int>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 8)
		XCTAssert(r1.at(1)?.isSignalClosed == true)
	}
	
	func testSingle() {
		var r0 = [Result<Int>]()
		_ = Signal.fromSequence([5, 5, 5, 7, 7, 7, 8, 8, 8]).single { $0 == 7 }.subscribe { (r: Result<Int>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 1)
		XCTAssert(r0.at(0)?.isSignalClosed == true)
		
		var r1 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).single { $0 == 7 }.subscribe { (r: Result<Int>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 7)
		XCTAssert(r1.at(1)?.isSignalClosed == true)
		
		var r2 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 8, 9, 10]).single { $0 == 7 }.subscribe { (r: Result<Int>) -> Void in
			r2.append(r)
		}
		XCTAssert(r2.count == 1)
		XCTAssert(r2.at(0)?.isSignalClosed == true)
		
		var r3 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 8, 9, 10]).single().subscribe { (r: Result<Int>) -> Void in
			r3.append(r)
		}
		XCTAssert(r3.count == 1)
		XCTAssert(r3.at(0)?.isSignalClosed == true)
		
		var r4 = [Result<Int>]()
		_ = Signal.fromSequence([5]).single().subscribe { (r: Result<Int>) -> Void in
			r4.append(r)
		}
		XCTAssert(r4.count == 2)
		XCTAssert(r4.at(0)?.value == 5)
		XCTAssert(r4.at(1)?.isSignalClosed == true)
	}
	
	func testIgnoreElements() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 0, 1, 2, 3, 5, 5, 1, 4, 6, 0, 2, 7, 5]).ignoreElements().subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.isSignalClosed == true)
	}
	
	func testLast() {
		var r0 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).last().subscribe { (r: Result<Int>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 10)
		XCTAssert(r0.at(1)?.isSignalClosed == true)
		
		var r1 = [Result<Int>]()
		_ = Signal.fromSequence([5, 6, 7, 8, 9, 10]).last() { v in v < 7 }.subscribe { (r: Result<Int>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 6)
		XCTAssert(r1.at(1)?.isSignalClosed == true)
	}
	
	func testSample() {
		var results = [Result<Int>]()
		let (input, signal) = Signal<Int>.createInput()
		let (triggerInput, trigger) = Signal<()>.createInput()
		let sample = signal.sample(trigger)
		let ep = sample.subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		
		input.send(value: 1)
		triggerInput.send(value: ())
		
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 5)
		triggerInput.send(value: ())
		
		input.send(value: 7)
		input.send(value: 11)
		input.send(value: 13)
		triggerInput.send(value: ())
		
		input.close()
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 5)
		XCTAssert(results.at(2)?.value == 13)
		XCTAssert(results.at(3)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testSkip() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 1, 2, 3, 4, 5, 6, 7]).skip(3).subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 6)
		XCTAssert(results.at(4)?.value == 7)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testSkipLast() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 1, 2, 3, 4, 5, 6, 7]).skipLast(3).subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 4)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testTake() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 1, 2, 3, 4, 5, 6, 7]).take(3).subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.isSignalClosed == true)
	}
	
	func testTakeLast() {
		var results = [Result<Int>]()
		_ = Signal.fromSequence([0, 1, 2, 3, 4, 5, 6, 7]).takeLast(3).subscribe { (r: Result<Int>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(results.at(2)?.value == 7)
		XCTAssert(results.at(3)?.isSignalClosed == true)
	}
	
	func testCombineLatest2() {
		var results = [Result<String>]()
		let (signal1Input, signal1) = Signal<Int>.createInput()
		let (signal2Input, signal2) = Signal<Double>.createInput()
		let combined = signal1.combineLatest(second: signal2) {
			"\($0) \($1)"
		}
		let ep = combined.subscribe { (r: Result<String>) -> Void in
			results.append(r)
		}
		
		signal1Input.send(value: -1)
		signal1Input.send(value: 0)
		signal2Input.send(value: 1.1)
		signal2Input.send(value: 2.2)
		signal2Input.send(value: 3.3)
		signal1Input.send(value: 1)
		signal1Input.send(value: 2)
		
		signal2Input.close()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 1.1")
		XCTAssert(results.at(1)?.value == "0 2.2")
		XCTAssert(results.at(2)?.value == "0 3.3")
		XCTAssert(results.at(3)?.value == "1 3.3")
		XCTAssert(results.at(4)?.value == "2 3.3")
		XCTAssert(results.at(5)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testCombineLatest3() {
		var results = [Result<String>]()
		let (signal1Input, signal1) = Signal<Int>.createInput()
		let (signal2Input, signal2) = Signal<Double>.createInput()
		let (signal3Input, signal3) = Signal<String>.createInput()
		let combined = signal1.combineLatest(second: signal2, third: signal3) {
			"\($0) \($1) \($2)"
		}
		let ep = combined.subscribe { (r: Result<String>) -> Void in
			results.append(r)
		}
		
		signal1Input.send(value: -1)
		signal1Input.send(value: 0)
		signal2Input.send(value: 1.1)
		signal2Input.send(value: 2.2)
		signal3Input.send(value: "Hello")
		signal2Input.send(value: 3.3)
		signal3Input.send(value: "World")
		signal1Input.send(value: 1)
		signal3Input.send(value: "!")
		
		signal1Input.close()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello")
		XCTAssert(results.at(2)?.value == "0 3.3 World")
		XCTAssert(results.at(3)?.value == "1 3.3 World")
		XCTAssert(results.at(4)?.value == "1 3.3 !")
		XCTAssert(results.at(5)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testCombineLatest4() {
		var results = [Result<String>]()
		let (signal1Input, signal1) = Signal<Int>.createInput()
		let (signal2Input, signal2) = Signal<Double>.createInput()
		let (signal3Input, signal3) = Signal<String>.createInput()
		let (signal4Input, signal4) = Signal<Int>.createInput()
		let combined = signal1.combineLatest(second: signal2, third: signal3, fourth: signal4) {
			"\($0) \($1) \($2) \($3)"
		}
		let ep = combined.subscribe { (r: Result<String>) -> Void in
			results.append(r)
		}
		
		signal1Input.send(value: -1)
		signal1Input.send(value: 0)
		signal2Input.send(value: 1.1)
		signal4Input.send(value: 10)
		signal2Input.send(value: 2.2)
		signal4Input.send(value: 11)
		signal3Input.send(value: "Hello")
		signal2Input.send(value: 3.3)
		signal4Input.send(value: 12)
		signal3Input.send(value: "World")
		signal1Input.send(value: 1)
		
		signal1Input.close()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello 11")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello 11")
		XCTAssert(results.at(2)?.value == "0 3.3 Hello 12")
		XCTAssert(results.at(3)?.value == "0 3.3 World 12")
		XCTAssert(results.at(4)?.value == "1 3.3 World 12")
		XCTAssert(results.at(5)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testCombineLatest5() {
		var results = [Result<String>]()
		let (signal1Input, signal1) = Signal<Int>.createInput()
		let (signal2Input, signal2) = Signal<Double>.createInput()
		let (signal3Input, signal3) = Signal<String>.createInput()
		let (signal4Input, signal4) = Signal<Int>.createInput()
		let (signal5Input, signal5) = Signal<Bool>.createInput()
		let combined = signal1.combineLatest(second: signal2, third: signal3, fourth: signal4, fifth: signal5) {
			"\($0) \($1) \($2) \($3) \($4)"
		}
		let ep = combined.subscribe { (r: Result<String>) -> Void in
			results.append(r)
		}
		
		signal5Input.send(value: true)
		signal1Input.send(value: -1)
		signal1Input.send(value: 0)
		signal2Input.send(value: 1.1)
		signal4Input.send(value: 10)
		signal2Input.send(value: 2.2)
		signal4Input.send(value: 11)
		signal3Input.send(value: "Hello")
		signal2Input.send(value: 3.3)
		signal4Input.send(value: 12)
		signal3Input.send(value: "World")
		signal1Input.send(value: 1)
		signal5Input.send(value: false)
		
		signal1Input.close()
		
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello 11 true")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello 11 true")
		XCTAssert(results.at(2)?.value == "0 3.3 Hello 12 true")
		XCTAssert(results.at(3)?.value == "0 3.3 World 12 true")
		XCTAssert(results.at(4)?.value == "1 3.3 World 12 true")
		XCTAssert(results.at(5)?.value == "1 3.3 World 12 false")
		XCTAssert(results.at(6)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testJoin() {
		var results1 = [Result<String>]()
		let (leftInput1, leftSignal1) = Signal<Int>.createInput()
		let (rightInput1, rightSignal1) = Signal<Double>.createInput()
		let ep1 = leftSignal1.join(withRight: rightSignal1, leftEnd: { v -> Signal<()> in Signal<()>.preclosed() }, rightEnd: { v in Signal<()>.preclosed() }) { (l, r) in return "Unexpected \(l) \(r)" }.subscribe {
			results1.append($0)
		}
		leftInput1.send(value: 0)
		rightInput1.send(value: 1.1)
		leftInput1.send(value: 8)
		leftInput1.send(value: 9)
		rightInput1.send(value: 2.2)
		rightInput1.send(value: 3.3)
		leftInput1.send(value: 10)
		rightInput1.send(value: 4.4)
		leftInput1.close()
		XCTAssert(results1.count == 1)
		XCTAssert(results1.first?.isSignalClosed == true)
		
		withExtendedLifetime(ep1) {}
		
		var results2 = [Result<String>]()
		let (leftInput2, leftSignal2) = Signal<Int>.createInput { s in s.multicast() }
		let (rightInput2, rightSignal2) = Signal<Double>.createInput { s in s.multicast() }
		let ep2 = leftSignal2.join(withRight: rightSignal2, leftEnd: { v in leftSignal2 }, rightEnd: { v in rightSignal2 }) { (l, r) in return "\(l) \(r)" }.subscribe {
			results2.append($0)
		}
		leftInput2.send(value: 0)
		rightInput2.send(value: 1.1)
		leftInput2.send(value: 8)
		leftInput2.send(value: 9)
		rightInput2.send(value: 2.2)
		rightInput2.send(value: 3.3)
		leftInput2.send(value: 10)
		rightInput2.send(value: 4.4)
		XCTAssert(results2.count == 7)
		XCTAssert(results2.at(0)?.value == "0 1.1") // 1.1 projected onto 0
		XCTAssert(results2.at(1)?.value == "8 1.1") // 8 projected onto 1.1
		XCTAssert(results2.at(2)?.value == "9 1.1") // 9 projected onto 1.1
		XCTAssert(results2.at(3)?.value == "9 2.2") // 2.2 projected onto 9
		XCTAssert(results2.at(4)?.value == "9 3.3") // 3.3 projected onto 9
		XCTAssert(results2.at(5)?.value == "10 3.3") // 10 projected onto 3.3
		XCTAssert(results2.at(6)?.value == "10 4.4") // 4.4 projected onto 10
		
		withExtendedLifetime(ep2) {}
		
		var results3 = [Result<String>]()
		let (leftInput3, leftSignal3) = Signal<Int>.createInput { s in s.multicast() }
		let (rightInput3, rightSignal3) = Signal<Double>.createInput { s in s.multicast() }
		let ep3 = leftSignal3.join(withRight: rightSignal3, leftEnd: { v in leftSignal3.skip(1) }, rightEnd: { v in rightSignal3.skip(1) }) { (l, r) in return "\(l) \(r)" }.subscribe {
			results3.append($0)
		}
		leftInput3.send(value: 0)
		rightInput3.send(value: 1.1)
		leftInput3.send(value: 8)
		leftInput3.send(value: 9)
		rightInput3.send(value: 2.2)
		rightInput3.send(value: 3.3)
		leftInput3.send(value: 10)
		rightInput3.send(value: 4.4)
		XCTAssert(results3.count == 11)
		XCTAssert(results3.at(0)?.value == "0 1.1") // 1.1 projected onto 0
		XCTAssert(results3.at(1)?.value == "8 1.1") // 8 projected onto 1.1
		XCTAssert(results3.at(2)?.value == "9 1.1") // 9 projected onto 1.1
		XCTAssert(results3.at(3)?.value == "8 2.2") // 2.2 projected onto 8
		XCTAssert(results3.at(4)?.value == "9 2.2") // 2.2 projected onto 9
		XCTAssert(results3.at(5)?.value == "8 3.3") // 3.3 projected onto 8
		XCTAssert(results3.at(6)?.value == "9 3.3") // 3.3 projected onto 9
		XCTAssert(results3.at(7)?.value == "10 2.2") // 10 projected onto 2.2
		XCTAssert(results3.at(8)?.value == "10 3.3") // 10 projected onto 3.3
		XCTAssert(results3.at(9)?.value == "9 4.4") // 4.4 projected onto 9
		XCTAssert(results3.at(10)?.value == "10 4.4") // 4.4 projected onto 10
		
		withExtendedLifetime(ep3) {}
	}
	
	func testGroupJoin() {
		var results1 = [Result<String>]()
		let (leftInput1, leftSignal1) = Signal<Int>.createInput()
		let (rightInput1, rightSignal1) = Signal<Double>.createInput()
		let ep1 = leftSignal1.groupJoin(withRight: rightSignal1, leftEnd: { v -> Signal<()> in Signal<()>.preclosed() }, rightEnd: { v in Signal<()>.preclosed() }) { (l, r) in r.map { "\(l) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v): v.subscribeValues { results1.append(Result<String>.success($0)) }.keepAlive()
			case .failure(let e): results1.append(Result<String>.failure(e))
			}
		}
		leftInput1.send(value: 0)
		rightInput1.send(value: 1.1)
		leftInput1.send(value: 8)
		leftInput1.send(value: 9)
		rightInput1.send(value: 2.2)
		rightInput1.send(value: 3.3)
		leftInput1.send(value: 10)
		rightInput1.send(value: 4.4)
		leftInput1.close()
		XCTAssert(results1.count == 1)
		XCTAssert(results1.first?.isSignalClosed == true)
		
		withExtendedLifetime(ep1) {}
		
		var results2 = [Result<String>]()
		let (leftInput2, leftSignal2) = Signal<Int>.createInput { s in s.multicast() }
		let (rightInput2, rightSignal2) = Signal<Double>.createInput { s in s.multicast() }
		let ep2 = leftSignal2.groupJoin(withRight: rightSignal2, leftEnd: { v in leftSignal2 }, rightEnd: { v in rightSignal2 }) { (l, r) in r.map { "\(l) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v):
				v.subscribeValues {
					results2.append(Result<String>.success($0))
				}.keepAlive()
			case .failure(let e):
				results2.append(Result<String>.failure(e))
			}
		}
		leftInput2.send(value: 0)
		rightInput2.send(value: 1.1)
		leftInput2.send(value: 8)
		leftInput2.send(value: 9)
		rightInput2.send(value: 2.2)
		rightInput2.send(value: 3.3)
		leftInput2.send(value: 10)
		rightInput2.send(value: 4.4)
		XCTAssert(results2.count == 7)
		XCTAssert(results2.at(0)?.value == "0 1.1") // 1.1 projected onto 0
		XCTAssert(results2.at(1)?.value == "8 1.1") // 8 projected onto 1.1
		XCTAssert(results2.at(2)?.value == "9 1.1") // 9 projected onto 1.1
		XCTAssert(results2.at(3)?.value == "9 2.2") // 2.2 projected onto 9
		XCTAssert(results2.at(4)?.value == "9 3.3") // 3.3 projected onto 9
		XCTAssert(results2.at(5)?.value == "10 3.3") // 10 projected onto 3.3
		XCTAssert(results2.at(6)?.value == "10 4.4") // 4.4 projected onto 10
		
		withExtendedLifetime(ep2) {}
		
		var results3 = [Result<String>]()
		let (leftInput3, leftSignal3) = Signal<Int>.createInput { s in s.multicast() }
		let (rightInput3, rightSignal3) = Signal<Double>.createInput { s in s.multicast() }
		let ep3 = leftSignal3.groupJoin(withRight: rightSignal3, leftEnd: { v in leftSignal3.skip(1) }, rightEnd: { v in rightSignal3.skip(1) }) { (l, r) in r.map { "\(l) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v): v.subscribeValues { results3.append(Result<String>.success($0)) }.keepAlive()
			case .failure(let e): results3.append(Result<String>.failure(e))
			}
		}
		leftInput3.send(value: 0)
		rightInput3.send(value: 1.1)
		leftInput3.send(value: 8)
		leftInput3.send(value: 9)
		rightInput3.send(value: 2.2)
		rightInput3.send(value: 3.3)
		leftInput3.send(value: 10)
		rightInput3.send(value: 4.4)
		XCTAssert(results3.count == 11)
		XCTAssert(results3.at(0)?.value == "0 1.1") // 1.1 projected onto 0
		XCTAssert(results3.at(1)?.value == "8 1.1") // 8 projected onto 1.1
		XCTAssert(results3.at(2)?.value == "9 1.1") // 9 projected onto 1.1
		XCTAssert(results3.at(3)?.value == "8 2.2") // 2.2 projected onto 8
		XCTAssert(results3.at(4)?.value == "9 2.2") // 2.2 projected onto 9
		XCTAssert(results3.at(5)?.value == "8 3.3") // 3.3 projected onto 8
		XCTAssert(results3.at(6)?.value == "9 3.3") // 3.3 projected onto 9
		XCTAssert(results3.at(7)?.value == "10 2.2") // 10 projected onto 2.2
		XCTAssert(results3.at(8)?.value == "10 3.3") // 10 projected onto 3.3
		XCTAssert(results3.at(9)?.value == "9 4.4") // 4.4 projected onto 9
		XCTAssert(results3.at(10)?.value == "10 4.4") // 4.4 projected onto 10
		
		withExtendedLifetime(ep3) {}
	}
	
	func testMerge() {
		let merge2 = Signal<Int>.merge([Signal<Int>.fromSequence(0..<10), Signal<Int>.fromSequence(10..<20)])
		var results2 = [Result<Int>]()
		_ = merge2.subscribe { (r: Result<Int>) in
			results2.append(r)
		}
		XCTAssert(results2.count == 21)
		for i in 0..<20 {
			XCTAssert(results2.at(i)?.value == i)
		}
		XCTAssert(results2.at(20)?.error as? SignalError == .cancelled)
	}
	
	func testStartWith() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(10..<20).startWith(0..<10).subscribe { (r: Result<Int>) in
			results.append(r)
		}
		XCTAssert(results.count == 21)
		for i in 0..<20 {
			XCTAssert(results.at(i)?.value == i)
		}
		XCTAssert(results.at(20)?.isSignalClosed == true)
	}
	
	func testEndWith() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(0..<10).endWith(10..<20).subscribe { (r: Result<Int>) in
			results.append(r)
		}
		XCTAssert(results.count == 21)
		for i in 0..<20 {
			XCTAssert(results.at(i)?.value == i)
		}
		XCTAssert(results.at(20)?.isSignalClosed == true)
	}
	
	func testSwitchLatest() {
		var results = [Result<Int>]()
		let (input, signal) = Signal<Signal<Int>>.createInput()
		let ep = switchLatestSignal(signal).subscribe { (r: Result<Int>) in
			results.append(r)
		}
		let (input1, child1) = Signal<Int>.createInput()
		let (input2, child2) = Signal<Int>.createInput()
		let (input3, child3) = Signal<Int>.createInput()
		let (input4, child4) = Signal<Int>.createInput()
		input.send(value: child1)
		input1.send(value: 0)
		input1.send(value: 1)
		input.send(value: child2)
		input1.send(value: 2)
		input1.send(value: 3)
		input2.send(value: 10)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.close()
		input1.send(value: 4)
		input1.send(value: 5)
		input.send(value: child3)
		input3.close()
		input1.send(value: 6)
		input1.send(value: 7)
		input.send(value: child4)
		input4.send(value: 30)
		input4.send(value: 31)
		input4.send(value: 32)
		input1.send(value: 8)
		input1.send(value: 9)
		input.close()
		
		XCTAssert(results.count == 9)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(results.at(3)?.value == 11)
		XCTAssert(results.at(4)?.value == 12)
		XCTAssert(results.at(5)?.value == 30)
		XCTAssert(results.at(6)?.value == 31)
		XCTAssert(results.at(7)?.value == 32)
		XCTAssert(results.at(8)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testZip() {
		var results = [Result<(Int, Int)>]()
		let (input1, signal1) = Signal<Int>.createInput()
		let (input2, signal2) = Signal<Int>.createInput()
		let ep = signal1.zip(second: signal2).subscribe { (r: Result<(Int, Int)>) in
			results.append(r)
		}
		input1.send(value: 0)
		input1.send(value: 1)
		input1.send(value: 2)
		input2.send(value: 10)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.send(value: 13)
		input2.send(value: 14)
		input2.send(value: 15)
		input1.send(value: 3)
		input1.close()
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.0 == 0 && results.at(0)?.value?.1 == 10)
		XCTAssert(results.at(1)?.value?.0 == 1 && results.at(1)?.value?.1 == 11)
		XCTAssert(results.at(2)?.value?.0 == 2 && results.at(2)?.value?.1 == 12)
		XCTAssert(results.at(3)?.value?.0 == 3 && results.at(3)?.value?.1 == 13)
		XCTAssert(results.at(4)?.isSignalClosed == true)
		
		withExtendedLifetime(ep) {}
	}
	
	func testCatch() {
		var results1 = [Result<Int>]()
		let signal1 = Signal<Int>.fromSequence(0..<10)
		let signal2 = Signal<Int>.fromSequence(10..<20)
		_ = signal1.catchError { e -> Signal<Int>? in
			if e as? SignalError == .closed {
				return signal2
			} else {
				return nil
			}
		}.subscribe { (r: Result<Int>) in
			results1.append(r)
		}
		XCTAssert(results1.count == 21)
		for i in 0..<20 {
			XCTAssert(results1.at(i)?.value == i)
		}
		XCTAssert(results1.at(20)?.error as? SignalError == .duplicate)
		
		var results2 = [Result<Int>]()
		let signal3 = Signal<Int>.fromSequence(0..<10)
		_ = signal3.catchError { e in (10..<20, SignalError.closed) }.subscribe { (r: Result<Int>) in
			results2.append(r)
		}
		XCTAssert(results2.count == 21)
		for i in 0..<20 {
			XCTAssert(results2.at(i)?.value == i)
		}
		XCTAssert(results2.at(20)?.isSignalClosed == true)
	}
	
	func testRetry() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		var count = 0
		let ep = Signal<Int>.generate { input in
			guard let i = input else { return }
			if count == 0 {
				count += 1
				for j in 0..<5 {
					i.send(value: j)
				}
				i.send(error: TestError.zeroValue)
			} else {
				for j in 0..<5 {
					i.send(value: j)
				}
				i.send(error: SignalError.closed)
			}
		}.retry(count: 1, delaySeconds: 0.1, context: coordinator.direct).subscribe { (r: Result<Int>) in
			results.append(r)
		}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 4)
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}

		XCTAssert(coordinator.currentTime == 100_000_000)
		
		XCTAssert(results.count == 11)
		XCTAssert(results.at(5)?.value == 0)
		XCTAssert(results.at(6)?.value == 1)
		XCTAssert(results.at(7)?.value == 2)
		XCTAssert(results.at(8)?.value == 3)
		XCTAssert(results.at(9)?.value == 4)
		XCTAssert(results.at(10)?.isSignalClosed == true)
	}
	
	func testDelay() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		var times = [UInt64]()
		let ep = Signal<Int>.fromSequence(0..<5).delay(withState: 5, context: coordinator.direct) { (offset: inout Int, v: Int) -> Double in
			return Double(offset - v) * 0.05
		}.subscribe { (r: Result<Int>) in
			results.append(r)
			times.append(coordinator.currentTime)
		}
		
		coordinator.runScheduledTasks()
		
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 4)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.isSignalClosed == true)
		XCTAssert(times.at(0).map { (v: UInt64) -> Bool in v == 50_000_000 } == true)
		XCTAssert(times.at(1).map { (v: UInt64) -> Bool in v == 100_000_000 } == true)
		XCTAssert(times.at(2).map { (v: UInt64) -> Bool in v == 150_000_000 } == true)
		XCTAssert(times.at(3).map { (v: UInt64) -> Bool in v == 200_000_000 } == true)
		XCTAssert(times.at(4).map { (v: UInt64) -> Bool in v == 250_000_000 } == true)
		XCTAssert(times.at(5).map { (v: UInt64) -> Bool in v == 250_000_000 } == true)
	}
	
	func testDelaySignal() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		var times = [UInt64]()
		let ep = Signal<Int>.fromSequence(0..<5).delay(context: coordinator.direct) { (v: Int) -> Signal<()> in
			return timerSignal(seconds: Double(6 - v) * 0.05, context: coordinator.default)
		}.subscribe { (r: Result<Int>) in
			results.append(r)
			times.append(coordinator.currentTime)
		}

		coordinator.runScheduledTasks()
		
		withExtendedLifetime(ep) {}

		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 4)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.isSignalClosed == true)

		XCTAssert(times.at(0).map { (v: UInt64) -> Bool in v == 100_000_000 } == true)
		XCTAssert(times.at(1).map { (v: UInt64) -> Bool in v == 150_000_000 } == true)
		XCTAssert(times.at(2).map { (v: UInt64) -> Bool in v == 200_000_000 } == true)
		XCTAssert(times.at(3).map { (v: UInt64) -> Bool in v == 250_000_000 } == true)
		XCTAssert(times.at(4).map { (v: UInt64) -> Bool in v == 300_000_000 } == true)
		XCTAssert(times.at(5).map { (v: UInt64) -> Bool in v == 300_000_000 } == true)
	}
	
	func testOn() {
		var results = [String]()
		_ = Signal<Int>.fromSequence(0..<5).onActivate {
			results.append("activate")
		}.onDeactivate {
			results.append("deactivate")
		}.onValue { v in
			results.append("\(v)")
		}.onError { e in
			results.append("\(e)")
		}.subscribe { r in
			results.append("\(r)")
		}
		
		XCTAssert(results == [
			"activate",
			"0",
			"success(0)",
			"1",
			"success(1)",
			"2",
			"success(2)",
			"3",
			"success(3)",
			"4",
			"success(4)",
			"closed",
			"failure(CwlUtils.SignalError.closed)",
			"deactivate",
		])
	}
	
	func testTimeInterval() {
		var results = [Result<Double>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		let ep = signal.timeInterval(context: coordinator.direct).subscribe { (r: Result<Double>) in
			results.append(r)
		}

		var delayedInputs = [Cancellable]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(350)) {
			input.close()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}

		let compare: (Double, Double) -> (Double) -> Bool = { (right: Double, epsilon: Double) -> (Double) -> Bool in
			return { (left: Double) -> Bool in left - epsilon < right && left + epsilon > right }
		}
		
		XCTAssert(results.count == 6)
		XCTAssert((results.at(0)?.value).map(compare(0.02, 1e-6)) == true)
		XCTAssert((results.at(1)?.value).map(compare(0.06, 1e-6)) == true)
		XCTAssert((results.at(2)?.value).map(compare(0.07, 1e-6)) == true)
		XCTAssert((results.at(3)?.value).map(compare(0.10, 1e-6)) == true)
		XCTAssert((results.at(4)?.value).map(compare(0.05, 1e-6)) == true)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testTimeout() {
		var results = [Result<Int>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		let ep = signal.timeout(seconds: 0.09, context: coordinator.direct).subscribe { (r: Result<Int>) in
			results.append(r)
		}

		var delayedInputs = [Cancellable]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(350)) {
			input.close()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}

		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)

		switch results.at(3)?.error as? SignalReactiveError {
		case .some(.timeout): break
		default: XCTFail()
		}
	}
	
	func testTimestamp() {
		var results = [Result<(Int, DispatchTime)>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.createInput()
		let ep = signal.timestamp(context: coordinator.direct).subscribe { (r: Result<(Int, DispatchTime)>) in
			results.append(r)
		}
		
		var delayedInputs = [Cancellable]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.default.singleTimer(interval: .milliseconds(350)) {
			input.close()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(ep) {}

		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value?.1.uptimeNanoseconds == 20_000_000)
		XCTAssert(results.at(1)?.value?.1.uptimeNanoseconds == 80_000_000)
		XCTAssert(results.at(2)?.value?.1.uptimeNanoseconds == 150_000_000)
		XCTAssert(results.at(3)?.value?.1.uptimeNanoseconds == 250_000_000)
		XCTAssert(results.at(4)?.value?.1.uptimeNanoseconds == 300_000_000)
		XCTAssert(results.at(5)?.isSignalClosed == true)
	}
	
	func testAll() {
		var results = [Result<Bool>]()
		_ = Signal<Int>.fromSequence(1...10).all { (v: Int) -> Bool in v % 3 == 0 }.subscribe { (r: Result<Bool>) in
			results.append(r)
		}
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == false)
		XCTAssert(results.at(1)?.isSignalClosed == true)

		_ = Signal<Int>.fromSequence(1...10).all { (v: Int) -> Bool in v > 0 }.subscribe { (r: Result<Bool>) in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(2)?.value == true)
		XCTAssert(results.at(3)?.isSignalClosed == true)
	}
	
	func testAmb() {
		var results = [Result<Int>]()
		let (input1, signal1) = Signal<Int>.createInput()
		let (input2, signal2) = Signal<Int>.createInput()
		let (input3, signal3) = Signal<Int>.createInput()
		let ep = Signal<Int>.amb(inputs: [signal1, signal2, signal3]).subscribe { (r: Result<Int>) in
			results.append(r)
		}
		input2.send(value: 0)
		input1.send(value: 1)
		input3.send(value: 2)
		input2.send(value: 3)
		input1.send(value: 4)
		input1.send(value: 5)
		input1.close()
		input2.send(value: 6)
		input2.close()
		input3.send(value: 7)
		input3.send(value: 8)
		input3.close()

		withExtendedLifetime(ep) {}

		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 6)
		XCTAssert(results.at(3)?.isSignalClosed == true)
	}
	
	func testSome() {
		var results2 = [Result<Bool>]()
		_ = Signal<Int>.fromSequence(1...10).some { $0 == 5 }.subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error as? SignalError == .closed)

		var results1 = [Result<Bool>]()
		_ = Signal<Int>.fromSequence(1...10).some { $0 == 15 }.subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error as? SignalError == .closed)
	}
	
	func testContains() {
		var results2 = [Result<Bool>]()
		_ = Signal<Int>.fromSequence(1...10).contains(value: 5).subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error as? SignalError == .closed)

		var results1 = [Result<Bool>]()
		_ = Signal<Int>.fromSequence(1...10).contains(value: 15).subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error as? SignalError == .closed)
	}
	
	func testDefaultIfEmpty() {
		var results1 = [Result<Int>]()
		_ = Signal<Int>.fromSequence(1...3).defaultIfEmpty(value: 5).subscribe { results1.append($0) }
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 2)
		XCTAssert(results1.at(2)?.value == 3)
		XCTAssert(results1.at(3)?.error as? SignalError == .closed)

		var results2 = [Result<Int>]()
		_ = Signal<Int>.fromSequence(0..<0).defaultIfEmpty(value: 5).subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.error as? SignalError == .closed)
	}
	
	func testSwitchIfEmpty() {
		var results1 = [Result<Int>]()
		let alternate1 = Signal<Int>.fromSequence(11...13)
		_ = Signal<Int>.fromSequence(1...3).switchIfEmpty(alternate: alternate1).subscribe { results1.append($0) }
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 2)
		XCTAssert(results1.at(2)?.value == 3)
		XCTAssert(results1.at(3)?.error as? SignalError == .closed)

		var results2 = [Result<Int>]()
		let alternate2 = Signal<Int>.fromSequence(11...13)
		_ = Signal<Int>.fromSequence(0..<0).switchIfEmpty(alternate: alternate2).subscribe { results2.append($0) }
		XCTAssert(results2.count == 4)
		XCTAssert(results2.at(0)?.value == 11)
		XCTAssert(results2.at(1)?.value == 12)
		XCTAssert(results2.at(2)?.value == 13)
		XCTAssert(results2.at(3)?.error as? SignalError == .closed)
	}
	
	func testSequenceEqual() {
		var results1 = [Result<Bool>]()
		let alternate1 = Signal<Int>.fromSequence(11...13)
		_ = Signal<Int>.fromSequence(11...14).sequenceEqual(to: alternate1).subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error as? SignalError == .closed)

		var results2 = [Result<Bool>]()
		let alternate2 = Signal<Int>.fromSequence(11...13)
		_ = Signal<Int>.fromSequence(11...13).sequenceEqual(to: alternate2).subscribe { r in
			results2.append(r)
		}
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error as? SignalError == .closed)
	}
	
	func testSkipUntil() {
		var results = [Result<Int>]()
		let (otherInput, otherSignal) = Signal<()>.createInput()
		let (input, ep) = Signal<Int>.createInput { s in s.skipUntil(otherSignal).subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		otherInput.send(value: ())
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.close()
		
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
	}
	
	func testSkipWhile() {
		var results = [Result<Int>]()
		let (input, ep) = Signal<Int>.createInput { s in s.skipWhile { v in v != 3 }.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.close()
		
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
	}
	
	func testTakeUntil() {
		var results = [Result<Int>]()
		let (otherInput, otherSignal) = Signal<()>.createInput()
		let (input, ep) = Signal<Int>.createInput { s in s.takeUntil(otherSignal).subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		otherInput.send(value: ())
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.close()
		
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
	}
	
	func testTakeWhile() {
		var results = [Result<Int>]()
		let (input, ep) = Signal<Int>.createInput { s in s.takeWhile { v in v != 3 }.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.close()
		
		withExtendedLifetime(ep) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error as? SignalError == .closed)
	}
	
	func testConcat() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(1...3).concat(Signal<Int>.fromSequence(4...6)).subscribe { r in results.append(r) }
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 2)
		XCTAssert(results.at(2)?.value == 3)
		XCTAssert(results.at(3)?.value == 4)
		XCTAssert(results.at(4)?.value == 5)
		XCTAssert(results.at(5)?.value == 6)
		XCTAssert(results.at(6)?.error as? SignalError == .closed)
	}
	
	func testCount() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(4...8).count().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)
	}
	
	func testMin() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(1...3).min().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)
	}
	
	func testMax() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(2...5).max().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)
	}
	
	func testReduce() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(1...3).reduce(5) { (state, v) in state + v }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 11)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)
	}
	
	func testSum() {
		var results = [Result<Int>]()
		_ = Signal<Int>.fromSequence(1...3).sum().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 6)
		XCTAssert(results.at(1)?.error as? SignalError == .closed)
	}
}
