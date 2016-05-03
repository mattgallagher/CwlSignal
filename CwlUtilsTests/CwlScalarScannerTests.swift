//
//  CwlScalarScannerTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/01/05.
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

class ScalarScannerTests: XCTestCase {
	func testConstruction() {
		var sc1 = ScalarScanner(scalars: ["a", "b", "c"], context: 1)
		XCTAssert(sc1.remainder() == "abc")
		XCTAssert(sc1.context == 1)

		var sc2 = ScalarScanner(string: "xyz", context: ())
		XCTAssert(sc2.remainder() == "xyz")
	}

	func testRequireMatch() {
		do {
			var sc = ScalarScanner(string: "xyz", context: ())
			try sc.requireMatch("xy")
			try sc.requireMatch("za")
			XCTFail()
		} catch ScalarScannerError.MatchFailed(let wanted, let at) {
			XCTAssert(wanted == "za")
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}

	func testReadUntil() {
		do {
			var sc = ScalarScanner(string: "xyz", context: ())
			try sc.readUntil("y")
			try sc.readUntil("a")
			XCTFail()
		} catch ScalarScannerError.SearchFailed(let wanted, let after) {
			XCTAssert(wanted == "a")
			XCTAssert(after == 1)
		} catch {
			XCTFail()
		}
	}

	func testSkipWhileTrue() {
		var sc = ScalarScanner(string: "xyz", context: ())
		sc.skipWhileTrue { $0 < "z"}
		XCTAssert(sc.remainder() == "z")
	}

	func testReadWhileTrue() {
		var sc = ScalarScanner(string: "xyz", context: ())
		let value = sc.readWhileTrue { $0 < "z"}
		XCTAssert(value == "xy")
		XCTAssert(sc.remainder() == "z")
	}

	func testConditionalString() {
		var sc = ScalarScanner(string: "xyz", context: ())
		XCTAssert(sc.conditionalString("xy"))
		XCTAssert(!sc.conditionalString("ab"))
		XCTAssert(sc.remainder() == "z")
	}

	func testConditionalScalar() {
		var sc = ScalarScanner(string: "xyz", context: ())
		XCTAssert(sc.conditionalScalar("x"))
		XCTAssert(!sc.conditionalScalar("a"))
		XCTAssert(sc.remainder() == "yz")
	}

	func testRequirePeek() {
		do {
			var sc = ScalarScanner(string: "xyz", context: ())
			XCTAssert(try sc.requirePeek() == "x")
			try sc.requireMatch("xyz")
			_ = try sc.requirePeek()
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testConditionalPeek() {
		var sc = ScalarScanner(string: "xyz", context: ())
		XCTAssert(sc.conditionalPeek() == "x")
		try! sc.requireMatch("xyz")
		XCTAssert(sc.conditionalPeek() == nil)
	}

	func testRequireScalar() {
		do {
			var sc = ScalarScanner(string: "xyz", context: ())
			XCTAssert(try sc.requireScalar() == "x")
			try sc.requireMatch("yz")
			_ = try sc.requireScalar()
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testRequireInt() {
		do {
			var sc = ScalarScanner(string: "123abc", context: ())
			XCTAssert(try sc.requireInt() == 123)
			_ = try sc.requireInt()
			XCTFail()
		} catch ScalarScannerError.ExpectedInt(let at) {
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testRequireScalars() {
		do {
			var sc = ScalarScanner(string: "xyz", context: ())
			XCTAssert(try sc.requireScalars(2) == "xy")
			_ = try sc.requireScalars(2)
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 2)
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}

	func testUnexpectedError() {
		var sc = ScalarScanner(string: "xyz", context: ())
		let e1 = sc.unexpectedError()
		sc.conditionalScalar("x")
		let e2 = sc.unexpectedError()
		switch (e1, e2) {
		case (ScalarScannerError.Unexpected(0), ScalarScannerError.Unexpected(1)): break
		default: XCTFail()
		}
	}
}
