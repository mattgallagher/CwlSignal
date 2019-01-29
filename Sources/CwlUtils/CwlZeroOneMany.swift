//
//  CwlZeroOneMany.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 29/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation

public enum ZeroOneMany<T> {
	case zero
	case one(T)
	case many(Array<T>)
}

extension ZeroOneMany: Collection {
	public func index(after i: Int) -> Int {
		return i + 1
	}
	
	public var count: Int {
		switch self {
		case .zero: return 0
		case .one: return 1
		case .many(let a): return a.count
		}
	}
	
	public var startIndex: Int {
		return 0
	}
	
	public var endIndex: Int {
		switch self {
		case .zero: return 0
		case .one: return 1
		case .many(let a): return a.endIndex
		}
	}
	
	public subscript(key: Int) -> T {
		switch self {
		case .zero: fatalError()
		case .one(let value): return value
		case .many(let a): return a[key]
		}
	}
}
