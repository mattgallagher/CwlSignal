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
		var sc1 = ScalarScanner(scalars: ["a", "b", "c"])
		var sc2 = ScalarScanner(scalars: "xyz".unicodeScalars)
		XCTAssert(sc1.remainder() == "abc")
		XCTAssert(sc2.remainder() == "xyz")
	}
	
	func testMatchString() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			try sc.match(string: "xy")
			try sc.match(string: "za")
			XCTFail()
		} catch ScalarScannerError.matchFailed(let wanted, let at) {
			XCTAssert(wanted == "za")
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}
	
	func testMatchScalar() {
		do {
			var sc = ScalarScanner(scalars: "x".unicodeScalars)
			try sc.match(scalar: "x")
			try sc.match(scalar: "y")
			XCTFail()
		} catch ScalarScannerError.matchFailed(let wanted, let at) {
			XCTAssert(wanted == "y")
			XCTAssert(at == 1)
		} catch {
			XCTFail()
		}
	}
	
	func testReadUntilScalar() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			let s1 = try sc.readUntil(scalar: "y")
			XCTAssert(s1 == "x")
			_ = try sc.readUntil(scalar: "a")
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "a")
			XCTAssert(after == 1)
		} catch {
			XCTFail()
		}
	}
	
	func testReadUntilSet() {
		do {
			var sc = ScalarScanner(scalars: "uvwxyz . ABCD_*".unicodeScalars)
			let s1 = try sc.readUntil(set: Set(" .".unicodeScalars.sorted()))
			XCTAssertEqual(s1, "uvwxyz")
			let s2 = try sc.readUntil(set: Set(" .".unicodeScalars.sorted()))
			XCTAssertEqual(s2, "")
			let s3 = try sc.readUntil(set: Set("_%^&*".unicodeScalars.sorted()))
			XCTAssertEqual(s3, " . ABCD")
			let _ = try sc.readUntil(set: Set("ab".unicodeScalars.sorted()))
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "One of: [\"a\", \"b\"]")
			XCTAssert(after == 13)
		} catch {
			XCTFail()
		}
	}
	
	func testReadUntilString() {
		do {
			var sc = ScalarScanner(scalars: "uvwxyz".unicodeScalars)
			let s1 = try sc.readUntil(string: "wx")
			let s2 = try sc.readUntil(string: "y")
			XCTAssert(s1 == "uv")
			XCTAssert(s2 == "wx")
			_ = try sc.readUntil(string: "za")
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "za")
			XCTAssert(after == 4)
		} catch {
			XCTFail()
		}
	}
	
	func testSkipUntilScalar() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			try sc.skipUntil(scalar: "y")
			try sc.skipUntil(scalar: "a")
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "a")
			XCTAssert(after == 1)
		} catch {
			XCTFail()
		}
	}
	
	func testSkipUntilString() {
		do {
			var sc = ScalarScanner(scalars: "uvwxyz".unicodeScalars)
			try sc.skipUntil(string: "wx")
			try sc.skipUntil(string: "y")
			try sc.skipUntil(string: "za")
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "za")
			XCTAssert(after == 4)
		} catch {
			XCTFail()
		}
	}
	
	func testSkipUntilSet() {
		do {
			var sc = ScalarScanner(scalars: "uvwxyz . ABCD_*".unicodeScalars)
			try sc.skipUntil(set: Set(" .".unicodeScalars.sorted()))
			try sc.skipUntil(set: Set(" .".unicodeScalars.sorted()))
			try sc.skipUntil(set: Set("_%^&*".unicodeScalars.sorted()))
			try sc.skipUntil(set: Set("ab".unicodeScalars.sorted()))
			XCTFail()
		} catch ScalarScannerError.searchFailed(let wanted, let after) {
			XCTAssert(wanted == "One of: [\"a\", \"b\"]")
			XCTAssert(after == 13)
		} catch {
			XCTFail()
		}
	}
	
	func testReadWhileTrue() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		let value = sc.readWhile { $0 < "z" }
		XCTAssert(value == "xy")
		XCTAssert(sc.remainder() == "z")
	}
	
	func testSkipWhileTrue() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		sc.skipWhile { $0 < "z" }
		XCTAssert(sc.remainder() == "z")
	}
	
	func testSkip() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			try sc.skip(count: 1)
			try sc.skip(count: 3)
			XCTFail()
		} catch ScalarScannerError.endedPrematurely(let count, let at) {
			XCTAssert(count == 3)
			XCTAssert(at == 1)
		} catch {
			XCTFail()
		}
	}
	
	func testBacktrack() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			try sc.match(string: "xyz")
			try sc.backtrack()
			try sc.backtrack(count: 2)
			try sc.backtrack(count: 1)
			XCTFail()
		} catch ScalarScannerError.endedPrematurely(let count, let at) {
			XCTAssert(count == -1)
			XCTAssert(at == 0)
		} catch {
			XCTFail()
		}
	}
	
	func testRemainder() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		XCTAssert((try? sc.match(string: "x")) != nil)
		XCTAssert(sc.remainder() == "yz")
		XCTAssert(sc.remainder() == "")
	}
	
	func testConditionalString() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		XCTAssert(sc.conditional(string: "xy"))
		XCTAssert(!sc.conditional(string: "ab"))
		XCTAssert(sc.remainder() == "z")
	}
	
	func testConditionalScalar() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		XCTAssert(sc.conditional(scalar: "x"))
		XCTAssert(!sc.conditional(scalar: "a"))
		XCTAssert(sc.remainder() == "yz")
	}
	
	func testRequirePeek() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			XCTAssert(try sc.requirePeek() == "x")
			try sc.match(string: "xyz")
			_ = try sc.requirePeek()
			XCTFail()
		} catch ScalarScannerError.endedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}
	
	func testPeek() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		XCTAssert(sc.peek() == "x")
		XCTAssert((try? sc.match(string: "xyz")) != nil)
		XCTAssert(sc.peek() == nil)
	}
	
	func testReadScalar() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			XCTAssert(try sc.readScalar() == "x")
			try sc.match(string: "yz")
			_ = try sc.readScalar()
			XCTFail()
		} catch ScalarScannerError.endedPrematurely(let count, let at) {
			XCTAssert(count == 1)
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}
	
	func testReadInt() {
		do {
			var sc = ScalarScanner(scalars: "123abc".unicodeScalars)
			XCTAssert(try sc.readInt() == 123)
			_ = try sc.readInt()
			XCTFail()
		} catch ScalarScannerError.expectedInt(let at) {
			XCTAssert(at == 3)
		} catch {
			XCTFail()
		}
	}
	
	func testReadScalars() {
		do {
			var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
			XCTAssert(try sc.readScalars(count: 2) == "xy")
			_ = try sc.readScalars(count: 2)
			XCTFail()
		} catch ScalarScannerError.endedPrematurely(let count, let at) {
			XCTAssert(count == 2)
			XCTAssert(at == 2)
		} catch {
			XCTFail()
		}
	}
	
	func testUnexpectedError() {
		var sc = ScalarScanner(scalars: "xyz".unicodeScalars)
		let e1 = sc.unexpectedError()
		_ = sc.conditional(scalar: "x")
		let e2 = sc.unexpectedError()
		switch (e1, e2) {
		case (ScalarScannerError.unexpected(0), ScalarScannerError.unexpected(1)): break
		default: XCTFail()
		}
	}
}
