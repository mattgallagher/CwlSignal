//
//  CwlUnanticipatedErrorTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/03/05.
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

enum TestCode: Int, ErrorProtocol {
	case ZeroValue = 0
	case OneValue = 1
	case TestValue = 2
}

class UnanticipatedErrorTests: XCTestCase {
	func testUnanticipatedError() {
		let e = TestCode.TestValue.withUnanticipatedErrorRecoveryAttempter()
		
		// NOTE: error codes equal raw values only if the raw values are zero based with no gaps
		XCTAssert(e.code == TestCode.TestValue.rawValue)
		
		let userInfo = e.userInfo
		if let callStackSymbols = userInfo[UnanticipatedErrorRecoveryAttempter.ReturnAddressesKey] as? [UInt] {
			XCTAssert(callStackSymbols.count > 1, "No call stack symbols present")
		} else {
			XCTFail("Call stack symbols not present")
		}

		XCTAssertNotNil(userInfo[NSLocalizedRecoverySuggestionErrorKey])
		XCTAssertNotNil(userInfo[NSLocalizedRecoveryOptionsErrorKey])
		XCTAssertNotNil(userInfo[NSRecoveryAttempterErrorKey])
		
		XCTAssert(userInfo[NSLocalizedRecoveryOptionsErrorKey]?.count == 2, "Wrong number of options")

		let attempter = userInfo[NSRecoveryAttempterErrorKey] as? NSObject
		let backup = pasteboardBackup()
		attempter?.attemptRecovery(fromError: e as NSError, optionIndex: 1)
		let clipboardString = pasteboardString()

		// The following (ugly) compile-time conditional is a best effort at testing for the simulator (no actual simulator macro is provided)
	#if !os(iOS) || (!arch(i386) && !arch(x86_64))
		XCTAssert(clipboardString?.range(of: e.localizedRecoverySuggestion!) != nil)
	#else
		// Logic tests in the simulator don't appear to have access to a real UIPasteboard so we expect a failure here
		XCTAssertFalse(clipboardString?.range(of: e.localizedRecoverySuggestion!) != nil, "Simulator pasteboard expected to fail")
	#endif

		restorePasteboard(items: backup)
	}
}

#if os(iOS)

func pasteboardBackup() -> [Dictionary<String, NSObject>] {
	return ((UIPasteboard.generalPasteboard().items as NSArray).copy() as? [Dictionary<String, NSObject>]) ?? Array<Dictionary<String, NSObject>>()
}

func restorePasteboard(items: [Dictionary<String, NSObject>]) {
	UIPasteboard.generalPasteboard().items = items
}

func pasteboardString() -> String? {
	return UIPasteboard.generalPasteboard().string
}

#else

func pasteboardBackup() -> [NSPasteboardItem] {
	return NSPasteboard.general().pasteboardItems?.map { item in
		let backupItem = NSPasteboardItem()
		for type in item.types {
			if let data = item.data(forType: type)?.copy() as? NSData {
				backupItem.setData(data, forType:type)
			}
		}
		return backupItem
	} ?? []
}

func restorePasteboard(items: [NSPasteboardItem]) {
	NSPasteboard.general().clearContents()
	NSPasteboard.general().writeObjects(items)
}

func pasteboardString() -> String? {
	return NSPasteboard.general().string(forType: NSPasteboardTypeString)
}

#endif
