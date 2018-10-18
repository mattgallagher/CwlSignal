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

/// This protocol exists to keep alive and terminate-at-will asynchronous and ongoing tasks (an implementation of the "Disposable" pattern).
///
/// While conformance to this protocol requires just one function, conforming to this protocol also signals three important traits:
///    1. instances manage an underlying resource
///    2. the resource will last until one the first of the following end-conditions occurs:
///        a. It terminates on its own
///        b. All references to the Lifetime instance are released
///        c. The `cancel()` function is invoked
///    3. subsequent calls to `cancel()` after a previous end-condition will have no effect
///
/// ideally, as well:
///
///    4. `cancel()` and releasing all references to the instance should have the same effect
///    5. no further effects or actions of any kind will occur after the first end-condition is registered in the
///       resource's context.
///
/// although there are some cases where explicitly sending "cancelled" notifications is valid behavior and where this
/// type of notification might be triggered when `cancel()` is called but not `deinit`.
///
/// The protocol requires the `cancel` function exist but it is up to conforming types to follow the rules.
public protocol Lifetime {
	/// Immediately set the resource managed by this instance to an "end-of-life" state.
	mutating func cancel()
}

public typealias Cancellable = Lifetime

/// Just an array of Lifetime that conforms to Lifetime. While you can do this through conditional conformance, you can't handle Element == Lifetime at the sme time as Element: Lifetime or Element: LifetimeSubtype in Swift 4.2 so it's best to tread around the issue entirely.
public struct AggregateLifetime: Lifetime {
	public var lifetimes: [Lifetime]
	public init(lifetimes: [Lifetime]) {
		self.lifetimes = lifetimes
	}
	public mutating func cancel() {
		for i in lifetimes.indices {
			lifetimes[i].cancel()
		}
	}
}
