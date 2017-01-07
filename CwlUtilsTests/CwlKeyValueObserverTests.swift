//
//  CwlKeyValueObserverTests.swift
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

class TestObservable: NSObject {
	dynamic var someProperty: String
	dynamic var unrelatedProperty: NSNumber
	dynamic weak var weakProperty: TestObservable?
	dynamic var chainedObservable: TestObservable?
	
	init(value: String) {
		someProperty = value
		unrelatedProperty = false
		super.init()
	}
}

class KeyValueObserverTests: XCTestCase {
	func testBasicProperty() {
		var results: [(String?, KeyValueObserver.CallbackReason)] = Array()
		var kvo2Count = 0
		var testObservable1: TestObservable? = TestObservable(value: "empty")
		var kvo: KeyValueObserver?
		var kvo2: KeyValueObserver?
		
		if let to1 = testObservable1 {
			kvo = KeyValueObserver(source: to1, keyPath: #keyPath(TestObservable.someProperty), options: NSKeyValueObservingOptions.new) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				results.append(change[NSKeyValueChangeKey.newKey] as? String, reason)
			}
		}
		
		if let to1 = testObservable1 {
			kvo2 = KeyValueObserver(source: to1, keyPath: #keyPath(TestObservable.someProperty), options: NSKeyValueObservingOptions()) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				kvo2Count += 1
			}
		}
		
		// Test basic observer notifications
		testObservable1?.someProperty = "filled"
		
		// Test source deleted notification
		testObservable1 = nil
		
		XCTAssert(results[0].0 == "filled" && results[0].1 == .valueChanged)
		XCTAssert(results[1].0 == nil && results[1].1 == .sourceDeleted)
		XCTAssert(results.count == 2)

		XCTAssert(kvo2Count == 2)
		
		withExtendedLifetime(kvo) {}
		withExtendedLifetime(kvo2) {}
	}
	
	func testCancel() {
		var results: [(String?, KeyValueObserver.CallbackReason)] = Array()
		let testObservable = TestObservable(value: "empty")
		let kvo = KeyValueObserver(source: testObservable, keyPath: #keyPath(TestObservable.someProperty)) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				results.append(change[NSKeyValueChangeKey.newKey] as? String, reason)
		}
		
		testObservable.someProperty = "one"
		kvo.cancel()
		testObservable.someProperty = "two"
		
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.0 == "empty" && results.at(0)?.1 == .valueChanged)
		XCTAssert(results.at(1)?.0 == "one" && results.at(1)?.1 == .valueChanged)
	}
	
	func testChainedProperty() {
		var results: [(String?, KeyValueObserver.CallbackReason)] = Array()
		var testObservable1: TestObservable? = TestObservable(value: "one")
		let testObservable2: TestObservable? = TestObservable(value: "two")
		let testObservable3: TestObservable? = TestObservable(value: "three")
		let testObservable4: TestObservable? = TestObservable(value: "four")
		var kvo: KeyValueObserver?
		
		if let to1 = testObservable1, let to2 = testObservable2, let to3 = testObservable3 {
			to2.chainedObservable = to3
			to1.chainedObservable = to2
			kvo = KeyValueObserver(source: to1, keyPath: "chainedObservable.chainedObservable.someProperty", options: NSKeyValueObservingOptions.new) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				results.append(change[NSKeyValueChangeKey.newKey] as? String, reason)
			}
		}
		
		// Test key path observer notifications
		testObservable3?.someProperty = "filled"
		XCTAssert(results[0].0 == "filled" && results[0].1 == .valueChanged)
		
		// Test various combinations of path changes
		testObservable2?.chainedObservable = testObservable4
		XCTAssert(results[1].0 == "four" && results[1].1 == .pathChanged)
		
		testObservable4?.someProperty = "cleared"
		XCTAssert(results[2].0 == "cleared" && results[2].1 == .valueChanged)
		
		testObservable2?.chainedObservable = nil
		XCTAssert(results[3].0 == nil && results[3].1 == .pathChanged)
		
		testObservable2?.chainedObservable = testObservable3
		XCTAssert(results[4].0 == "filled" && results[4].1 == .pathChanged)
		
		testObservable2?.chainedObservable = nil
		XCTAssert(results[5].0 == nil && results[5].1 == .pathChanged)
		
		testObservable1 = nil
		XCTAssert(results[6].0 == nil && results[6].1 == .sourceDeleted)
		XCTAssert(results.count == 7)
		
		withExtendedLifetime(kvo) { () -> Void in }
	}
	
	func testWeakPropertyNotifications() {
		var results: [(String?, KeyValueObserver.CallbackReason)] = Array()
		let testObservable1: TestObservable? = TestObservable(value: "empty")
		var kvo: KeyValueObserver?
		
		if let to1 = testObservable1 {
			kvo = KeyValueObserver(source: to1, keyPath: "weakProperty", options: NSKeyValueObservingOptions.new) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				results.append(((change[NSKeyValueChangeKey.newKey] as? TestObservable)?.someProperty, reason))
			}
		}
		
		autoreleasepool() {
			var to2: TestObservable? = TestObservable(value: "monkey")
			testObservable1?.weakProperty = to2
			XCTAssert(results[0].0 == "monkey" && results[0].1 == .valueChanged)
			to2 = nil
		}
		
		XCTAssert(results[1].0 == nil && results[1].1 == .valueChanged)
		XCTAssert(results.count == 2)
		
		withExtendedLifetime(kvo!) { () -> Void in }
	}
	
	func testChangeOptions() {
		var results: [[AnyHashable: Any]] = Array()
		let options: [NSKeyValueObservingOptions] = [NSKeyValueObservingOptions(), NSKeyValueObservingOptions.new, NSKeyValueObservingOptions.old, [NSKeyValueObservingOptions.initial, NSKeyValueObservingOptions.new], [NSKeyValueObservingOptions.prior, NSKeyValueObservingOptions.new, NSKeyValueObservingOptions.old]]
		
		for o in options {
			let testObservable1 = TestObservable(value: "empty")
			let testObservable2 = TestObservable(value: "empty")
			let testObservable3 = TestObservable(value: "empty")
			testObservable1.chainedObservable = testObservable2
			testObservable2.chainedObservable = testObservable3
			let kvo = KeyValueObserver(source: testObservable1, keyPath: "chainedObservable.chainedObservable.someProperty", options: o) { (change: [NSKeyValueChangeKey: Any], reason: KeyValueObserver.CallbackReason) -> Void in
				results.append(change)
			}
			
			// Test basic observer notifications
			testObservable3.someProperty = "filled"
			
			// Cancel to avoid TargetDeleted notifications
			kvo.cancel()
		}
		
		XCTAssert(results.count == 7)
		
		// allZeros
		XCTAssert(Set<AnyHashable>(results[0].keys) == [NSKeyValueChangeKey.kindKey])
		
		// New
		XCTAssert(Set<AnyHashable>(results[1].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.newKey])
		
		// Old
		XCTAssert(Set<AnyHashable>(results[2].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.oldKey])
		
		// Initial
		XCTAssert(Set<AnyHashable>(results[3].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.newKey])
		
		// Initial, Setting
		XCTAssert(Set<AnyHashable>(results[4].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.newKey])
		
		// Prior (prior)
		XCTAssert(Set<AnyHashable>(results[5].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.notificationIsPriorKey, NSKeyValueChangeKey.oldKey])
		
		// Prior (post)
		XCTAssert(Set<AnyHashable>(results[6].keys) == [NSKeyValueChangeKey.kindKey, NSKeyValueChangeKey.newKey, NSKeyValueChangeKey.oldKey])
	}
}
