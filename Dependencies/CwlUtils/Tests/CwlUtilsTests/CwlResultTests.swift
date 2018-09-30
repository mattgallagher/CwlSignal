//
//  CwlResultTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

class ResultTests: XCTestCase {
	func testInitWithClosure() {
		let r = Result<Int> {
			return 3
		}
		XCTAssert(r.value != nil)
		XCTAssert(r.error == nil)
		XCTAssert(r.value! == 3)
		
		let s = Result<Int> {
			throw TestError.oneValue
		}
		XCTAssert(s.value == nil)
		XCTAssert(s.error != nil)
	}
	
	func testInitWithValue() {
		let r = Result<Int>.success(3)
		XCTAssert(r.value != nil)
		XCTAssert(r.error == nil)
		XCTAssert(r.value! == 3)
		
		let s = Result<Int>.success(5)
		XCTAssert(r.value != nil)
		XCTAssert(r.error == nil)
		XCTAssert(s.value! == 5)
	}
	
	func testInitWithError() {
		let e1 = NSError(domain: "a", code: 5, userInfo: nil)
		let r = Result<Int>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		XCTAssert(r.value == nil)
		XCTAssert(r.error != nil)
		XCTAssert(r.error.map { $0 as NSError } == e1)
		
		let e2 = NSError(domain: "b", code: 7, userInfo: nil)
		let s = Result<Int>.failure(e2)
		XCTAssert(s.value == nil)
		XCTAssert(s.error.map { $0 as NSError } == e2)
	}
	
	func testFlatMap() {
		var x = false
		let a = Result<Int>.success(3)
		let c = a.flatMap() { (i: Int) -> Result<Int> in
			XCTAssert(i == 3)
			x = true
			return Result<Int>.success(5)
		}
		let v = c.value
		XCTAssert(v != nil && v! == 5)
		XCTAssert(x == true)
		
		var y = false
		let b = Result<Int>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		let d = b.flatMap() { (i: Int) -> Result<Int> in
			y = true
			return Result<Int>.success(5)
		}
		let w = d.value
		XCTAssert(w == nil)
		XCTAssert(y == false)
		
		let s = Result<Int>.success(3)
		let r = s.map { (i: Int) throws -> Bool in
			throw TestError.oneValue
		}
		XCTAssert(r.error != nil)
	}
	
	func testMap() {
		var x = false
		let a = Result<Int>.success(3)
		let c = a.map() { (i: Int) -> Int in
			XCTAssert(i == 3)
			x = true
			return 5
		}
		let v = c.value
		XCTAssert(v != nil && v! == 5)
		XCTAssert(x == true)
		
		var y = false
		let b = Result<Int>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		let d = b.map() { (i: Int) -> Int in
			y = true
			return 5
		}
		let w = d.value
		XCTAssert(w == nil)
		XCTAssert(y == false)
	}
	
	func testUnwrap() {
		var e: Error?
		var i: Int?
		do {
			i = try Result<Int>.success(3).unwrap()
		} catch {
			e = error
		}
		XCTAssert(i != nil)
		XCTAssert(e == nil)
		
		var f: Error?
		var j: Int?
		do {
			j = try Result<Int>.failure(TestError.oneValue).unwrap()
		} catch {
			f = error
		}
		XCTAssert(j == nil)
		XCTAssert(f != nil)
	}
}
