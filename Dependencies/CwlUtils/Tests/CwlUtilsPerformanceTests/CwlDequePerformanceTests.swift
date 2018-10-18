//
//  CwlDequePerformanceTests.swift
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

class DequePerformanceTests: XCTestCase {
	func testFIFOPerformance() {
		measure { () -> Void in
			#if DEBUG
				let outerCount = 100
			#else
				let outerCount = 100_000
			#endif
			let innerCount = 20
			var accumulator = 0
			for _ in 1...outerCount {
				var deque = Deque<Int>()
				for i in 1...innerCount {
					deque.append(i)
					accumulator ^= (deque.last ?? 0)
				}
				for _ in 1...innerCount {
					accumulator ^= (deque.first ?? 0)
					deque.remove(at: 0)
				}
			}
			XCTAssert(accumulator == 0)
		}
	}
	
	func testReferenceArrayPerformance() {
		measure { () -> Void in
			#if DEBUG
				let outerCount = 100
			#else
				let outerCount = 100_000
			#endif
			let innerCount = 20
			var accumulator = 0
			for _ in 1...outerCount {
				var deque = ContiguousArray<Int>()
				for i in 1...innerCount {
					deque.append(i)
					accumulator ^= (deque.last ?? 0)
				}
				for _ in 1...innerCount {
					accumulator ^= (deque.first ?? 0)
					deque.remove(at: 0)
				}
			}
			XCTAssert(accumulator == 0)
		}
	}
}
