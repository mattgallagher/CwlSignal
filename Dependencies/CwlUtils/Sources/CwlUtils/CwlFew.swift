//
//  CwlFew.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 29/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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
