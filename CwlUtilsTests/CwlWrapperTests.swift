//
//  CwlWrapperTests.swift
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

class WrapperTests: XCTestCase {
	func testBox() {
		let b = Box(5)
		XCTAssert(b.value == 5)
	}
	
	func testAtomicBox() {
		let a = AtomicBox(5)
		let b = a
		a.value = 3
		XCTAssert(a.value == 3 && b.value == 3)
	}
	
	func testWeak() {
		let q = NSObject()
		let w = { () -> Weak<NSObject> in
			let o = NSObject()
			let p = NSObject()
			let innerW = Weak(o)
			XCTAssert(innerW.value != nil)
			XCTAssert(innerW.contains(o))
			XCTAssert(!innerW.contains(p))
			return innerW
		}()
		XCTAssert(w.value == nil)
		XCTAssert(!w.contains(q))
	}
	
	func testUnownedWrapper() {
		var uow: Unowned<NSObject>? = nil
		let w = { () -> Weak<NSObject> in
			let o = NSObject()
			let innerW = Weak(o)
			uow = Unowned(o)
			XCTAssert(innerW.value != nil)
			XCTAssert(uow != nil)
			XCTAssert(uow!.value == o)
			return innerW
		}()
		XCTAssert(w.value == nil)
		XCTAssert(uow != nil)
	}
	
	func testPossiblyWeak() {
		let q = NSObject()
		let w = { () -> PossiblyWeak<NSObject> in
			let o = NSObject()
			let p = NSObject()
			let innerW = PossiblyWeak.strong(o)
			XCTAssert(innerW.value != nil)
			XCTAssert(innerW.contains(o))
			XCTAssert(!innerW.contains(p))
			return innerW
		}()
		XCTAssert(w.value != nil)
		XCTAssert(!w.contains(q))
		
		let x = { () -> PossiblyWeak<NSObject> in
			let o = NSObject()
			let p = NSObject()
			let innerW = PossiblyWeak.weak(Weak(o))
			XCTAssert(innerW.value != nil)
			XCTAssert(innerW.contains(o))
			XCTAssert(!innerW.contains(p))
			return innerW
		}()
		XCTAssert(x.value == nil)
		XCTAssert(!x.contains(q))
	}
}
