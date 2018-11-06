//
//  CwlSignalCocoaTests.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 12/31/16.
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
import CwlSignal
import XCTest

#if SWIFT_PACKAGE
import CwlUtils
#endif

class Target: NSObject {
	@objc dynamic var property = NSObject()
	@objc dynamic var intProperty: Int = 5
}

class Sender: NSObject {
	weak var target: AnyObject?
	var action: Selector?
	var doubleAction: Selector?
	
	func sendSingle() {
		guard let t = target, let a = action else { return }
		
		// Look the function up using the Obj-C runtime and call it directly. It's the closest that we can get in pure Swift to "performSelector".
		var imp = class_getMethodImplementation(object_getClass(t), a)!
		withUnsafePointer(to: &imp) { opaquePtr in
			typealias actionFunction = @convention(c) (AnyObject, Selector, Any?) -> Void
			opaquePtr.withMemoryRebound(to: actionFunction.self, capacity: 1) { actionFunctionPtr in
				actionFunctionPtr.pointee(t, a, "Hello")
			}
		}
	}
	
	func sendDouble() {
		guard let t = target, let a = doubleAction else { return }
		
		// Look the function up using the Obj-C runtime and call it directly. It's the closest that we can get in pure Swift to "performSelector".
		var imp = class_getMethodImplementation(object_getClass(t), a)!
		withUnsafePointer(to: &imp) { opaquePtr in
			typealias actionFunction = @convention(c) (AnyObject, Selector, Any?) -> Void
			opaquePtr.withMemoryRebound(to: actionFunction.self, capacity: 1) { actionFunctionPtr in
				actionFunctionPtr.pointee(t, a, "World")
			}
		}
	}
}

class SignalCocoaTests: XCTestCase {
	func testSignalKeyValueObserving() {
		var target: Target? = Target()
		target?.intProperty = 123
		var results = [Result<Int>]()
		let output = Signal.keyValueObserving(target!, keyPath: \.intProperty).subscribe { result in
			results.append(result)
		}
		
		target?.intProperty = 456
		target = nil
		
		XCTAssert(results.count == 2)
		XCTAssert(results.at(0)?.value == 123)
		XCTAssert(results.at(1)?.value == 456)
		
		withExtendedLifetime(output) {}
	}
	
	func testSignalActionTarget() {
		weak var weakSat: SignalActionTarget? = nil
		weak var weakSender: Sender? = nil
		var results = [String]()
		do {
			let sen = Sender()
			weakSender = sen
			do {
				var output: SignalOutput<String>? = nil
				do {
					let sat = SignalActionTarget()
					weakSat = sat
					
					sen.target = sat
					sen.action = SignalActionTarget.selector
					
					output = sat.signal.compactMap { $0 as? String }.subscribeValues { v in results.append(v) }
					
					sen.sendSingle()
				}
				
				XCTAssert(weakSender != nil)
				XCTAssert(weakSat != nil)
				output?.cancel()
			}
			XCTAssert(weakSat == nil)
			XCTAssert(sen.action == #selector(SignalActionTarget.cwlSignalAction(_:)))
			XCTAssert(sen.target == nil)
		}
		
		XCTAssert(results == ["Hello"])
	}
	
	func testSignalDoubleActionTarget() {
		let sat = SignalDoubleActionTarget()
		var results1 = [String]()
		var results2 = [String]()
		let ep1 = sat.signal.compactMap { $0 as? String }.subscribeValues { v in results1.append(v) }
		let ep2 = sat.secondSignal.compactMap { $0 as? String }.subscribeValues { v in results2.append(v) }
		let sel1 = SignalActionTarget.selector
		let sel2 = SignalDoubleActionTarget.secondSelector
		
		// Look the function up using the Obj-C runtime and call it directly. It's the closest that we can get in pure Swift to "performSelector".
		var imp1 = class_getMethodImplementation(SignalDoubleActionTarget.self, sel1)!
		withUnsafePointer(to: &imp1) { opaquePtr in
			typealias actionFunction = @convention(c) (AnyObject, Selector, Any?) -> Void
			opaquePtr.withMemoryRebound(to: actionFunction.self, capacity: 1) { actionFunctionPtr in
				actionFunctionPtr.pointee(sat, sel1, "Hello")
			}
		}
		var imp2 = class_getMethodImplementation(SignalDoubleActionTarget.self, sel2)!
		withUnsafePointer(to: &imp2) { opaquePtr in
			typealias actionFunction = @convention(c) (AnyObject, Selector, Any?) -> Void
			opaquePtr.withMemoryRebound(to: actionFunction.self, capacity: 1) { actionFunctionPtr in
				actionFunctionPtr.pointee(sat, sel2, "World")
			}
		}
		
		XCTAssert(results1 == ["Hello"])
		XCTAssert(results2 == ["World"])
		ep1.cancel()
		ep2.cancel()
	}
	
	func testSignalFromNotifications() {
		let source = NSObject()
		var results = [String]()
		let out = Signal.notifications(object: source).subscribeValues { v in
			results.append("\(v.name)")
		}
		NotificationCenter.default.post(name: Notification.Name.NSThreadWillExit, object: source)
		NotificationCenter.default.post(name: Notification.Name.NSFileHandleDataAvailable, object: source)
		XCTAssert(results == ["\(Notification.Name.NSThreadWillExit)", "\(Notification.Name.NSFileHandleDataAvailable)"])
		out.cancel()
	}
	
//	func testViewControllerTest() {
//		let e = expectation(description: "Waiting")
//		let latestSelection = FileSelection.currentSelection
//			.flatMapLatest { possible in possible.selection }
//			.continuous()
//		
//		var count = 0
//		let lifetime = latestSelection.subscribeValues(context: .main) { value in
//			print(value)
//			count += 1
//			if count == 100 {
//				e.fulfill()
//			}
//		}
//		
//		withExtendedLifetime(lifetime) {
//			waitForExpectations(timeout: 1e2) { e in
//			}
//		}
//	}
}

class FileSelection {
	let offset: Int
	init(offset: Int) { self.offset = offset }
	
	lazy var selection: Signal<Int> = Signal
		.interval(.milliseconds(100))
		.map { v in 1000 * self.offset + v }
		.continuous(initialValue: 0)
	
	static let currentSelection: Signal<FileSelection> = Signal
		.interval(.seconds(1), context: .main)
		.map { v in FileSelection(offset: v) }
		.continuous(initialValue: FileSelection(offset: 0))
}
