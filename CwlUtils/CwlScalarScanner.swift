//
//  CwlScalarScanner.swift
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

import Swift

/// A type for representing the different possible failure conditions when using ScalarScanner
public enum ScalarScannerError: ErrorType {
	/// The scalar at the specified index doesn't match the expected grammar
	case Unexpected(at: Int)
	
	/// Expected `wanted` at offset `at`
	case MatchFailed(wanted: String, at: Int)
	
	/// Expected numerals at offset `at`
	case ExpectedInt(at: Int)
	
	/// Attempted to read `count` scalars from position `at` but hit the end of the sequence
	case EndedPrematurely(count: Int, at: Int)
	
	/// Unable to find search patter `wanted` at or after `after` in the sequence
	case SearchFailed(wanted: String, after: Int)
}

/// A structure for traversing a `String.UnicodeScalarView`. A `context` field is provided but is not used by the scanner (it is entirely for storage by the scanner's user).
public struct ScalarScanner<C: CollectionType, T where C.Generator.Element == UnicodeScalar, C.Index: BidirectionalIndexType, C.Index: Comparable> {
	// The underlying storage
	let scalars: C
	
	// Current scanning index
	var index: C.Index
	
	/// Entirely for user use
	public var context: T

	/// Construct from a String.UnicodeScalarView and a context value
	public init(scalars: C, context: T) {
		self.scalars = scalars
		self.index = self.scalars.startIndex
		self.context = context
	}
	
	// Private utility for getting the index as an Int (used in errors)
	var absoluteIndex: Int {
		var i = index
		var count = 0
		while i > scalars.startIndex {
			i = i.predecessor()
			count += 1
		}
		return count
	}
	
	/// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
	public mutating func matchString(value: String) throws {
		index = try value.unicodeScalars.reduce(index) { i, scalar in
			if i == self.scalars.endIndex || scalar != self.scalars[i] {
				throw ScalarScannerError.MatchFailed(wanted: value, at: absoluteIndex)
			}
			return i.successor()
		}
	}
	
	/// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
	public mutating func matchScalar(value: UnicodeScalar) throws {
		if index == scalars.endIndex || scalars[index] != value {
			throw ScalarScannerError.MatchFailed(wanted: String(value), at: absoluteIndex)
		}
		index = index.advancedBy(1)
	}
	
	/// Consume scalars from the contained collection until `scalar` is found. `index` is advanced to immediately after `scalar`. Throws if `scalar` is never found.
	public mutating func readUntil(scalar: UnicodeScalar) throws -> String {
		var string = ""
		var i = index
		while i != scalars.endIndex {
			let s = scalars[i]
			if s == scalar {
				break
			} else {
				string.append(s)
				i = i.successor()
			}
		}
		if i == scalars.endIndex {
			throw ScalarScannerError.SearchFailed(wanted: String(scalar), after: absoluteIndex)
		}
		index = i
		return string
	}
	
	/// Peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the scalar is appended to a `String` and the `index` increased. The `String` is returned at the end.
	public mutating func readWhileTrue(@noescape f: UnicodeScalar -> Bool) -> String {
		var string = ""
		while index != scalars.endIndex {
			if !f(scalars[index]) {
				break
			}
			string.append(scalars[index])
			index = index.advancedBy(1)
		}
		return string
	}
	
	/// Repeatedly peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the `index` increased. If `false`, the function returns.
	public mutating func skipWhileTrue(@noescape f: UnicodeScalar -> Bool) {
		while index != scalars.endIndex {
			if !f(scalars[index]) {
				return
			}
			index = index.advancedBy(1)
		}
	}
	
	/// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
	public mutating func skip(count: Int = 1) throws {
		var i = index
		var c = count
		while c > 0 && i != scalars.endIndex {
			i = i.successor()
			c -= 1
		}
		if c > 0 {
			throw ScalarScannerError.EndedPrematurely(count: count, at: absoluteIndex)
		} else {
			index = i
		}
	}
	
	/// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
	public mutating func backtrack(count: Int = 1) throws {
		var i = index
		var c = count
		while c > 0 && i != scalars.startIndex {
			i = i.predecessor()
			c -= 1
		}
		if c > 0 {
			throw ScalarScannerError.EndedPrematurely(count: -count, at: absoluteIndex)
		} else {
			index = i
		}
	}
	
	/// Returns all content after the current `index`. `index` is advanced to the end.
	public mutating func remainder() -> String {
		var string: String = ""
		while index != scalars.endIndex {
			string.append(scalars[index])
			index = index.successor()
		}
		return string
	}
	
	/// If the next scalars after the current `index` match `value`, advance over them and return `true`, otherwise, leave `index` unchanged and return `false`.
	public mutating func conditionalString(value: String) -> Bool {
		var i = index
		for c in value.unicodeScalars {
			if i == scalars.endIndex || c != scalars[i] {
				return false
			}
			i = i.successor()
		}
		index = i
		return true
	}
	
	/// If the next scalar after the current `index` match `value`, advance over it and return `true`, otherwise, leave `index` unchanged and return `false`.
	public mutating func conditionalScalar(value: UnicodeScalar) -> Bool {
		if index == scalars.endIndex || value != scalars[index] {
			return false
		}
		index = index.successor()
		return true
	}
	
	/// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index` without advancing `index`.
	public func requirePeek() throws -> UnicodeScalar {
		if index == scalars.endIndex {
			throw ScalarScannerError.EndedPrematurely(count: 1, at: absoluteIndex)
		}
		return scalars[index]
	}
	
	/// If `index` + `ahead` is within bounds, return the scalar at that location, otherwise return `nil`. The `index` will not be changed in any case.
	public func peek(ahead: Int = 0) -> UnicodeScalar? {
		var i = index
		var c = ahead
		while c > 0 && i != scalars.endIndex {
			i = i.successor()
			c -= 1
		}
		if i == scalars.endIndex {
			return nil
		}
		return scalars[i]
	}
	
	/// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index`, advancing `index` by one.
	public mutating func readScalar() throws -> UnicodeScalar {
		if index == scalars.endIndex {
			throw ScalarScannerError.EndedPrematurely(count: 1, at: absoluteIndex)
		}
		let result = scalars[index]
		index = index.successor()
		return result
	}
	
	/// Throws if scalar at the current `index` is not in the range `"0"` to `"9"`. Consume scalars `"0"` to `"9"` until a scalar outside that range is encountered. Return the integer representation of the value scanned, interpreted as a base 10 integer. `index` is advanced to the end of the number.
	public mutating func readInt() throws -> Int {
		var result = 0
		var i = index
		while i != scalars.endIndex && scalars[i] >= "0" && scalars[i] <= "9" {
			result = result * 10 + Int(scalars[i].value - UnicodeScalar("0").value)
			i = i.successor()
		}
		if i == index {
			throw ScalarScannerError.ExpectedInt(at: absoluteIndex)
		}
		index = i
		return result
	}
	
	/// Consume and return `count` scalars. `index` will be advanced by count. Throws if end of `scalars` occurs before consuming `count` scalars.
	public mutating func readScalars(count: Int) throws -> String {
		var result = String()
		result.reserveCapacity(count)
		var i = index
		for _ in 0..<count {
			if i == scalars.endIndex {
				throw ScalarScannerError.EndedPrematurely(count: count, at: absoluteIndex)
			}
			result.append(scalars[i])
			i = i.successor()
		}
		index = i
		return result
	}

	/// Returns a throwable error capturing the current scanner progress point.
	public func unexpectedError() -> ScalarScannerError {
		return ScalarScannerError.Unexpected(at: absoluteIndex)
	}
}
