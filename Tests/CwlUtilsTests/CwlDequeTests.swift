//
//  CwlDequeTests.swift
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

class DequeTests: XCTestCase {
	func testAppend() {
		var deque = Deque<Result<Int>>()
		for i in 1...100 {
			deque.append(.success(i))
		}
		XCTAssert(deque.count == 100)
		
		for i in 1...2_000 {
			deque.remove(at: 0)
			deque.append(.success(i))
		}
		for i in 1...2_000 {
			deque.remove(at: deque.count - 1)
			deque.insert(.success(i), at: 0)
		}
		
		var i = 0
		while deque.count > 0 {
			deque.remove(at: 0)
			i += 1
		}
		XCTAssert(i == 100)
	}
	
	func testRemoveFirst() {
		var deque = Deque<Result<Int>>()
		deque.append(.success(1))
		deque.append(.success(3))
		deque.append(.success(5))
		deque.append(.success(7))
		deque.append(.success(11))

		XCTAssert(deque.removeFirst().value == 1)
		XCTAssert(deque.removeFirst().value == 3)

		deque.append(.success(13))
		deque.append(.success(17))
		deque.append(.success(19))
		deque.append(.success(23))
		
		XCTAssert(deque[4].value == 17)
		
		XCTAssert(deque.removeFirst().value == 5)

		deque.append(.success(29))
		
		XCTAssert(deque.removeFirst().value == 7)
		XCTAssert(deque.removeFirst().value == 11)
		XCTAssert(deque.removeFirst().value == 13)

		deque.append(.success(31))
		deque.append(.success(37))
		deque.append(.success(41))
		deque.append(.success(43))
		XCTAssert(deque.removeFirst().value == 17)
		
		XCTAssert(deque.count == 7)
	}
	
	func testAdvancingRemoveInsert() {
		var deque: Deque<Int> = [0, 1, 2]
		deque.remove(at: 0)
		XCTAssert(Array(deque) == [1, 2])
		deque.insert(3, at: 2)
		XCTAssert(Array(deque) == [1, 2, 3])
		deque.remove(at: 0)
		XCTAssert(Array(deque) == [2, 3])
		deque.insert(4, at: 2)
		XCTAssert(Array(deque) == [2, 3, 4])
		deque.remove(at: 0)
		XCTAssert(Array(deque) == [3, 4])
		deque.insert(5, at: 2)
		XCTAssert(Array(deque) == [3, 4, 5])
		
		XCTAssert(deque[0] == 3)
		XCTAssert(deque[1] == 4)
		XCTAssert(deque[2] == 5)
	}
	
	func testRegressingRemoveInsert() {
		var deque: Deque<Int> = [0, 1, 2]
		deque.remove(at: 2)
		XCTAssert(Array(deque) == [0, 1])
		deque.insert(-1, at: 0)
		XCTAssert(Array(deque) == [-1, 0, 1])
		deque.remove(at: 2)
		XCTAssert(Array(deque) == [-1, 0])
		deque.insert(-2, at: 0)
		XCTAssert(Array(deque) == [-2, -1, 0])
		deque.remove(at: 2)
		XCTAssert(Array(deque) == [-2, -1])
		deque.insert(-3, at: 0)
		XCTAssert(Array(deque) == [-3, -2, -1])
		
		XCTAssert(deque[0] == -3)
		XCTAssert(deque[1] == -2)
		XCTAssert(deque[2] == -1)
	}
	
	func testRangeReplacing() {
		var deque: Deque<Int> = [0, 1, 2]
		deque.replaceSubrange(1..<1, with: [3, 4, 5, 6, 7, 8])
		XCTAssert(Array(deque) == [0, 3, 4, 5, 6, 7, 8, 1, 2])
		
		deque.replaceSubrange(4..<6, with: [9, 10, 11, 12, 13])
		XCTAssert(Array(deque) == [0, 3, 4, 5, 9, 10, 11, 12, 13, 8, 1, 2])
		
		deque.replaceSubrange(9..<12, with: [14])
		XCTAssert(Array(deque) == [0, 3, 4, 5, 9, 10, 11, 12, 13, 14])
		
		deque.replaceSubrange(0..<8, with: [15, 16])
		XCTAssert(Array(deque) == [15, 16, 13, 14])
	}
}
