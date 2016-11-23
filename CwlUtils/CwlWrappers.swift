//
//  CwlWrappers.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
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

/// A class wrapper around a type (usually a value type) so it can be moved without copying but also so that it can be passed through Objective-C parameters.
public class Box<T> {
	public let value: T
	public init(_ t: T) {
		value = t
	}
}

//// A class wrapper around a type (usually a value type) so changes to it can be shared (usually as an ad hoc communication channel). NOTE: this version is *not* threadsafe, use AtomicBox for that.
public final class MutableBox<T> {
	public var value: T
	public init(_ t: T) {
		value = t
	}
}

// A class wrapper around a type (usually a value type) so changes to it can be shared in a thread-safe manner (usually as an ad hoc communication channel).
/// "Atomic" in this sense refers to the semantics, not the implementation. This uses a pthread mutex, not CAS-style atomic operations.
public final class AtomicBox<T> {
	private var mutex = PThreadMutex()
	private var internalValue: T
	
	public init(_ t: T) {
		internalValue = t
	}
	
	public var value: T {
		get {
			mutex.unbalancedLock()
			defer { mutex.unbalancedUnlock() }
			return internalValue
		}
		set {
			mutex.unbalancedLock()
			defer { mutex.unbalancedUnlock() }
			internalValue = newValue
		}
	}

	@discardableResult
	public func mutate(_ f: (inout T) -> Void) -> T {
		mutex.unbalancedLock()
		defer { mutex.unbalancedUnlock() }
		f(&internalValue)
		return internalValue
	}
}

/// A wrapper around a type (usually a class type) so it can be weakly referenced from an Array or other strong container.
public struct Weak<T: AnyObject> {
	public weak var value: T?
	
	public init(_ value: T?) {
		self.value = value
	}
	
	public func contains(_ other: T) -> Bool {
		if let v = value {
			return v === other
		} else {
			return false
		}
	}
}

/// A wrapper around a type (usually a class type) so it can be referenced unowned from an Array or other strong container.
public struct Unowned<T: AnyObject> {
	public unowned let value: T
	public init(_ value: T) {
		self.value = value
	}
}

/// A enum wrapper around a type (usually a class type) so its ownership can be set at runtime.
public enum PossiblyWeak<T: AnyObject> {
	case strong(T)
	case weak(Weak<T>)
	
	public init(strong value: T) {
		self = PossiblyWeak<T>.strong(value)
	}
	
	public init(weak value: T) {
		self = PossiblyWeak<T>.weak(Weak(value))
	}
	
	public var value: T? {
		switch self {
		case .strong(let t): return t
		case .weak(let weakT): return weakT.value
		}
	}
	
	public func contains(_ other: T) -> Bool {
		switch self {
		case .strong(let t): return t === other
		case .weak(let weakT):
			if let wt = weakT.value {
				return wt === other
			}
			return false
		}
	}
}
