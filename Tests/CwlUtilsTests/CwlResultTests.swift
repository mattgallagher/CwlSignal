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
		let r = Result<Int, Error> {
			return 3
		}
		XCTAssert(r.success != nil)
		XCTAssert(r.failure == nil)
		XCTAssert(r.success! == 3)
		
		let s = Result<Int, Error> {
			throw TestError.oneValue
		}
		XCTAssert(s.success == nil)
		XCTAssert(s.failure != nil)
	}
	
	func testInitWithValue() {
		let r = Result<Int, Error>.success(3)
		XCTAssert(r.success != nil)
		XCTAssert(r.failure == nil)
		XCTAssert(r.success! == 3)
		
		let s = Result<Int, Error>.success(5)
		XCTAssert(r.success != nil)
		XCTAssert(r.failure == nil)
		XCTAssert(s.success! == 5)
	}
	
	func testInitWithError() {
		let e1 = NSError(domain: "a", code: 5, userInfo: nil)
		let r = Result<Int, Error>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		XCTAssert(r.success == nil)
		XCTAssert(r.failure != nil)
		XCTAssert(r.failure.map { $0 as NSError } == e1)
		
		let e2 = NSError(domain: "b", code: 7, userInfo: nil)
		let s = Result<Int, Error>.failure(e2)
		XCTAssert(s.success == nil)
		XCTAssert(s.failure.map { $0 as NSError } == e2)
	}
	
	func testFlatMap() {
		var x = false
		let a = Result<Int, Error>.success(3)
		let c = a.flatMap() { (i: Int) -> Result<Int, Error> in
			XCTAssert(i == 3)
			x = true
			return Result<Int, Error>.success(5)
		}
		let v = c.success
		XCTAssert(v != nil && v! == 5)
		XCTAssert(x == true)
		
		var y = false
		let b = Result<Int, Error>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		let d = b.flatMap() { (i: Int) -> Result<Int, Error> in
			y = true
			return Result<Int, Error>.success(5)
		}
		let w = d.success
		XCTAssert(w == nil)
		XCTAssert(y == false)
		
		let s = Result<Int, Error>.success(3)
		let r = s.mapThrows { (i: Int) throws -> Bool in
			throw TestError.oneValue
		}
		XCTAssert(r.failure != nil)
	}
	
	func testMap() {
		var x = false
		let a = Result<Int, Error>.success(3)
		let c = a.map() { (i: Int) -> Int in
			XCTAssert(i == 3)
			x = true
			return 5
		}
		let v = c.success
		XCTAssert(v != nil && v! == 5)
		XCTAssert(x == true)
		
		var y = false
		let b = Result<Int, Error>.failure(NSError(domain: "a", code: 5, userInfo: nil))
		let d = b.map() { (i: Int) -> Int in
			y = true
			return 5
		}
		let w = d.success
		XCTAssert(w == nil)
		XCTAssert(y == false)
	}
	
	func testUnwrap() {
		var e: Error?
		var i: Int?
		do {
			i = try Result<Int, Error>.success(3).unwrap()
		} catch {
			e = error
		}
		XCTAssert(i != nil)
		XCTAssert(e == nil)
		
		var f: Error?
		var j: Int?
		do {
			j = try Result<Int, Error>.failure(TestError.oneValue).unwrap()
		} catch {
			f = error
		}
		XCTAssert(j == nil)
		XCTAssert(f != nil)
	}
}
