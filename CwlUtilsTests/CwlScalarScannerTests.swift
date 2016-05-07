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

		var sc2 = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		XCTAssert(sc2.remainder() == "xyz")
	}

	func testMatchString() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			try sc.matchString("xy")
			try sc.matchString("za")
			XCTFail()
		} catch ScalarScannerError.MatchFailed(let wanted, let at) {
			XCTAssert(wanted == "za")
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}

	func testMatchScalar() {
		do {
			var sc = ScalarScanner(scalars: "x".unicodeScalars, context: ())
			try sc.matchScalar("x")
			try sc.matchScalar("y")
			XCTFail()
		} catch ScalarScannerError.MatchFailed(let wanted, let at) {
			XCTAssert(wanted == "y")
			XCTAssert(at == 1)
		} catch {
			XCTFail()
		}
	}

	func testReadUntil() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
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

	func testReadWhileTrue() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		let value = sc.readWhileTrue { $0 < "z"}
		XCTAssert(value == "xy")
		XCTAssert(sc.remainder() == "z")
	}

	func testSkipWhileTrue() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		sc.skipWhileTrue { $0 < "z"}
		XCTAssert(sc.remainder() == "z")
	}

	func testSkip() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			try sc.skip(1)
			try sc.skip(3)
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 3)
			XCTAssert(at == 1)
		} catch {
			XCTFail()
		}
	}

	func testBacktrack() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			try sc.matchString("xyz")
			try sc.backtrack()
			try sc.backtrack(2)
			try sc.backtrack(1)
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == -1)
			XCTAssert(at == 0)
		} catch {
			XCTFail()
		}
	}

	func testRemainder() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		XCTAssert((try? sc.matchString("x")) != nil)
		XCTAssert(sc.remainder() == "yz")
		XCTAssert(sc.remainder() == "")
	}

	func testConditionalString() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		XCTAssert(sc.conditionalString("xy"))
		XCTAssert(!sc.conditionalString("ab"))
		XCTAssert(sc.remainder() == "z")
	}

	func testConditionalScalar() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		XCTAssert(sc.conditionalScalar("x"))
		XCTAssert(!sc.conditionalScalar("a"))
		XCTAssert(sc.remainder() == "yz")
	}

	func testRequirePeek() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			XCTAssert(try sc.requirePeek() == "x")
			try sc.matchString("xyz")
			_ = try sc.requirePeek()
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testPeek() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		XCTAssert(sc.peek() == "x")
		XCTAssert((try? sc.matchString("xyz")) != nil)
		XCTAssert(sc.peek() == nil)
	}

	func testReadScalar() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			XCTAssert(try sc.readScalar() == "x")
			try sc.matchString("yz")
			_ = try sc.readScalar()
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testReadInt() {
		do {
			var sc = ScalarScanner(scalars: "123abc".unicodeScalars, context: ())
			XCTAssert(try sc.readInt() == 123)
			_ = try sc.readInt()
			XCTFail()
		} catch ScalarScannerError.ExpectedInt(let at) {
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}

	func testReadScalars() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
			XCTAssert(try sc.readScalars(2) == "xy")
			_ = try sc.readScalars(2)
			XCTFail()
		} catch ScalarScannerError.EndedPrematurely(let count, let at) {
			XCTAssert(count == 2)
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}

	func testUnexpectedError() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars, context: ())
		let e1 = sc.unexpectedError()
		sc.conditionalScalar("x")
		let e2 = sc.unexpectedError()
		switch (e1, e2) {
		case (ScalarScannerError.Unexpected(0), ScalarScannerError.Unexpected(1)): break
		default: XCTFail()
		}
	}
}
