//
//  CwlExecTests.swift
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

class ExecTests: XCTestCase {
	func testDirect() {
		XCTAssert(Exec.direct.type.isConcurrent == true)
		XCTAssert(Exec.direct.type.isImmediate == true)
		
		var x = false
		Exec.direct.invoke { x = true }
		XCTAssert(x, "Block ran")
		
		var y = false
		Exec.direct.invokeAndWait { y = true }
		XCTAssert(y, "Block ran")
		
		let e2 = expectation(description: "Block 2 not invoked")
		Exec.direct.invokeAsync { e2.fulfill() }
		
		waitForExpectations(timeout: 1e1, handler: nil)
		
		let serialized = Exec.direct.serialized()
		if case .custom = serialized {
		} else {
			XCTFail()
		}
	}
	
	func testMain() {
		XCTAssert(Thread.current == Thread.main)
		XCTAssert(Exec.main.type.isConcurrent == false)
		XCTAssert(Exec.main.type.isImmediate == true)
		
		let e3 = expectation(description: "Block not invoked")
		Exec.global.invoke {
			XCTAssert(Exec.main.type.isImmediate == false)

			let lock = DispatchQueue(label: "")
			var x = false
			lock.sync {
				Exec.main.invoke {
					lock.sync {	x = true }
				}
				XCTAssert(!x, "Block should not yet run")
			}

			var y = false
			Exec.main.invokeAndWait { y = true }
			XCTAssert(y, "Block ran")

			e3.fulfill()
		}
		
		var x = false
		Exec.main.invoke { x = true }
		XCTAssert(x, "Block ran")
		
		var y = false
		Exec.main.invokeAndWait { y = true }
		XCTAssert(y, "Block ran")
		
		let e2 = expectation(description: "Block not invoked")
		Exec.main.invokeAsync { e2.fulfill() }
		
		waitForExpectations(timeout: 1e1, handler: nil)
		
		let serialized = Exec.main.serialized()
		if case .main = serialized {
		} else {
			XCTFail()
		}
	}
	
	func testMainAsync() {
		XCTAssert(Exec.mainAsync.type.isConcurrent == false)
		XCTAssert(Exec.mainAsync.type.isImmediate == false)
		
		let e1 = expectation(description: "Block not invoked")
		var run1 = false
		Exec.mainAsync.invoke {
			run1 = true
			e1.fulfill()
		}
		XCTAssert(run1 == false)
		
		var run2 = false
		Exec.mainAsync.invokeAndWait { run2 = true }
		XCTAssert(run2 == true)
		
		let e5 = expectation(description: "Block not invoked")
		Exec.global.invoke {
			let lock = DispatchQueue(label: "")
			var x = false
			lock.sync {
				Exec.mainAsync.invoke {
					lock.sync {	x = true }
				}
			}
			XCTAssert(!x, "Block should not yet run")

			var y = false
			Exec.mainAsync.invokeAndWait { y = true }
			XCTAssert(y, "Block ran")

			Exec.mainAsync.invokeAndWait {
				e5.fulfill()
			}
		}
		
		let e4 = expectation(description: "Block not invoked")
		var run3 = false
		Exec.mainAsync.invoke {
			run3 = true
			e4.fulfill()
		}
		XCTAssert(run3 == false)
		
		waitForExpectations(timeout: 1e1, handler: nil)
		
		let serialized = Exec.mainAsync.serialized()
		if case .mainAsync = serialized {
		} else {
			XCTFail()
		}
	}
	
	func testQueue() {
		let (ec1, sk1) = Exec.syncQueueWithSpecificKey()
		XCTAssert(ec1.type.isConcurrent == false)
		XCTAssert(ec1.type.isImmediate == true)
		
		let (ec2, sk2) = Exec.asyncQueueWithSpecificKey()
		XCTAssert(ec2.type.isConcurrent == false)
		XCTAssert(ec2.type.isImmediate == false)
		
		var a = false
		ec1.invoke() {
			XCTAssert(DispatchQueue.getSpecific(key: sk1) != nil)
			a = true
		}
		XCTAssert(a)
		
		let x1 = expectation(description: "Block not invoked")
		ec2.invoke() {
			XCTAssert(DispatchQueue.getSpecific(key: sk2) != nil)
			x1.fulfill()
		}
		
		let x2 = expectation(description: "Block 2 not invoked")
		ec1.invokeAsync() {
			XCTAssert(DispatchQueue.getSpecific(key: sk1) != nil)
			x2.fulfill()
		}
		
		let x3 = expectation(description: "Block 3 not invoked")
		ec2.invokeAsync() {
			XCTAssert(DispatchQueue.getSpecific(key: sk2) != nil)
			x3.fulfill()
		}
		
		var y1 = false
		ec1.invokeAndWait() {
			XCTAssert(DispatchQueue.getSpecific(key: sk1) != nil)
			y1 = true
		}
		XCTAssert(y1)
		
		var y2 = false
		ec2.invokeAndWait() {
			XCTAssert(DispatchQueue.getSpecific(key: sk2) != nil)
			y2 = true
		}
		XCTAssert(y2)
		
		waitForExpectations(timeout: 1e1, handler: nil)
		
		let serialized = ec1.serialized()
		if case .custom = serialized {
		} else {
			XCTFail()
		}
	}
	
	func testGlobal() {
		let variants: [Exec] = [.interactive, .user, .global, .utility, .background]
		let expectations1: [XCTestExpectation] = variants.map({ v in self.expectation(description: "Block \(v), 1 not invoked") })
		let expectations2: [XCTestExpectation] = variants.map({ v in self.expectation(description: "Block \(v), 2 not invoked") })
		for (i, variant) in variants.enumerated() {
			variant.invoke { expectations1[i].fulfill() }
			variant.invokeAsync { expectations2[i].fulfill() }
			XCTAssert(variant.type.isConcurrent == true)
			XCTAssert(variant.type.isImmediate == false)
			
			var x = false
			variant.invokeAndWait { x = true }
			XCTAssert(x)

			let serialized = variant.serialized()
			if case .custom = serialized {
			} else {
				XCTFail()
			}
		}
		waitForExpectations(timeout: 1e1, handler: nil)
	}
}
