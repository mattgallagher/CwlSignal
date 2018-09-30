//
//  CwlCollection.swift
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

extension Optional {
	/// Reurns true if the current optional is nil. Useful for testing for nil at a specific point during chained unwrapping of nested optionals.
	public var isNil: Bool {
		return self == nil
	}
}

extension Collection {
	/// Returns the element at the specified index iff it is within bounds, otherwise nil.
	public func at(_ i: Index) -> Iterator.Element? {
		return (i >= startIndex && i < endIndex) ? self[i] : nil
	}
}

extension Collection {
	/// Constrains the range to the indices of self and returns a SubSequence.
	public func at(_ range: Range<Index>) -> SubSequence {
		let start = (range.lowerBound >= startIndex) ? (range.lowerBound < endIndex ? range.lowerBound : endIndex) : startIndex
		let end = (range.upperBound < endIndex) ? (range.upperBound > startIndex ? range.upperBound : startIndex) : endIndex
		return self[start..<end]
	}
}

extension Collection where Index: Strideable, Index.Stride: SignedInteger {
	/// Constrains the range to the indices of self and returns a SubSequence.
	public func at(_ range: CountableRange<Index>) -> SubSequence {
		let start = (range.lowerBound >= startIndex) ? (range.lowerBound < endIndex ? range.lowerBound : endIndex) : startIndex
		let end = (range.upperBound < endIndex) ? (range.upperBound > startIndex ? range.upperBound : startIndex) : endIndex
		return self[start..<end]
	}
}

extension RangeReplaceableCollection {
	// In Swift 4, this can be replaced by `s += CollectionOfOne(e)`
	public static func +=(s: inout Self, e: Iterator.Element) {
		s.append(e)
	}
	
	// In Swift 4, this can be replaced by `s + CollectionOfOne(e)`
	public func appending(_ newElement: Iterator.Element) -> Self {
		var result = self
		result.append(newElement)
		return result
	}
}
