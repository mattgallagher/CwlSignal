//
//  CwlSignalReactiveTests.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2016/09/08.
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

import CwlSignal
import CwlUtils
import Foundation
import XCTest

private enum TestError: Error {
	case zeroValue
	case oneValue
	case twoValue
}

class SignalReactiveTests: XCTestCase {
	func testNever() {
		var results = [Result<Int, SignalEnd>]()
		let out = Signal.never().subscribe { r in
			results.append(r)
		}
		XCTAssert(results.isEmpty)
		XCTAssert(out.isClosed == false)
		out.cancel()
		XCTAssert(results.isEmpty)
		XCTAssert(out.isClosed == true)
	}
	
	func testFrom() {
		var results = [Result<Int, SignalEnd>]()
		let capture = Signal<Int>.just(1, 3, 5, 7, 11).capture()
		let (input, signal) = Signal<Int>.create()
		let out = signal.subscribe { r in results.append(r) }
		let (values, error) = (capture.values, capture.end)
		do {
			try capture.bind(to: input)
		} catch {
			input.send(end: .other(error))
		}
		withExtendedLifetime(out) {}
		XCTAssert(values.isEmpty)
		XCTAssert(error == nil)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 7)
		XCTAssert(results.at(4)?.value == 11)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testToSequence() {
		let signal = Signal<Int>.just(1, 3, 5, 7, 11)
		let results = Array<Int>(signal.toSequence())
		XCTAssert(results == [1, 3, 5, 7, 11])

		let (input, signal2) = Signal<Int>.create()
		let sequence = signal2.toSequence()
		input.send(value: 13)
		
		XCTAssert(sequence.next() == 13)
		XCTAssert(sequence.end == nil)

		sequence.cancel()
		XCTAssert(sequence.next() == nil)
		XCTAssert(sequence.end?.isCancelled == true)
	}
	
	func testInterval() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let out = Signal.interval(.interval(0.01), context: coordinator.direct).subscribe { r in
			results.append(r)
			if let v = r.value, v == 3 {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.error?.isCancelled == true)
		XCTAssert(coordinator.currentTime == 40_000_000)
	}
	
	func testRepeatCollection() {
		var results = [Result<Int, SignalEnd>]()
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
		XCTAssert(results.at(15)?.error?.isComplete == true)
	}
	
	func testStart() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.start() { 5 }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testTimer() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let out = Signal<Int>.timer(interval: .interval(0.005), value: 5, context: coordinator.direct).subscribe { r in
			results.append(r)
		}
		let ep2 = Signal<Int>.timer(interval: .interval(0.01), context: coordinator.direct).subscribe { r in
			results.append(r)
		}
		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}
		withExtendedLifetime(ep2) {}
		
		XCTAssert(coordinator.currentTime == 10_000_000)
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error?.isComplete == true)
		XCTAssert(results.at(2)?.error?.isComplete == true)
	}
	
	func testBufferCount() {
		do {
			var results = [Result<[Int], SignalEnd>]()
			let signal = Signal<Int>.from(1...10)
			_ = signal.buffer(count: 3, skip: 2).subscribe {
				results.append($0)
			}
			XCTAssert(results.count == 6)
			XCTAssert(results.at(0)?.value.map { (v: [Int]) -> Bool in v == [1, 2, 3] } == true)
			XCTAssert(results.at(1)?.value.map { (v: [Int]) -> Bool in v == [3, 4, 5] } == true)
			XCTAssert(results.at(2)?.value.map { (v: [Int]) -> Bool in v == [5, 6, 7] } == true)
			XCTAssert(results.at(3)?.value.map { (v: [Int]) -> Bool in v == [7, 8, 9] } == true)
			XCTAssert(results.at(4)?.value.map { (v: [Int]) -> Bool in v == [9, 10] } == true)
			XCTAssert(results.at(5)?.error?.isComplete == true)
		}

		do {
			var results = [Result<[Int], SignalEnd>]()
			let signal = Signal<Int>.from(1...10)
			_ = signal.buffer(count: 3).subscribe {
				results.append($0)
			}
			XCTAssert(results.count == 5)
			XCTAssert(results.at(0)?.value.map { (v: [Int]) -> Bool in v == [1, 2, 3] } == true)
			XCTAssert(results.at(1)?.value.map { (v: [Int]) -> Bool in v == [4, 5, 6] } == true)
			XCTAssert(results.at(2)?.value.map { (v: [Int]) -> Bool in v == [7, 8, 9] } == true)
			XCTAssert(results.at(3)?.value.map { (v: [Int]) -> Bool in v == [10] } == true)
			XCTAssert(results.at(4)?.error?.isComplete == true)
		}
	}
	
	func testBufferSeconds() {
		var results = [Result<[Int], SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.buffer(interval: .interval(0.02), count: 3, context: coordinator.direct).subscribe { r in
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
		withExtendedLifetime(out) { }
	}
	
	func testBufferTimespan() {
		var results = [Result<[Int], SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.buffer(interval: .interval(2), timeshift: .interval(5), context: coordinator.direct).subscribe { r in
			results.append(r)
			if results.count == 3 {
				coordinator.stop()
			}
		}
		XCTAssert(results.isEmpty)
		
		var delays = [Lifetime]()
		for i in 1...20 {
			delays += coordinator.direct.singleTimer(interval: .interval(0.45 * Double(i))) {
				input.send(value: i)
				if i == 20 {
					input.complete()
				}
			}
		}

		coordinator.runScheduledTasks()

		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value.map { (v: [Int]) -> Bool in v == [1, 2, 3, 4] } == true)
		XCTAssert(results.at(1)?.value.map { (v: [Int]) -> Bool in v == [12, 13, 14, 15] } == true)
		XCTAssert(results.at(2)?.error?.isComplete == true)


		XCTAssert(coordinator.currentTime == 9_000_000_000)
		
		withExtendedLifetime(input) { }
		withExtendedLifetime(out) { }
	}
	
	func testFlatMap() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(1, 3, 5, 7, 11).flatMap { v in
			return Signal<Int>.generate(context: .direct) { input in
				guard let i = input else { return }
				for w in 0...v {
					if let _ = i.send(result: .success(w)) {
						break
					}
				}
				i.complete()
			}
		}.subscribe { r in results.append(r) }
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
		XCTAssert(results.at(32)?.error?.isComplete == true)
	}

	func testFlatMapOuterError() {
		var results1 = [Result<Int, SignalEnd>]()
		let (i1, s1) = Signal<Int>.create()
		let (i2, s2) = Signal<Int>.create()
		let (i3, ep1) = Signal<Signal<Int>>.create { $0.flatMap { $0 }.subscribe { results1.append($0) } }
		i3.send(value: s1)
		i1.send(value: 0)
		i1.send(value: 1)
		i3.send(value: s2)
		i2.send(value: 2)
		i2.send(value: 3)
		i1.send(value: 4)
		i1.send(value: 5)
		i1.complete()
		i2.send(value: 6)
		i3.send(end: .other(TestError.twoValue))
		i2.send(value: 7)
		i2.complete()
		
		XCTAssert(results1.count == 8)
		XCTAssert(results1.at(0)?.value == 0)
		XCTAssert(results1.at(1)?.value == 1)
		XCTAssert(results1.at(2)?.value == 2)
		XCTAssert(results1.at(3)?.value == 3)
		XCTAssert(results1.at(4)?.value == 4)
		XCTAssert(results1.at(5)?.value == 5)
		XCTAssert(results1.at(6)?.value == 6)
		XCTAssert(results1.at(7)?.error?.otherError as? TestError == .twoValue)
		
		ep1.cancel()
	}

	func testFlatMapInnerClosing() {
		var results1 = [Result<Int, SignalEnd>]()
		let (i1, s1) = Signal<Int>.create()
		let (i2, s2) = Signal<Int>.create()
		let (i3, ep1) = Signal<Signal<Int>>.create { $0.flatMap { $0 }.subscribe { results1.append($0) } }
		i3.send(value: s1)
		i1.send(value: 0)
		i1.send(value: 1)
		i3.send(value: s2)
		i2.send(value: 2)
		i2.send(value: 3)
		i1.send(value: 4)
		i1.send(value: 5)
		i1.complete()
		i2.send(value: 6)
		i3.complete()
		i2.send(value: 7)
		i2.complete()
		
		XCTAssert(results1.count == 9)
		XCTAssert(results1.at(0)?.value == 0)
		XCTAssert(results1.at(1)?.value == 1)
		XCTAssert(results1.at(2)?.value == 2)
		XCTAssert(results1.at(3)?.value == 3)
		XCTAssert(results1.at(4)?.value == 4)
		XCTAssert(results1.at(5)?.value == 5)
		XCTAssert(results1.at(6)?.value == 6)
		XCTAssert(results1.at(7)?.value == 7)
		XCTAssert(results1.at(8)?.error?.isComplete == true)
		
		ep1.cancel()
	}

	func testFlatMapInnerErrors() {
		var results2 = [Result<Int, SignalEnd>]()
		let (i4, s4) = Signal<Int>.create()
		let (i5, s5) = Signal<Int>.create()
		let (i6, ep2) = Signal<Signal<Int>>.create { $0.flatMap { $0 }.subscribe { results2.append($0) } }
		i6.send(value: s4)
		i4.send(value: 0)
		i4.send(value: 1)
		i6.send(value: s5)
		i5.send(value: 2)
		i5.send(value: 3)
		i4.send(value: 4)
		i4.send(value: 5)
		i4.send(error: TestError.zeroValue)
		i5.send(value: 6)
		i5.send(value: 7)
		i6.send(error: TestError.oneValue)
		
		XCTAssert(results2.count == 7)
		XCTAssert(results2.at(0)?.value == 0)
		XCTAssert(results2.at(1)?.value == 1)
		XCTAssert(results2.at(2)?.value == 2)
		XCTAssert(results2.at(3)?.value == 3)
		XCTAssert(results2.at(4)?.value == 4)
		XCTAssert(results2.at(5)?.value == 5)
		XCTAssert(results2.at(6)?.error?.otherError as? TestError == .zeroValue)
		
		ep2.cancel()
	}
	
	func testFlatMapWithState() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(1, 3, 5, 7, 11).flatMap(initialState: 0) { (state: inout Int, v: Int) -> Signal<Int> in
			state += 1
			return Signal<Int>.generate(context: .direct) { [state] input in
				guard let i = input else { return }
				for w in 0...v {
					if let _ = i.send(result: .success(w + state - 1)) {
						break
					}
				}
				i.complete()
			}
		}.subscribe { r -> () in
			results.append(r)
		}
		XCTAssert(results.count == 33)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 1)
		XCTAssert(results.at(3)?.value == 2)
		XCTAssert(results.at(4)?.value == 3)
		XCTAssert(results.at(5)?.value == 4)
		XCTAssert(results.at(6)?.value == 2)
		XCTAssert(results.at(7)?.value == 3)
		XCTAssert(results.at(8)?.value == 4)
		XCTAssert(results.at(9)?.value == 5)
		XCTAssert(results.at(10)?.value == 6)
		XCTAssert(results.at(11)?.value == 7)
		XCTAssert(results.at(12)?.value == 3)
		XCTAssert(results.at(13)?.value == 4)
		XCTAssert(results.at(14)?.value == 5)
		XCTAssert(results.at(15)?.value == 6)
		XCTAssert(results.at(16)?.value == 7)
		XCTAssert(results.at(17)?.value == 8)
		XCTAssert(results.at(18)?.value == 9)
		XCTAssert(results.at(19)?.value == 10)
		XCTAssert(results.at(20)?.value == 4)
		XCTAssert(results.at(21)?.value == 5)
		XCTAssert(results.at(22)?.value == 6)
		XCTAssert(results.at(23)?.value == 7)
		XCTAssert(results.at(24)?.value == 8)
		XCTAssert(results.at(25)?.value == 9)
		XCTAssert(results.at(26)?.value == 10)
		XCTAssert(results.at(27)?.value == 11)
		XCTAssert(results.at(28)?.value == 12)
		XCTAssert(results.at(29)?.value == 13)
		XCTAssert(results.at(30)?.value == 14)
		XCTAssert(results.at(31)?.value == 15)
		XCTAssert(results.at(32)?.error?.isComplete == true)
	}
	
	func testFlatMapFirst() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(3, 5, 7, 11).flatMapFirst { v in
			return Signal<Int>.generate(context: .direct) { input in
				guard let i = input else { return }
				for w in v..<(v * 2) {
					if let _ = i.send(result: .success(w)) {
						break
					}
				}
				i.complete()
			}
		}.subscribe { r in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testFlatMapLatest() {
		var results = [Result<Int, SignalEnd>]()
		let signals = [Signal<Int>.create(), Signal<Int>.create(), Signal<Int>.create()]
		let wrapper = Signal<Int>.create()
		let output = wrapper.signal.flatMapLatest { v in signals[v].signal }.subscribe { r in
			results.append(r)
		}
		
		wrapper.input.send(0)
		signals[0].input.send(0, 1, 2)
		wrapper.input.send(1)
		signals[0].input.send(3, 4, 5)
		signals[1].input.send(6, 7, 8)
		wrapper.input.send(2)
		signals[0].input.send(9, 10, 11)
		signals[1].input.send(12, 13, 14)
		signals[2].input.send(15, 16, 17)
		wrapper.input.complete()
		signals.forEach { $0.input.complete() }
		
		XCTAssert(results.count == 10)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 6)
		XCTAssert(results.at(4)?.value == 7)
		XCTAssert(results.at(5)?.value == 8)
		XCTAssert(results.at(6)?.value == 15)
		XCTAssert(results.at(7)?.value == 16)
		XCTAssert(results.at(8)?.value == 17)
		XCTAssert(results.at(9)?.error?.isComplete == true)
		
		withExtendedLifetime(output) {}
	}
	
	func testConcatMap() {
		var results = [Result<String, SignalEnd>]()
		let inputOutputPairs = (0..<4).map { i in Signal<String>.create() }
		let (input, out) = Signal<Int>.create { r in
			r.concatMap { v in inputOutputPairs[v].1 }.subscribe { r in
				results.append(r)
			}
		}

		input.send(value: 0)
		inputOutputPairs[0].0.send(value: "a")
		inputOutputPairs[0].0.send(value: "b")

		XCTAssert(results.at(0)?.value == "a")
		XCTAssert(results.at(1)?.value == "b")

		input.send(value: 1)
		inputOutputPairs[0].0.send(value: "c")
		inputOutputPairs[1].0.send(value: "d")

		XCTAssert(results.at(2)?.value == "c")
		XCTAssert(results.count == 3)

		input.send(value: 2)
		inputOutputPairs[2].0.send(value: "e")
		inputOutputPairs[0].0.send(value: "f")
		inputOutputPairs[1].0.send(value: "g")

		XCTAssert(results.at(3)?.value == "f")
		XCTAssert(results.count == 4)

		inputOutputPairs[1].0.complete()

		XCTAssert(results.count == 4)

		input.send(value: 3)
		input.complete()

		XCTAssert(results.count == 4)
		
		inputOutputPairs[2].0.send(value: "h")
		inputOutputPairs[0].0.send(value: "i")
		inputOutputPairs[3].0.send(value: "j")

		XCTAssert(results.at(4)?.value == "i")
		XCTAssert(results.count == 5)

		inputOutputPairs[0].0.complete()

		XCTAssert(results.at(5)?.value == "d")
		XCTAssert(results.at(6)?.value == "g")
		XCTAssert(results.at(7)?.value == "e")
		XCTAssert(results.at(8)?.value == "h")
		XCTAssert(results.count == 9)
		
		inputOutputPairs[2].0.complete()

		inputOutputPairs[3].0.send(value: "k")
		inputOutputPairs[3].0.send(value: "l")
		inputOutputPairs[3].0.send(value: "m")
		inputOutputPairs[3].0.send(error: TestError.twoValue)

		XCTAssert(results.at(9)?.value == "j")
		XCTAssert(results.at(10)?.value == "k")
		XCTAssert(results.at(11)?.value == "l")
		XCTAssert(results.at(12)?.value == "m")
		XCTAssert(results.at(13)?.error?.otherError as? TestError == TestError.twoValue)

		withExtendedLifetime(out) { }
	}
	
	func testGroupBy() {
		var results = Dictionary<Int, Array<Result<Int, SignalEnd>>>()
		_ = Signal.from(1...20).groupBy { v in v % 3 }.subscribe { r in
			if let v = r.value {
				results[v.0] = Array<Result<Int, SignalEnd>>()
				v.1.subscribeUntilEnd { r in
					results[v.0]!.append(r)
				}
			} else {
				XCTAssert(r.isComplete)
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
		XCTAssert(r1?.at(6)?.error?.isComplete == true)
		XCTAssert(r2?.count == 8)
		XCTAssert(r2?.at(0)?.value == 1)
		XCTAssert(r2?.at(1)?.value == 4)
		XCTAssert(r2?.at(2)?.value == 7)
		XCTAssert(r2?.at(3)?.value == 10)
		XCTAssert(r2?.at(4)?.value == 13)
		XCTAssert(r2?.at(5)?.value == 16)
		XCTAssert(r2?.at(6)?.value == 19)
		XCTAssert(r2?.at(7)?.error?.isComplete == true)
		XCTAssert(r3?.count == 8)
		XCTAssert(r3?.at(0)?.value == 2)
		XCTAssert(r3?.at(1)?.value == 5)
		XCTAssert(r3?.at(2)?.value == 8)
		XCTAssert(r3?.at(3)?.value == 11)
		XCTAssert(r3?.at(4)?.value == 14)
		XCTAssert(r3?.at(5)?.value == 17)
		XCTAssert(r3?.at(6)?.value == 20)
		XCTAssert(r3?.at(7)?.error?.isComplete == true)
	}
	
	func testCompactOptionals() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int?>.just(1, nil, 2, nil).compact().subscribe { r in results.append(r) }
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 2)
		XCTAssert(results.at(2)?.error?.isComplete == true)
	}
	
	func testCompactMap() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.from(1...5).compactMap { v -> Int? in
			if v % 2 == 0 {
				return v * 2
			} else {
				return nil
			}
		}.subscribe { r in results.append(r) }
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == 4)
		XCTAssert(results.at(1)?.value == 8)
		XCTAssert(results.at(2)?.error?.isComplete == true)
	}

	func testMap() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.from(1...5).map { v in v * 2 }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 6)
		XCTAssert(results.at(3)?.value == 8)
		XCTAssert(results.at(4)?.value == 10)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testMapActivation() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let lifetime = signal.customActivation(initialValues: [1, 2]) { _, _, _ in }.mapActivation(select: .all,
			activation: { v in v * 10 },
			remainder: { $0 * 2 }
		).subscribe { r in results.append(r) }
		input.send(7, 8, 9)
		input.complete()
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 10)
		XCTAssert(results.at(1)?.value == 20)
		XCTAssert(results.at(2)?.value == 14)
		XCTAssert(results.at(3)?.value == 16)
		XCTAssert(results.at(4)?.value == 18)
		XCTAssert(results.at(5)?.error?.isComplete == true)
		withExtendedLifetime(lifetime) {}
	}
	
	func testMapActivationFirst() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let lifetime = signal
			.customActivation(initialValues: [1, 2]) { _, _, _ in }
			.mapActivation(
				select: .first,
				activation: { v in v * 10 },
				remainder: { $0 * 2 }
			).subscribe { r in results.append(r) }
		input.send(7, 8, 9)
		input.complete()
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 10)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 14)
		XCTAssert(results.at(3)?.value == 16)
		XCTAssert(results.at(4)?.value == 18)
		XCTAssert(results.at(5)?.error?.isComplete == true)
		withExtendedLifetime(lifetime) {}
	}
	
	func testCompactMapActivation() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let capture = signal
			.cacheUntilActive(precached: [1, 2])
			.compactMapActivation(
				select: .last,
				activation: { v in v * 10 },
				remainder: { v in v * 2 }
			)
			.capture()
		let captureValues = capture.values
		
		let lifetime = capture.resume(resend: .deferred)
			.subscribe { r in results.append(r) }
		input.send(7, 8, 9)
		input.complete()
		
		XCTAssert(captureValues.count == 1)
		XCTAssert(captureValues.at(0) == 20)
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 20)
		XCTAssert(results.at(1)?.value == 14)
		XCTAssert(results.at(2)?.value == 16)
		XCTAssert(results.at(3)?.value == 18)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		withExtendedLifetime(lifetime) {}
	}
	
	func testCompactMapLatestActivation() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let capture = signal
			.cacheUntilActive(precached: [1, 2])
			.compactMapActivation(select: .last) { v in v * 10 }
			.capture()
		let captureValues = capture.values
		
		let lifetime = capture.resume(resend: .deferred)
			.subscribe { r in results.append(r) }
		input.send(7, 8, 9)
		input.complete()
		
		XCTAssert(captureValues.count == 1)
		XCTAssert(captureValues.at(0) == 20)
		
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 20)
		XCTAssert(results.at(1)?.value == 7)
		XCTAssert(results.at(2)?.value == 8)
		XCTAssert(results.at(3)?.value == 9)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(lifetime) {}
	}
	
	func testCompactMapActivationReducer() {
		let (i, s) = Signal<Int>.create()
		let r = s
			.reduce(initialState: 8) { state, value in state + value }
			.compactMapActivation(select: .first, activation: { $0 * 2 }, remainder: { $0 * 3 })
		var values = [Int]()
		r.subscribeValuesUntilEnd { values += $0 }
		i.send(value: 5)
		XCTAssert(values.count == 2)
		XCTAssert(values.at(0) == 16)
		XCTAssert(values.at(1) == 39)
	}

	func testMapError() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.preclosed(1, 2, 3, end: .cancelled).mapErrors { _ in .complete }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 2)
		XCTAssert(results.at(2)?.value == 3)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testKeyPath() {
		var results = [Result<String, SignalEnd>]()
		_ = Signal.just("path.name").keyPath(\NSString.pathExtension).subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == "name")
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testMapWithState() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.from(1...5).map(initialState: 0) { (state: inout Int, v: Int) -> Int in
			state += 1
			return v * 2 + state
		}.subscribe { r in results.append(r) }
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(results.at(2)?.value == 9)
		XCTAssert(results.at(3)?.value == 12)
		XCTAssert(results.at(4)?.value == 15)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testScan() {
		var results = [Result<Int, SignalEnd>]()
		Signal.from(1...5).scan(initialState: 2) { a, v in a + v }.subscribeUntilEnd { r in
			results.append(r)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 5)
		XCTAssert(results.at(2)?.value == 8)
		XCTAssert(results.at(3)?.value == 12)
		XCTAssert(results.at(4)?.value == 17)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testWindowInterval() {
		var results = Array<Array<Result<Int, SignalEnd>>>()
		let coordinator = DebugContextCoordinator()
		let (input, out) = Signal<Int>.create { s in
			s.window(interval: .interval(0.2), count: 5, context: coordinator.direct).subscribe { r in
				if let v = r.value {
					let index = results.count
					results.append(Array<Result<Int, SignalEnd>>())
					v.subscribeUntilEnd { r in
						results[index].append(r)
					}
				} else {
					XCTAssert(r.isComplete)
				}
			}
		}
		for i in 1...12 {
			input.send(value: i)
		}
		let delay = coordinator.direct.singleTimer(interval: .interval(0.5)) {
			input.send(value: 13)
			input.complete()
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
		XCTAssert(r1?.at(5)?.error?.isComplete == true)
		XCTAssert(r2?.count == 6)
		XCTAssert(r2?.at(0)?.value == 6)
		XCTAssert(r2?.at(1)?.value == 7)
		XCTAssert(r2?.at(2)?.value == 8)
		XCTAssert(r2?.at(3)?.value == 9)
		XCTAssert(r2?.at(4)?.value == 10)
		XCTAssert(r2?.at(5)?.error?.isComplete == true)
		XCTAssert(r3?.count == 2)
		XCTAssert(r3?.at(0)?.value == 11)
		XCTAssert(r3?.at(1)?.value == 12)
		coordinator.runScheduledTasks()

		XCTAssert(coordinator.currentTime == 500_000_000)
		XCTAssert(results.count == 4)
		let r4 = results.at(3)
		XCTAssert(r4?.count == 2)
		XCTAssert(r4?.at(0)?.value == 13)
		XCTAssert(r4?.at(1)?.error?.isCancelled == true)
		
		withExtendedLifetime(out) { }
		withExtendedLifetime(delay) { }
		withExtendedLifetime(input) { }
	}
	
	func testWindowWindows() {
		var results = Array<Array<Result<Int, SignalEnd>>>()
		let coordinator = DebugContextCoordinator()
		
		let baseSignal = Signal.interval(.interval(0.03), context: coordinator.global)
		let windowedSignal = baseSignal.window(windows: Signal.interval(.interval(0.2), initial: .interval(0.0499), context: coordinator.global).map { _ in
			Signal<Void>.timer(interval: .interval(0.1), context: coordinator.global)
		})
		let out = windowedSignal.subscribe { r in
			if let v = r.value {
				let index = results.count
				results.append(Array<Result<Int, SignalEnd>>())
				v.subscribeUntilEnd { r in
					results[index].append(r)
				}
			}
			
			if coordinator.currentTime > 500 * USEC_PER_SEC {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()

		XCTAssert(results.count == 4)
		let r1 = results.at(0)
		let r2 = results.at(1)
		let r3 = results.at(2)
		let r4 = results.at(3)

		XCTAssert(r1?.count == 4)
		XCTAssert(r1?.at(0)?.value == 1)
		XCTAssert(r1?.at(1)?.value == 2)
		XCTAssert(r1?.at(2)?.value == 3)
		XCTAssert(r1?.at(3)?.error?.isComplete == true)

		XCTAssert(r2?.count == 4)
		XCTAssert(r2?.at(0)?.value == 8)
		XCTAssert(r2?.at(1)?.value == 9)
		XCTAssert(r2?.at(2)?.value == 10)
		XCTAssert(r2?.at(3)?.error?.isComplete == true)

		XCTAssert(r3?.count == 5)
		XCTAssert(r3?.at(0)?.value == 14)
		XCTAssert(r3?.at(1)?.value == 15)
		XCTAssert(r3?.at(2)?.value == 16)
		XCTAssert(r3?.at(3)?.value == 17)
		XCTAssert(r3?.at(4)?.error?.isComplete == true)

		XCTAssert(r4?.count == 1)
		XCTAssert(r4?.at(0)?.error?.isComplete == true)
		
		withExtendedLifetime(out) { }
	}
	
	func testWindowTimespanTimeInterval() {
		var results = Array<Array<Result<Int, SignalEnd>>>()
		let coordinator = DebugContextCoordinator()
		
		let baseSignal = Signal.interval(.interval(0.03), context: coordinator.global).timeout(interval: .interval(0.34), resetOnValue: false, context: coordinator.global)
		let windowedSignal = baseSignal.window(interval: .interval(0.091), timeshift: .interval(0.151), context: coordinator.global)
		let out = windowedSignal.subscribe { r in
			if let v = r.value {
				let index = results.count
				results.append(Array<Result<Int, SignalEnd>>())
				v.subscribeUntilEnd { r in
					results[index].append(r)
				}
			}
		}
		coordinator.runScheduledTasks(untilTime: 400 * USEC_PER_SEC)
		out.cancel()

		XCTAssert(results.count == 3)
		let r1 = results.at(0)
		let r2 = results.at(1)
		let r3 = results.at(2)

		XCTAssert(r1?.count == 4)
		XCTAssert(r1?.at(0)?.value == 0)
		XCTAssert(r1?.at(1)?.value == 1)
		XCTAssert(r1?.at(2)?.value == 2)
		XCTAssert(r1?.at(3)?.error?.isComplete == true)

		XCTAssert(r2?.count == 4)
		XCTAssert(r2?.at(0)?.value == 5)
		XCTAssert(r2?.at(1)?.value == 6)
		XCTAssert(r2?.at(2)?.value == 7)
		XCTAssert(r2?.at(3)?.error?.isComplete == true)

		XCTAssert(r3?.count == 2)
		XCTAssert(r3?.at(0)?.value == 10)
		XCTAssert(r3?.at(1)?.error?.isCancelled == true)
		
		withExtendedLifetime(out) { }
	}
	
	func testWindowCountSkip() {
		var results = Array<Array<Result<Int, SignalEnd>>>()
		let coordinator = DebugContextCoordinator()
		
		let baseSignal = Signal.interval(.interval(0.03), context: coordinator.global)
		let windowedSignal = baseSignal.window(count: 3, skip: 5)
		let out = windowedSignal.subscribe { r in
			if let v = r.value {
				let index = results.count
				results.append(Array<Result<Int, SignalEnd>>())
				v.subscribeUntilEnd { r in
					results[index].append(r)
				}
			}
			
			if coordinator.currentTime > 300 * USEC_PER_SEC {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()

		XCTAssert(results.count == 3)
		let r1 = results.at(0)
		let r2 = results.at(1)
		let r3 = results.at(2)

		XCTAssert(r1?.count == 4)
		XCTAssert(r1?.at(0)?.value == 0)
		XCTAssert(r1?.at(1)?.value == 1)
		XCTAssert(r1?.at(2)?.value == 2)
		XCTAssert(r1?.at(3)?.error?.isComplete == true)

		XCTAssert(r2?.count == 4)
		XCTAssert(r2?.at(0)?.value == 5)
		XCTAssert(r2?.at(1)?.value == 6)
		XCTAssert(r2?.at(2)?.value == 7)
		XCTAssert(r2?.at(3)?.error?.isComplete == true)

		XCTAssert(r3?.count == 2)
		XCTAssert(r3?.at(0)?.value == 10)
		XCTAssert(r3?.at(1)?.error?.isCancelled == true)
		
		withExtendedLifetime(out) { }
	}
	
	func testWindowCount() {
		var results = Array<Array<Result<Int, SignalEnd>>>()
		let coordinator = DebugContextCoordinator()
		
		let baseSignal = Signal.interval(.interval(0.03), context: coordinator.global)
		let windowedSignal = baseSignal.window(count: 3)
		let out = windowedSignal.subscribe { r in
			if let v = r.value {
				let index = results.count
				results.append(Array<Result<Int, SignalEnd>>())
				v.subscribeUntilEnd { r in
					results[index].append(r)
				}
			}
			
			if coordinator.currentTime > 160 * USEC_PER_SEC {
				coordinator.stop()
			}
		}
		coordinator.runScheduledTasks()

		XCTAssert(results.count == 3)
		let r1 = results.at(0)
		let r2 = results.at(1)
		let r3 = results.at(2)

		XCTAssert(r1?.count == 4)
		XCTAssert(r1?.at(0)?.value == 0)
		XCTAssert(r1?.at(1)?.value == 1)
		XCTAssert(r1?.at(2)?.value == 2)
		XCTAssert(r1?.at(3)?.error?.isComplete == true)

		XCTAssert(r2?.count == 4)
		XCTAssert(r2?.at(0)?.value == 3)
		XCTAssert(r2?.at(1)?.value == 4)
		XCTAssert(r2?.at(2)?.value == 5)
		XCTAssert(r2?.at(3)?.error?.isComplete == true)

		XCTAssert(r3?.count == 2)
		XCTAssert(r3?.at(0)?.value == 6)
		XCTAssert(r3?.at(1)?.error?.isCancelled == true)
		
		withExtendedLifetime(out) { }
	}
	
	func testDebounce() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		var delayedInputs = [Lifetime]()
		let delays: [Int] = [4, 8, 12, 16, 60, 64, 68, 72, 120, 124, 128, 170, 174, 220, 224]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.main.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		
		let out = signal.debounce(interval: .interval(0.02), context: coordinator.direct).take(5).subscribe { r in
			results.append(r)
			if r.isFailure {
				coordinator.stop()
			}
		}
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(out) { }
		withExtendedLifetime(delayedInputs) { }
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 7)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(results.at(3)?.value == 12)
		XCTAssert(results.at(4)?.value == 14)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testThrottleFirst() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		var delayedInputs = [Lifetime]()
		let delays: [Int] = [4, 8, 12, 16, 60, 64, 68, 72, 120, 124, 128, 170, 174, 220, 224]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.main.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}

		let out = signal.throttleFirst(interval: .interval(0.02), context: coordinator.direct).take(5).subscribe { r in
			results.append(r)
			if r.isFailure {
				coordinator.stop()
			}
		}
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(out) { }
		withExtendedLifetime(delayedInputs) { }
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 8)
		XCTAssert(results.at(3)?.value == 11)
		XCTAssert(results.at(4)?.value == 13)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testDistinct() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 0, 1, 2, 3, 5, 5, 1, 0, 2, 7, 5).distinct().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 5)
		XCTAssert(results.at(5)?.value == 7)
		XCTAssert(results.at(6)?.error?.isComplete == true)
	}
	
	func testDistinctUntilChanged() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 0, 1, 1, 1, 5, 5, 1, 0, 0, 7).distinctUntilChanged().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.value == 7)
		XCTAssert(results.at(6)?.error?.isComplete == true)
	}
	
	func testDistinctUntilChangedWithComparator() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 1, 0, 1, 2, 3, 3, 5).distinctUntilChanged() { a, b in a + 1 == b }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 0)
		XCTAssert(results.at(2)?.value == 3)
		XCTAssert(results.at(3)?.value == 5)
		XCTAssert(results.at(4)?.error?.isComplete == true)
	}
	
	func testElementAt() {
		var r0 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).elementAt(3).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 8)
		XCTAssert(r0.at(1)?.error?.isComplete == true)
		
		var r1 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.preclosed(12, 13, 14, 15, 16, end: .cancelled).elementAt(5).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 1)
		XCTAssert(r1.at(0)?.error?.isCancelled == true)
	}
	
	func testFilter() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 0, 1, 2, 3, 5, 5, 1, 4, 6, 0, 2, 7, 5).filter() { v in (v % 2) == 0 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
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
		XCTAssert(results.at(7)?.error?.isComplete == true)
	}
	
	func testOfType() {
		var results = [Result<NSString, SignalEnd>]()
		_ = Signal.just(NSString(string: "hello"), NSObject(), NSString(string: "world")).ofType(NSString.self).subscribe { (r: Result<NSString, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == "hello")
		XCTAssert(results.at(1)?.value == "world")
		XCTAssert(results.at(2)?.error?.isComplete == true)
	}
	
	func testFirst() {
		var r0 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).first().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 5)
		XCTAssert(r0.at(1)?.error?.isComplete == true)
		
		var r1 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).first() { v in v > 7 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 8)
		XCTAssert(r1.at(1)?.error?.isComplete == true)
	}
	
	func testSingle() {
		var r0 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 5, 5, 7, 7, 7, 8, 8, 8).single { $0 == 7 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 1)
		XCTAssert(r0.at(0)?.error?.isComplete == true)
		
		var r1 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).single { $0 == 7 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 7)
		XCTAssert(r1.at(1)?.error?.isComplete == true)
		
		var r2 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 8, 9, 10).single { $0 == 7 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r2.append(r)
		}
		XCTAssert(r2.count == 1)
		XCTAssert(r2.at(0)?.error?.isComplete == true)
		
		var r3 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 8, 9, 10).single().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r3.append(r)
		}
		XCTAssert(r3.count == 1)
		XCTAssert(r3.at(0)?.error?.isComplete == true)
		
		var r4 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5).single().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r4.append(r)
		}
		XCTAssert(r4.count == 2)
		XCTAssert(r4.at(0)?.value == 5)
		XCTAssert(r4.at(1)?.error?.isComplete == true)
	}
	
	func testIgnoreElements() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 0, 1, 2, 3, 5, 5, 1, 4, 6, 0, 2, 7, 5).ignoreElements().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 1)
		XCTAssert(results.at(0)?.error?.isComplete == true)
	}
	
	func testLast() {
		var r0 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).last().subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r0.append(r)
		}
		XCTAssert(r0.count == 2)
		XCTAssert(r0.at(0)?.value == 10)
		XCTAssert(r0.at(1)?.error?.isComplete == true)
		
		var r1 = [Result<Int, SignalEnd>]()
		_ = Signal.just(5, 6, 7, 8, 9, 10).last() { v in v < 7 }.subscribe { (r: Result<Int, SignalEnd>) -> Void in
			r1.append(r)
		}
		XCTAssert(r1.count == 2)
		XCTAssert(r1.at(0)?.value == 6)
		XCTAssert(r1.at(1)?.error?.isComplete == true)
	}
	
	func testSample() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Int>.create()
		let (triggerInput, trigger) = Signal<Void>.create()
		let sample = signal.sample(trigger)
		let out = sample.subscribe { (r: Result<Int, SignalEnd>) -> Void in
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
		
		input.complete()
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 5)
		XCTAssert(results.at(2)?.value == 13)
		XCTAssert(results.at(3)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testSkip() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 1, 2, 3, 4, 5, 6, 7).skip(3).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.value == 6)
		XCTAssert(results.at(4)?.value == 7)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testSkipLast() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 1, 2, 3, 4, 5, 6, 7).skipLast(3).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 4)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testTake() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 1, 2, 3, 4, 5, 6, 7).take(3).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testTakeLast() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal.just(0, 1, 2, 3, 4, 5, 6, 7).takeLast(3).subscribe { (r: Result<Int, SignalEnd>) -> Void in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.value == 6)
		XCTAssert(results.at(2)?.value == 7)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testWithLatestFrom() {
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		var results = [Signal<Int>.Result]()
		let output = signal1.withLatestFrom(signal2) { $0 + $1 }.subscribe { result in
			results.append(result)
		}
		input1.send(value: 1)
		input1.send(value: 2)
		input1.send(value: 3)
		input2.send(value: 1)
		input2.send(value: 2)
		input1.send(value: 4)
		input1.send(value: 5)
		input2.send(value: 10)
		input1.send(value: 6)
		input1.complete()
		XCTAssertEqual(results.count, 4)
		XCTAssertEqual(results.at(0)?.value, 6)
		XCTAssertEqual(results.at(1)?.value, 7)
		XCTAssertEqual(results.at(2)?.value, 16)
		XCTAssertEqual(results.at(3)?.error?.isComplete, true)
		withExtendedLifetime(input2) {}
		withExtendedLifetime(output) {}
	}
	
	func testCombineLatest2() {
		var results = [Result<String, SignalEnd>]()
		let (signal1Input, signal1) = Signal<Int>.create()
		let (signal2Input, signal2) = Signal<Double>.create()
		let combined = signal1.combineLatestWith(signal2) {
			"\($0) \($1)"
		}
		let out = combined.subscribe { (r: Result<String, SignalEnd>) -> Void in
			results.append(r)
		}
		
		signal1Input.send(value: -1)
		signal1Input.send(value: 0)
		signal2Input.send(value: 1.1)
		signal2Input.send(value: 2.2)
		signal2Input.send(value: 3.3)
		signal1Input.send(value: 1)
		signal1Input.send(value: 2)
		
		signal2Input.complete()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 1.1")
		XCTAssert(results.at(1)?.value == "0 2.2")
		XCTAssert(results.at(2)?.value == "0 3.3")
		XCTAssert(results.at(3)?.value == "1 3.3")
		XCTAssert(results.at(4)?.value == "2 3.3")
		XCTAssert(results.at(5)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testCombineLatest3() {
		var results = [Result<String, SignalEnd>]()
		let (signal1Input, signal1) = Signal<Int>.create()
		let (signal2Input, signal2) = Signal<Double>.create()
		let (signal3Input, signal3) = Signal<String>.create()
		let combined = signal1.combineLatestWith(signal2, signal3) {
			"\($0) \($1) \($2)"
		}
		let out = combined.subscribe { (r: Result<String, SignalEnd>) -> Void in
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
		
		signal1Input.complete()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello")
		XCTAssert(results.at(2)?.value == "0 3.3 World")
		XCTAssert(results.at(3)?.value == "1 3.3 World")
		XCTAssert(results.at(4)?.value == "1 3.3 !")
		XCTAssert(results.at(5)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testCombineLatest4() {
		var results = [Result<String, SignalEnd>]()
		let (signal1Input, signal1) = Signal<Int>.create()
		let (signal2Input, signal2) = Signal<Double>.create()
		let (signal3Input, signal3) = Signal<String>.create()
		let (signal4Input, signal4) = Signal<Int>.create()
		let combined = signal1.combineLatestWith(signal2, signal3, signal4) {
			"\($0) \($1) \($2) \($3)"
		}
		let out = combined.subscribe { (r: Result<String, SignalEnd>) -> Void in
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
		
		signal1Input.complete()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello 11")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello 11")
		XCTAssert(results.at(2)?.value == "0 3.3 Hello 12")
		XCTAssert(results.at(3)?.value == "0 3.3 World 12")
		XCTAssert(results.at(4)?.value == "1 3.3 World 12")
		XCTAssert(results.at(5)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testCombineLatest5() {
		var results = [Result<String, SignalEnd>]()
		let (signal1Input, signal1) = Signal<Int>.create()
		let (signal2Input, signal2) = Signal<Double>.create()
		let (signal3Input, signal3) = Signal<String>.create()
		let (signal4Input, signal4) = Signal<Int>.create()
		let (signal5Input, signal5) = Signal<Bool>.create()
		let combined = signal1.combineLatestWith(signal2, signal3, signal4, signal5) {
			"\($0) \($1) \($2) \($3) \($4)"
		}
		let out = combined.subscribe { (r: Result<String, SignalEnd>) -> Void in
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
		
		signal1Input.complete()
		
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == "0 2.2 Hello 11 true")
		XCTAssert(results.at(1)?.value == "0 3.3 Hello 11 true")
		XCTAssert(results.at(2)?.value == "0 3.3 Hello 12 true")
		XCTAssert(results.at(3)?.value == "0 3.3 World 12 true")
		XCTAssert(results.at(4)?.value == "1 3.3 World 12 true")
		XCTAssert(results.at(5)?.value == "1 3.3 World 12 false")
		XCTAssert(results.at(6)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testJoin() {
		var results1 = [Result<String, SignalEnd>]()
		let (leftInput1, leftSignal1) = Signal<Int>.create()
		let (rightInput1, rightSignal1) = Signal<Double>.create()
		let ep1 = leftSignal1.intersect(withRight: rightSignal1, leftEnd: { v -> Signal<Void> in Signal<Void>.preclosed() }, rightEnd: { v in Signal<Void>.preclosed() }) { tuple in return "Unexpected \(tuple.0) \(tuple.1)" }.subscribe {
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
		leftInput1.complete()
		XCTAssert(results1.count == 1)
		XCTAssert(results1.first?.error?.isComplete == true)
		
		withExtendedLifetime(ep1) {}
		
		var results2 = [Result<String, SignalEnd>]()
		let (leftInput2, leftSignal2) = Signal<Int>.create { s in s.multicast() }
		let (rightInput2, rightSignal2) = Signal<Double>.create { s in s.multicast() }
		let ep2 = leftSignal2.intersect(withRight: rightSignal2, leftEnd: { v in leftSignal2 }, rightEnd: { v in rightSignal2 }) { tuple in return "\(tuple.0) \(tuple.1)" }.subscribe {
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
		
		var results3 = [Result<String, SignalEnd>]()
		let (leftInput3, leftSignal3) = Signal<Int>.create { s in s.multicast() }
		let (rightInput3, rightSignal3) = Signal<Double>.create { s in s.multicast() }
		let ep3 = leftSignal3.intersect(withRight: rightSignal3, leftEnd: { v in leftSignal3.skip(1) }, rightEnd: { v in rightSignal3.skip(1) }) { tuple in return "\(tuple.0) \(tuple.1)" }.subscribe {
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
	
	func testGroupIntersect() {
		var results1 = [Result<String, SignalEnd>]()
		let (leftInput1, leftSignal1) = Signal<Int>.create()
		let (rightInput1, rightSignal1) = Signal<Double>.create()
		let ep1 = leftSignal1.groupIntersect(withRight: rightSignal1, leftEnd: { v -> Signal<Void> in Signal<Void>.preclosed() }, rightEnd: { v in Signal<Void>.preclosed() }) { tuple in tuple.1.map { "\(tuple.0) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v):
				v.subscribeValuesUntilEnd {
					results1.append(Result<String, SignalEnd>.success($0))
				}
			case .failure(let e): results1.append(Result<String, SignalEnd>.failure(e))
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
		leftInput1.complete()
		XCTAssert(results1.count == 1)
		XCTAssert(results1.first?.error?.isComplete == true)
		
		withExtendedLifetime(ep1) {}
		
		var results2 = [Result<String, SignalEnd>]()
		let (leftInput2, leftSignal2) = Signal<Int>.create { s in s.multicast() }
		let (rightInput2, rightSignal2) = Signal<Double>.create { s in s.multicast() }
		let ep2 = leftSignal2.groupIntersect(withRight: rightSignal2, leftEnd: { v in leftSignal2 }, rightEnd: { v in rightSignal2 }) { tuple in tuple.1.map { "\(tuple.0) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v):
				v.subscribeValuesUntilEnd {
					results2.append(Result<String, SignalEnd>.success($0))
				}
			case .failure(let e):
				results2.append(Result<String, SignalEnd>.failure(e))
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
		
		var results3 = [Result<String, SignalEnd>]()
		let (leftInput3, leftSignal3) = Signal<Int>.create { s in s.multicast() }
		let (rightInput3, rightSignal3) = Signal<Double>.create { s in s.multicast() }
		let ep3 = leftSignal3.groupIntersect(withRight: rightSignal3, leftEnd: { v in leftSignal3.skip(1) }, rightEnd: { v in rightSignal3.skip(1) }) { tuple in tuple.1.map { "\(tuple.0) \($0)" } }.subscribe {
			switch $0 {
			case .success(let v):
				v.subscribeValuesUntilEnd {
					results3.append(Result<String, SignalEnd>.success($0))
				}
			case .failure(let e): results3.append(Result<String, SignalEnd>.failure(e))
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

	func testPlaygroundMerge() {
		let smileysArray = ["😀", "🙃", "😉", "🤣"]
		let spookeysArray = ["👻", "🎃", "👹", "😈"]
		let animalsArray = ["🐶", "🐱", "🐭", "🐨"]
		let smileys = Signal<String>.from(smileysArray, end: nil).playback()
		let spookeys = Signal<String>.from(spookeysArray, end: .complete).playback()
		let animals = Signal<String>.from(animalsArray, end: .cancelled).playback()
		
		var result = [String]()
		let out = Signal<String>.merge(smileys, spookeys, animals).subscribeValues {
			result.append($0)
		}
		var expected = smileysArray
		expected.append(contentsOf: spookeysArray)
		expected.append(contentsOf: animalsArray)
		XCTAssert(result == expected)
		withExtendedLifetime(out) {}
	}

	func testMerge() {
		let merge2 = Signal<Int>.merge(Signal<Int>.from(0..<10), Signal<Int>.from(10..<20))
		var results2 = [Result<Int, SignalEnd>]()
		_ = merge2.subscribe { (r: Result<Int, SignalEnd>) in
			results2.append(r)
		}
		XCTAssert(results2.count == 21)
		for i in 0..<20 {
			XCTAssert(results2.at(i)?.value == i)
		}
		XCTAssert(results2.at(20)?.error?.isComplete == true)
		
		var emptyMergeResults = [Result<Int, SignalEnd>]()
		let emptyMerge = Signal<Int>.merge().subscribe {
			emptyMergeResults.append($0)
		}
		XCTAssert(emptyMergeResults.count == 1)
		XCTAssert(emptyMergeResults.at(0)?.error?.isComplete == true)
		withExtendedLifetime(emptyMerge) {}
		
		var immediatelyClosedMergeResults = [Result<Int, SignalEnd>]()
		let immediatelyClosedMerge = Signal<Int>.merge(Signal<Int>.preclosed()).subscribe {
			immediatelyClosedMergeResults.append($0)
		}
		XCTAssert(immediatelyClosedMergeResults.count == 1)
		XCTAssert(immediatelyClosedMergeResults.at(0)?.error?.isComplete == true)
		withExtendedLifetime(immediatelyClosedMerge) {}
	}
	
	func testStartWith() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(10..<20).startWith(sequence: 0..<10).subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		XCTAssert(results.count == 21)
		for i in 0..<20 {
			XCTAssert(results.at(i)?.value == i)
		}
		XCTAssert(results.at(20)?.error?.isComplete == true)
	}
	
	func testEndWith() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(0..<10).endWith(sequence: 10..<20).subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		XCTAssert(results.count == 21)
		for i in 0..<20 {
			XCTAssert(results.at(i)?.value == i)
		}
		XCTAssert(results.at(20)?.error?.isComplete == true)
	}
	
	func testSwitchLatest() {
		var results = [Result<Int, SignalEnd>]()
		let (input, signal) = Signal<Signal<Int>>.create()
		let out = signal.switchLatest().subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		let (input1, child1) = Signal<Int>.create()
		let (input2, child2) = Signal<Int>.create()
		let (input3, child3) = Signal<Int>.create()
		let (input4, child4) = Signal<Int>.create()
		input.send(value: child1)
		input1.send(value: 0)
		input1.send(value: 1)
		input.send(value: child2)
		input1.send(value: 2)
		input1.send(value: 3)
		input2.send(value: 10)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.complete()
		input1.send(value: 4)
		input1.send(value: 5)
		input.send(value: child3)
		input3.complete()
		input1.send(value: 6)
		input1.send(value: 7)
		input.send(value: child4)
		input4.send(value: 30)
		input4.send(value: 31)
		input4.send(value: 32)
		input4.complete()
		input1.send(value: 8)
		input1.send(value: 9)
		input.complete()
		
		XCTAssert(results.count == 9)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 10)
		XCTAssert(results.at(3)?.value == 11)
		XCTAssert(results.at(4)?.value == 12)
		XCTAssert(results.at(5)?.value == 30)
		XCTAssert(results.at(6)?.value == 31)
		XCTAssert(results.at(7)?.value == 32)
		XCTAssert(results.at(8)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testZip2() {
		var results = [Result<(Int, Int), SignalEnd>]()
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		let out = signal1.zipWith(signal2).subscribe { (r: Result<(Int, Int), SignalEnd>) in
			results.append(r)
		}
		input1.send(value: 0)
		input1.send(value: 1)
		input1.send(value: 2)
		input2.send(value: 10)
		input2.send(value: 11)
		input2.send(value: 12)
		input1.send(value: 3)
		input1.complete()
		input2.send(value: 13)
		input2.send(value: 14)
		input2.send(value: 15)
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.0 == 0 && results.at(0)?.value?.1 == 10)
		XCTAssert(results.at(1)?.value?.0 == 1 && results.at(1)?.value?.1 == 11)
		XCTAssert(results.at(2)?.value?.0 == 2 && results.at(2)?.value?.1 == 12)
		XCTAssert(results.at(3)?.value?.0 == 3 && results.at(3)?.value?.1 == 13)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testZip3() {
		var results = [Result<(Int, Int, Int), SignalEnd>]()
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		let (input3, signal3) = Signal<Int>.create()
		let out = signal1.zipWith(signal2, signal3).subscribe { (r: Result<(Int, Int, Int), SignalEnd>) in
			results.append(r)
		}
		input1.send(value: 0)
		input3.send(value: 20)
		input1.send(value: 1)
		input1.send(value: 2)
		input2.send(value: 10)
		input3.send(value: 21)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.send(value: 13)
		input3.send(value: 22)
		input2.send(value: 14)
		input2.send(value: 15)
		input1.send(value: 3)
		input3.send(value: 23)
		input3.send(value: 24)
		input3.complete()
		input1.complete()
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.0 == 0 && results.at(0)?.value?.1 == 10 && results.at(0)?.value?.2 == 20)
		XCTAssert(results.at(1)?.value?.0 == 1 && results.at(1)?.value?.1 == 11 && results.at(1)?.value?.2 == 21)
		XCTAssert(results.at(2)?.value?.0 == 2 && results.at(2)?.value?.1 == 12 && results.at(2)?.value?.2 == 22)
		XCTAssert(results.at(3)?.value?.0 == 3 && results.at(3)?.value?.1 == 13 && results.at(3)?.value?.2 == 23)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testZip4() {
		var results = [Result<(Int, Int, Int, Int), SignalEnd>]()
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		let (input3, signal3) = Signal<Int>.create()
		let (input4, signal4) = Signal<Int>.create()
		let out = signal1.zipWith(signal2, signal3, signal4).subscribe { (r: Result<(Int, Int, Int, Int), SignalEnd>) in
			results.append(r)
		}
		input4.send(value: 30)
		input4.send(value: 31)
		input4.send(value: 32)
		input1.send(value: 0)
		input3.send(value: 20)
		input1.send(value: 1)
		input1.send(value: 2)
		input2.send(value: 10)
		input3.send(value: 21)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.send(value: 13)
		input3.send(value: 22)
		input2.send(value: 14)
		input2.send(value: 15)
		input1.send(value: 3)
		input3.send(value: 23)
		input3.send(value: 24)
		input3.complete()
		input4.send(value: 33)
		input1.complete()
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.0 == 0 && results.at(0)?.value?.1 == 10 && results.at(0)?.value?.2 == 20 && results.at(0)?.value?.3 == 30)
		XCTAssert(results.at(1)?.value?.0 == 1 && results.at(1)?.value?.1 == 11 && results.at(1)?.value?.2 == 21 && results.at(1)?.value?.3 == 31)
		XCTAssert(results.at(2)?.value?.0 == 2 && results.at(2)?.value?.1 == 12 && results.at(2)?.value?.2 == 22 && results.at(2)?.value?.3 == 32)
		XCTAssert(results.at(3)?.value?.0 == 3 && results.at(3)?.value?.1 == 13 && results.at(3)?.value?.2 == 23 && results.at(3)?.value?.3 == 33)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testZip5() {
		var results = [Result<(Int, Int, Int, Int, Int), SignalEnd>]()
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		let (input3, signal3) = Signal<Int>.create()
		let (input4, signal4) = Signal<Int>.create()
		let (input5, signal5) = Signal<Int>.create()
		let out = signal1.zipWith(signal2, signal3, signal4, signal5).subscribe { (r: Result<(Int, Int, Int, Int, Int), SignalEnd>) in
			results.append(r)
		}
		input4.send(value: 30)
		input4.send(value: 31)
		input4.send(value: 32)
		input4.send(value: 33)
		input1.send(value: 0)
		input3.send(value: 20)
		input1.send(value: 1)
		input1.send(value: 2)
		input2.send(value: 10)
		input3.send(value: 21)
		input2.send(value: 11)
		input2.send(value: 12)
		input2.send(value: 13)
		input3.send(value: 22)
		input2.send(value: 14)
		input2.send(value: 15)
		input1.send(value: 3)
		input3.send(value: 23)
		input3.send(value: 24)
		input5.send(value: 40)
		input5.send(value: 41)
		input5.send(value: 42)
		input5.send(value: 43)
		input5.send(value: 44)
		input3.complete()
		input1.complete()
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value?.0 == 0 && results.at(0)?.value?.1 == 10 && results.at(0)?.value?.2 == 20 && results.at(0)?.value?.3 == 30 && results.at(0)?.value?.4 == 40)
		XCTAssert(results.at(1)?.value?.0 == 1 && results.at(1)?.value?.1 == 11 && results.at(1)?.value?.2 == 21 && results.at(1)?.value?.3 == 31 && results.at(1)?.value?.4 == 41)
		XCTAssert(results.at(2)?.value?.0 == 2 && results.at(2)?.value?.1 == 12 && results.at(2)?.value?.2 == 22 && results.at(2)?.value?.3 == 32 && results.at(2)?.value?.4 == 42)
		XCTAssert(results.at(3)?.value?.0 == 3 && results.at(3)?.value?.1 == 13 && results.at(3)?.value?.2 == 23 && results.at(3)?.value?.3 == 33 && results.at(3)?.value?.4 == 43)
		XCTAssert(results.at(4)?.error?.isComplete == true)
		
		withExtendedLifetime(out) {}
	}
	
	func testCatch() {
		var results1 = [Result<Int, SignalEnd>]()
		let signal1 = Signal<Int>.from(0..<10, end: .other(TestError.zeroValue))
		let signal2 = Signal<Int>.from(10..<20)
		_ = signal1.catchError { e -> Signal<Int> in
			return signal2
		}.subscribe { (r: Result<Int, SignalEnd>) in
			results1.append(r)
		}
		XCTAssert(results1.count == 21)
		for i in 0..<20 {
			XCTAssert(results1.at(i)?.value == i)
		}
		XCTAssert(results1.at(20)?.error?.isComplete == true)
	}
	
	func testRetry() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		var count = 0
		let out = Signal<Int>.generate { input in
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
				i.send(end: SignalEnd.complete)
			}
		}.retry(count: 1, delayInterval: .interval(0.1), context: coordinator.direct).subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 4)
		
		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}

		XCTAssert(coordinator.currentTime == 100_000_000)
		
		XCTAssert(results.count == 11)
		XCTAssert(results.at(5)?.value == 0)
		XCTAssert(results.at(6)?.value == 1)
		XCTAssert(results.at(7)?.value == 2)
		XCTAssert(results.at(8)?.value == 3)
		XCTAssert(results.at(9)?.value == 4)
		XCTAssert(results.at(10)?.error?.isComplete == true)
	}
	
	func testDelay() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		var times = [UInt64]()
		let out = Signal<Int>.from(0..<5).delay(initialState: 5, context: coordinator.direct) { (offset: inout Int, v: Int) -> DispatchTimeInterval in
			return DispatchTimeInterval.interval(Double(offset - v) * 0.05)
		}.subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
			times.append(coordinator.currentTime)
		}
		
		coordinator.runScheduledTasks()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 4)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.error?.isComplete == true)
		XCTAssert(times.at(0).map { (v: UInt64) -> Bool in v == 50_000_000 } == true)
		XCTAssert(times.at(1).map { (v: UInt64) -> Bool in v == 100_000_000 } == true)
		XCTAssert(times.at(2).map { (v: UInt64) -> Bool in v == 150_000_000 } == true)
		XCTAssert(times.at(3).map { (v: UInt64) -> Bool in v == 200_000_000 } == true)
		XCTAssert(times.at(4).map { (v: UInt64) -> Bool in v == 250_000_000 } == true)
		XCTAssert(times.at(5).map { (v: UInt64) -> Bool in v == 250_000_000 } == true)
	}
	
	func testDelayInterval() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		var times = [UInt64]()
		let out = Signal
			.interval(.seconds(1), initial: .seconds(0), context: coordinator.global)
			.timeout(interval: .seconds(5), resetOnValue: false, context: coordinator.global)
			.delay(interval: .seconds(5), context: coordinator.global)
			.subscribe { (r: Result<Int, SignalEnd>) in
				results.append(r)
				times.append(coordinator.currentTime)
			}
		
		coordinator.runScheduledTasks()
		
		out.cancel()
		
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.value == 4)
		XCTAssert(results.at(5)?.error?.otherError as? SignalReactiveError == .timeout)
		
		// Explanation of the `4` at the end of these times:
		// `intervalSignal` is invoked asynchronously on `coordinator.global`, adding 1
		// `timeout` is invoked asynchronously on `coordinator.global`, adding 1
		// `delay` runs its offset calculation function asynchronously on `coordinator.global`, adding 1
		// the timer started by `delay` completes asynchronously on `coordinator.global`, adding 1
		XCTAssert(times.at(0).map { (v: UInt64) -> Bool in v == 5_000_000_004 } == true)
		XCTAssert(times.at(1).map { (v: UInt64) -> Bool in v == 6_000_000_004 } == true)
		XCTAssert(times.at(2).map { (v: UInt64) -> Bool in v == 7_000_000_004 } == true)
		XCTAssert(times.at(3).map { (v: UInt64) -> Bool in v == 8_000_000_004 } == true)
		XCTAssert(times.at(4).map { (v: UInt64) -> Bool in v == 9_000_000_004 } == true)
		XCTAssert(times.at(5).map { (v: UInt64) -> Bool in v == 9_000_000_004 } == true)
	}
	
	func testDelaySignal() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		var times = [UInt64]()
		let out = Signal<Int>.from(0..<5).delay(context: coordinator.direct) { (v: Int) -> Signal<Void> in
			return Signal<Void>.timer(interval: .interval(Double(6 - v) * 0.05), context: coordinator.global)
		}.subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
			times.append(coordinator.currentTime)
		}

		coordinator.runScheduledTasks()
		
		withExtendedLifetime(out) {}

		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value == 4)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 1)
		XCTAssert(results.at(4)?.value == 0)
		XCTAssert(results.at(5)?.error?.isComplete == true)

		// Explanation of the `1` at the end of these times:
		// the timer started by `delay` completes asynchronously on `coordinator.global`, adding 1
		XCTAssert(times.at(0).map { (v: UInt64) -> Bool in v == 100_000_001 } == true)
		XCTAssert(times.at(1).map { (v: UInt64) -> Bool in v == 150_000_001 } == true)
		XCTAssert(times.at(2).map { (v: UInt64) -> Bool in v == 200_000_001 } == true)
		XCTAssert(times.at(3).map { (v: UInt64) -> Bool in v == 250_000_001 } == true)
		XCTAssert(times.at(4).map { (v: UInt64) -> Bool in v == 300_000_001 } == true)
		XCTAssert(times.at(5).map { (v: UInt64) -> Bool in v == 300_000_001 } == true)
	}
	
	func testOn() {
		var results = [String]()
		let j = Signal<Int>.from(0..<5, end: .other(SignalReactiveError.timeout)).onActivate {
			results.append("activate")
		}.onDeactivate {
			results.append("deactivate")
		}.onValue { v in
			results.append("\(v)")
		}.onResult { r in
			results.append("\(r)")
		}.onError { e in
			results.append("\(e)")
		}.junction()
		
		let (i1, o1) = Signal<Int>.create()
		let ep1 = o1.subscribe { r in
			results.append("Output: \(r)")
		}
		
		_ = try? j.bind(to: i1)
		withExtendedLifetime(ep1) {}
		_ = j.disconnect()
		
		XCTAssertEqual(results, [
			"activate",
			"0",
			"success(0)",
			"Output: success(0)",
			"1",
			"success(1)",
			"Output: success(1)",
			"2",
			"success(2)",
			"Output: success(2)",
			"3",
			"success(3)",
			"Output: success(3)",
			"4",
			"success(4)",
			"Output: success(4)",
			"failure(CwlSignal.SignalEnd.other(CwlSignal.SignalReactiveError.timeout))",
			"other(CwlSignal.SignalReactiveError.timeout)",
			"Output: failure(CwlSignal.SignalEnd.other(CwlSignal.SignalReactiveError.timeout))",
			"deactivate",
		])

		results.removeAll()
		
		let (i2, o2) = Signal<Int>.create()
		let ep2 = o2.subscribe { r in
			results.append("Output: \(r)")
		}
		_ = try? j.bind(to: i2)
		withExtendedLifetime(ep2) {}

		XCTAssertEqual(results, [
			"activate",
			"0",
			"success(0)",
			"Output: success(0)",
			"1",
			"success(1)",
			"Output: success(1)",
			"2",
			"success(2)",
			"Output: success(2)",
			"3",
			"success(3)",
			"Output: success(3)",
			"4",
			"success(4)",
			"Output: success(4)",
			"failure(CwlSignal.SignalEnd.other(CwlSignal.SignalReactiveError.timeout))",
			"other(CwlSignal.SignalReactiveError.timeout)",
			"Output: failure(CwlSignal.SignalEnd.other(CwlSignal.SignalReactiveError.timeout))",
			"deactivate",
		])
	}
	
	func testMaterialize() {
		var results = [Result<Result<Int, SignalEnd>, SignalEnd>]()
		_ = Signal<Int>.just(0, 1, 2, 3).materialize().subscribe { r in
			results += r
		}
		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value?.value == 0)
		XCTAssert(results.at(1)?.value?.value == 1)
		XCTAssert(results.at(2)?.value?.value == 2)
		XCTAssert(results.at(3)?.value?.value == 3)
		XCTAssert(results.at(4)?.value?.error?.isComplete == true)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testDematerialize() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.dematerialize(Signal<Result<Int, SignalEnd>>.just(Result<Int, SignalEnd>.success(0), Result<Int, SignalEnd>.success(1), Result<Int, SignalEnd>.success(2), Result<Int, SignalEnd>.success(3))).subscribe { r in
			results += r
		}
		XCTAssert(results.count == 5)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.value == 3)
		XCTAssert(results.at(4)?.error?.isComplete == true)
	}
	
	func testTimeInterval() {
		var results = [Result<Double, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.timeInterval(context: coordinator.direct).subscribe { (r: Result<Double, SignalEnd>) in
			results.append(r)
		}

		var delayedInputs = [Lifetime]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(350)) {
			input.complete()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}

		let compare: (Double, Double) -> (Double) -> Bool = { (right: Double, epsilon: Double) -> (Double) -> Bool in
			return { (left: Double) -> Bool in left - epsilon < right && left + epsilon > right }
		}
		
		XCTAssert(results.count == 6)
		XCTAssert((results.at(0)?.value).map(compare(0.02, 1e-6)) == true)
		XCTAssert((results.at(1)?.value).map(compare(0.06, 1e-6)) == true)
		XCTAssert((results.at(2)?.value).map(compare(0.07, 1e-6)) == true)
		XCTAssert((results.at(3)?.value).map(compare(0.10, 1e-6)) == true)
		XCTAssert((results.at(4)?.value).map(compare(0.05, 1e-6)) == true)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testTimeout() {
		var results = [Result<Int, SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.timeout(interval: .interval(0.09), context: coordinator.direct).subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}

		var delayedInputs = [Lifetime]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(350)) {
			input.complete()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}

		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)

		switch results.at(3)?.error?.otherError as? SignalReactiveError {
		case .some(.timeout): break
		default: XCTFail()
		}
	}
	
	func testTimestamp() {
		var results = [Result<(Int, DispatchTime), SignalEnd>]()
		let coordinator = DebugContextCoordinator()
		let (input, signal) = Signal<Int>.create()
		let out = signal.timestamp(context: coordinator.direct).subscribe { (r: Result<(Int, DispatchTime), SignalEnd>) in
			results.append(r)
		}
		
		var delayedInputs = [Lifetime]()
		let delays: [Int] = [20, 80, 150, 250, 300]
		for i in 0..<delays.count {
			delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(delays[i])) {
				input.send(value: i)
			})
		}
		delayedInputs.append(coordinator.global.singleTimer(interval: .milliseconds(350)) {
			input.complete()
		})

		coordinator.runScheduledTasks()
		withExtendedLifetime(out) {}

		XCTAssert(results.count == 6)
		XCTAssert(results.at(0)?.value?.1.uptimeNanoseconds == 20_000_000)
		XCTAssert(results.at(1)?.value?.1.uptimeNanoseconds == 80_000_000)
		XCTAssert(results.at(2)?.value?.1.uptimeNanoseconds == 150_000_000)
		XCTAssert(results.at(3)?.value?.1.uptimeNanoseconds == 250_000_000)
		XCTAssert(results.at(4)?.value?.1.uptimeNanoseconds == 300_000_000)
		XCTAssert(results.at(5)?.error?.isComplete == true)
	}
	
	func testAll() {
		var results = [Result<Bool, SignalEnd>]()
		_ = Signal<Int>.from(1...10).all { (v: Int) -> Bool in v % 3 == 0 }.subscribe { (r: Result<Bool, SignalEnd>) in
			results.append(r)
		}
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == false)
		XCTAssert(results.at(1)?.error?.isComplete == true)

		_ = Signal<Int>.from(1...10).all { (v: Int) -> Bool in v > 0 }.subscribe { (r: Result<Bool, SignalEnd>) in
			results.append(r)
		}
		XCTAssert(results.count == 4)
		XCTAssert(results.at(2)?.value == true)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testAmb() {
		var results = [Result<Int, SignalEnd>]()
		let (input1, signal1) = Signal<Int>.create()
		let (input2, signal2) = Signal<Int>.create()
		let (input3, signal3) = Signal<Int>.create()
		let out = Signal<Int>.race(signal1, signal2, signal3).subscribe { (r: Result<Int, SignalEnd>) in
			results.append(r)
		}
		input2.send(value: 0)
		input1.send(value: 1)
		input3.send(value: 2)
		input2.send(value: 3)
		input1.send(value: 4)
		input1.send(value: 5)
		input1.complete()
		input2.send(value: 6)
		input2.complete()
		input3.send(value: 7)
		input3.send(value: 8)
		input3.complete()

		withExtendedLifetime(out) {}

		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 3)
		XCTAssert(results.at(2)?.value == 6)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testSome() {
		var results2 = [Result<Bool, SignalEnd>]()
		_ = Signal<Int>.from(1...10).find { $0 == 5 }.subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error?.isComplete == true)

		var results1 = [Result<Bool, SignalEnd>]()
		_ = Signal<Int>.from(1...10).find { $0 == 15 }.subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error?.isComplete == true)
	}
	
	func testContains() {
		var results2 = [Result<Bool, SignalEnd>]()
		_ = Signal<Int>.from(1...10).find(value: 5).subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error?.isComplete == true)

		var results1 = [Result<Bool, SignalEnd>]()
		_ = Signal<Int>.from(1...10).find(value: 15).subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error?.isComplete == true)
	}
	
	func testDefaultIfEmpty() {
		var results1 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).defaultIfEmpty(value: 5).subscribe { results1.append($0) }
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 2)
		XCTAssert(results1.at(2)?.value == 3)
		XCTAssert(results1.at(3)?.error?.isComplete == true)

		var results2 = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(0..<0).defaultIfEmpty(value: 5).subscribe { results2.append($0) }
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == 5)
		XCTAssert(results2.at(1)?.error?.isComplete == true)
	}
	
	func testSwitchIfEmpty() {
		var results1 = [Result<Int, SignalEnd>]()
		let alternate1 = Signal<Int>.from(11...13)
		_ = Signal<Int>.from(1...3).switchIfEmpty(alternate: alternate1).subscribe { results1.append($0) }
		XCTAssert(results1.count == 4)
		XCTAssert(results1.at(0)?.value == 1)
		XCTAssert(results1.at(1)?.value == 2)
		XCTAssert(results1.at(2)?.value == 3)
		XCTAssert(results1.at(3)?.error?.isComplete == true)

		var results2 = [Result<Int, SignalEnd>]()
		let alternate2 = Signal<Int>.from(11...13)
		_ = Signal<Int>.empty().switchIfEmpty(alternate: alternate2).subscribe { results2.append($0) }
		XCTAssert(results2.count == 4)
		XCTAssert(results2.at(0)?.value == 11)
		XCTAssert(results2.at(1)?.value == 12)
		XCTAssert(results2.at(2)?.value == 13)
		XCTAssert(results2.at(3)?.error?.isComplete == true)
	}
	
	func testSequenceEqual() {
		var results1 = [Result<Bool, SignalEnd>]()
		let alternate1 = Signal<Int>.from(11...13)
		_ = Signal<Int>.from(11...14).sequenceEqual(to: alternate1).subscribe { results1.append($0) }
		XCTAssert(results1.count == 2)
		XCTAssert(results1.at(0)?.value == false)
		XCTAssert(results1.at(1)?.error?.isComplete == true)

		var results2 = [Result<Bool, SignalEnd>]()
		let alternate2 = Signal<Int>.from(11...13)
		_ = Signal<Int>.from(11...13).sequenceEqual(to: alternate2).subscribe { r in
			results2.append(r)
		}
		XCTAssert(results2.count == 2)
		XCTAssert(results2.at(0)?.value == true)
		XCTAssert(results2.at(1)?.error?.isComplete == true)
	}
	
	func testSkipUntil() {
		var results = [Result<Int, SignalEnd>]()
		let (otherInput, otherSignal) = Signal<Void>.create()
		let (input, out) = Signal<Int>.create { s in s.skipUntil(otherSignal).subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		otherInput.send(value: ())
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testSkipWhile() {
		var results = [Result<Int, SignalEnd>]()
		let (input, out) = Signal<Int>.create { s in s.skipWhile { v in v != 3 }.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testSkipWhileWithState() {
		var results = [Result<Int, SignalEnd>]()
		let (input, out) = Signal<Int>.create { s in s.skipWhile(initialState: 0) { (state: inout Int, v: Int) -> Bool in
			state += v
			return (v + state) != 9
		}.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 3)
		XCTAssert(results.at(1)?.value == 4)
		XCTAssert(results.at(2)?.value == 5)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testTakeUntil() {
		var results = [Result<Int, SignalEnd>]()
		let (otherInput, otherSignal) = Signal<Void>.create()
		let (input, out) = Signal<Int>.create { s in s.takeUntil(otherSignal).subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		otherInput.send(value: ())
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testTakeWhile() {
		var results = [Result<Int, SignalEnd>]()
		let (input, out) = Signal<Int>.create { s in s.takeWhile { v in v != 3 }.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testTakeWhileWithState() {
		var results = [Result<Int, SignalEnd>]()
		let (input, out) = Signal<Int>.create { s in s.takeWhile(initialState: 0) { (state: inout Int, v: Int) -> Bool in
			state += v
			return (v + state) != 9
		}.subscribe { r in results.append(r) } }
		
		input.send(value: 0)
		input.send(value: 1)
		input.send(value: 2)
		input.send(value: 3)
		input.send(value: 4)
		input.send(value: 5)
		input.complete()
		
		withExtendedLifetime(out) {}
		
		XCTAssert(results.count == 4)
		XCTAssert(results.at(0)?.value == 0)
		XCTAssert(results.at(1)?.value == 1)
		XCTAssert(results.at(2)?.value == 2)
		XCTAssert(results.at(3)?.error?.isComplete == true)
	}
	
	func testConcat() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).concat(Signal<Int>.from(4...6)).subscribe { r in results.append(r) }
		XCTAssert(results.count == 7)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.value == 2)
		XCTAssert(results.at(2)?.value == 3)
		XCTAssert(results.at(3)?.value == 4)
		XCTAssert(results.at(4)?.value == 5)
		XCTAssert(results.at(5)?.value == 6)
		XCTAssert(results.at(6)?.error?.isComplete == true)
	}
	
	func testCount() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(4...8).count().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testMin() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).min().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 1)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testMax() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(2...5).max().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 5)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testReduceToSingleValue() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).aggregate(5) { (state, v) in state + v }.subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 11)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testSum() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).sum().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 6)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
	
	func testAverage() {
		var results = [Result<Int, SignalEnd>]()
		_ = Signal<Int>.from(1...3).average().subscribe { r in results.append(r) }
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 2)
		XCTAssert(results.at(1)?.error?.isComplete == true)
	}
}
