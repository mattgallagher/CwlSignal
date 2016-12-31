//
//  CwlSignalCocoaTests.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 12/31/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import Foundation
import CwlSignal
import XCTest

class Target: NSObject {
	dynamic var property = NSObject()
	init(property: NSObject) {
		self.property = property
	}
}

class SignalCocoaTests: XCTestCase {
	func testSignalKeyValueObserving() {
		var target: Target? = Target(property: NSNumber(integerLiteral: 123))
		var results = [Result<Any>]()
		let endpoint = signalKeyValueObserving(target!, keyPath: #keyPath(Target.property)).subscribe { result in
			results.append(result)
		}
		
		target?.property = NSNumber(integerLiteral: 456)
		target = nil
		
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value as? NSNumber == NSNumber(integerLiteral: 123))
		XCTAssert(results.at(1)?.value as? NSNumber == NSNumber(integerLiteral: 456))
		XCTAssert(results.at(2)?.error as? SignalError == .closed)
		
		withExtendedLifetime(endpoint) {}
	}

	func testKeyValueObserving() {
		var target: Target? = Target(property: NSNumber(integerLiteral: 123))
		var results = [Result<NSNumber>]()
		let endpoint = Signal<NSNumber>.keyValueObserving(target!, keyPath: #keyPath(Target.property)).subscribe { result in
			results.append(result)
		}
		
		target?.property = NSNumber(integerLiteral: 456)
		target = nil
		
		XCTAssert(results.count == 3)
		XCTAssert(results.at(0)?.value == NSNumber(integerLiteral: 123))
		XCTAssert(results.at(1)?.value == NSNumber(integerLiteral: 456))
		XCTAssert(results.at(2)?.error as? SignalError == .closed)
		
		withExtendedLifetime(endpoint) {}
	}
}
