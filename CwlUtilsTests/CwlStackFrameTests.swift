//
//  CwlStackFrameTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/02/26.
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

class StackFrameTests: XCTestCase {
	func testCallStackReturnAddresses() {
		var a = callStackReturnAddresses()
		a.remove(at: 0)
		var b = Thread.callStackReturnAddresses.map { UInt($0) }
		b.remove(at: 0)
		XCTAssert(a == b)
		
		a = callStackReturnAddresses(skip: 2)
		b.remove(at: 0)
		XCTAssert(a == b)
		
		a = callStackReturnAddresses(skip: 2, maximumAddresses: 10)
		XCTAssert(a == Array(b[0..<10]))
	}
	
	func testNSThreadCallStackReturnAddressesPerformance() {
		measure {
			var traces = [[NSNumber]]()
			for _ in 0..<1000 {
				traces.append(Thread.callStackReturnAddresses)
			}
		}
	}
	
	func testCallStackReturnAddressesPerformance() {
		measure {
			var traces = [[UInt]]()
			for _ in 0..<1000 {
				traces.append(callStackReturnAddresses())
			}
		}
	}
}
