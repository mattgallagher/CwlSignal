//
//  CwlLifetime.swift
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

/// This protocol exists to keep alive and terminate-at-will asynchronous and ongoing tasks. It is an
/// implementation of the "Disposable" pattern.
///
/// While conformance to this protocol requires just one function, conforming to this protocol also signals three important traits:
///    1. instances manage an underlying resource
///	 2. the resource will last until one the first of the following end-conditions occurs:
///        a. The resource terminates on its own
///        b. All references to the Lifetime instance are released
///        c. The `cancel()` function is invoked
///
/// ideally, as well:
///
///    3. no further effects or actions of any kind will occur after the first end-condition is registered in the
///       resource's context, no further messages or notifications sent or received, no resurrection possible
///    4. any subsequent end conditions after the first are safe and have no effect
///    5. if Self is a reference type, `cancel` should be explicitly invoked on deinit
///    6. `cancel` should invoke `cancel` on any owned child Lifetime instances
///
/// Examples of violations of the last 4 points exist be should be kept rare.
public protocol Lifetime {
	/// Immediately set the resource managed by this instance to an "end-of-life" state.
	/// This a mutating method and should be called only in executation contexts where changing `self` is threadsafe.
	mutating func cancel()
}

public typealias Cancellable = Lifetime

/// An array of Lifetime that conforms to Lifetime. Note that a conditional conformance on Array can't properly conform
// to Lifetime since it would permit adding new lifetimes after the aggregate was cancelled.
public class AggregateLifetime: Lifetime {
	private var lifetimes: [Lifetime]?
	public init(lifetimes: [Lifetime] = []) {
		self.lifetimes = lifetimes
	}
	public func cancel() {
		if var ls = lifetimes {
			for i in ls.indices {
				ls[i].cancel()
			}
			lifetimes = nil
		}
	}
	public static func +=(left: AggregateLifetime, right: Lifetime) {
		left.lifetimes?.append(right)
	}
	deinit {
		cancel()
	}
}
