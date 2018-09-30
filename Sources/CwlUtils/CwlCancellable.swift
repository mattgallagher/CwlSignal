//
//  CwlCancellable.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2017/04/18.
//  Copyright © 2017 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

/// This protocol exists to provide lifetime and termination capabilities to asynchronous an ongoing tasks (an implementation of the "Disposable" pattern).
///
/// Implementation of this protocol implies that an instance manages an underlying resource that will be set to en "end-of-life" state when the instances falls out of scope. The `cancel` function can be invoked to force this "end-of-life" state *without* falling out of scope.
///
/// This protocol implies a behavior that is *not* enforced by the interface. Namely: deallocating a `Cancellable` should have the same effect as calling `cancel` (although `cancel` need not be invoked on dealloc). Usually, this requirement is ensured by `cancel` in the `deinit` method, however, directly invoking `cancel` on dealloc is not required by this protocol, merely the transition to "end-of-life" state. Specifically, `struct` implementations of this protocol will usually contain a `class` instance that will apply the `cancel` behavior when deallocated.
///
/// An additional expectation is that calling `cancel` multiple times be "safe" and generally idempotent (the second call should be a no-op).
/// An additional expectation is that calling `cancel` multiple times be "safe" and generally idempotent (the second call should be a no-op).
public protocol Cancellable {
    /// Immediately set the resource managed by this instance to an "end-of-life" state.
    mutating func cancel()
}

/// A simple array, aggregating a number of Cancellable instances into a single Cancellable.
/// Once conditional conformances are available in Swift (possibly in Swift 4.1 at this stage) this could be replaced with `extension Array: Cancellable where Element: Cancellable`.
public struct ArrayOfCancellables: Cancellable, RangeReplaceableCollection {
    // Novel members of this type
    private var cancellables: [Cancellable]
    public mutating func cancel() {
        for i in cancellables.indices {
            cancellables[i].cancel()
        }
    }

	// Boilerplate RangeReplaceableCollection members:
	public typealias Iterator = IndexingIterator<Array<Cancellable>>
	public init<S>(_ elements: S) where S : Sequence, Iterator.Element == S.Iterator.Element {
		self.cancellables = Array(elements)
	}
	public init() {
		self.cancellables = []
	}
	public func makeIterator() -> IndexingIterator<Array<Cancellable>> {
		return cancellables.makeIterator()
	}
	public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C : Collection, C.Iterator.Element == Cancellable {
		cancellables.replaceSubrange(subrange, with: newElements)
	}
	public var startIndex: Int { return cancellables.startIndex }
	public var endIndex: Int { return cancellables.endIndex }
	public subscript(_ i: Int) -> Iterator.Element { return cancellables[i] }
	public func index(after i: Int) -> Int { return cancellables.index(after: i) }
}

/// Wraps an arbitrary value in an optional and offers Cancellable conformance. This lets any type participate in simple ownership scenarios or breakable reference counted loops without needing to implement per-type Cancellable conformance. The `cancel` simply nils the optional.
public struct CancellableValue<T>: Cancellable {
    public var value: T?
    public init(_ value: T) {
        self.value = value
    }
    public mutating func cancel() {
        self.value = nil
    }
}
