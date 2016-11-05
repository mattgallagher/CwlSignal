//
//  CwlMutexTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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

class PthreadTests: XCTestCase {
	func testPthreadMutex() {
		let mutex1 = PThreadMutex()
		
		let e1 = expectation(description: "Block1 not invoked")
		mutex1.sync {
			e1.fulfill()
			let reenter: Void? = mutex1.trySync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
		}
		
		let mutex2 = PThreadMutex(type: .recursive)
		
		let e2 = expectation(description: "Block2 not invoked")
		let e3 = expectation(description: "Block3 not invoked")
		mutex2.sync {
			e2.fulfill()
			let reenter: Void? = mutex2.trySync() {
				e3.fulfill()
			}
			XCTAssert(reenter != nil)
		}
		
		let e4 = expectation(description: "Block4 not invoked")
		let r = mutex1.sync { n -> Int in
			e4.fulfill()
			let reenter: Void? = mutex1.trySync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
			return 13
		}
		XCTAssert(r == 13)
		
		waitForExpectations(timeout: 0, handler: nil)
	}
}

extension PThreadMutex {
	public func sync_2<T>(_ param: inout T, f: (inout T) throws -> Void) rethrows -> Void {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		try f(&param)
	}
	public func sync_3<T, R>(_ param: inout T, f: (inout T) throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f(&param)
	}
	public func sync_4<T, U>(_ param1: inout T, _ param2: inout U, f: (inout T, inout U) throws -> Void) rethrows -> Void {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f(&param1, &param2)
	}
}

