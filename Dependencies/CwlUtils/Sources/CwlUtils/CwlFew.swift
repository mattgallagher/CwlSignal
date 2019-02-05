//
//  CwlFew.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 29/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose with or without
//  fee is hereby granted, provided that the above copyright notice and this permission notice
//  appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
//  SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
//  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
//  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
//  OF THIS SOFTWARE.
//

import Foundation

public enum Few<T> {
	case none
	case single(T)
	case array(Array<T>)
}

extension Few: Collection {
	public func index(after i: Int) -> Int {
		return i + 1
	}
	
	public var count: Int {
		switch self {
		case .none: return 0
		case .single: return 1
		case .array(let a): return a.count
		}
	}
	
	public var startIndex: Int {
		return 0
	}
	
	public var endIndex: Int {
		switch self {
		case .none: return 0
		case .single: return 1
		case .array(let a): return a.endIndex
		}
	}
	
	public subscript(key: Int) -> T {
		switch self {
		case .none: fatalError()
		case .single(let value): return value
		case .array(let a): return a[key]
		}
	}
}
