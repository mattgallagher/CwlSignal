//
//  CwlDeferredWork.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 5/10/2015.
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

// Simple thread safety:
//  1. No client "work" (functions or closures) should be invoked inside a private dispatch_queue/lock
//  2. No client supplied data should be released inside a private dispatch_queue/lock
// To facilitate this requirement, "lock internal" methods can return DeferredWork. DeferredWork values must be passed up the stack until they can be invoked outside any dispatch_queue.
//
// To ensure that DeferredWork is not simply forgotten without running, at debug time it includes an OnDelete check that raises a precondition failure if the DeferredWork has not been run.
public struct DeferredWork {
	var work: [() -> Void]?

#if DEBUG
	let invokeCheck: OnDelete = { () -> OnDelete in
		var sourceStack = callStackReturnAddresses(skip: 2)
		return OnDelete {
			preconditionFailure("Failed to perform work deferred at location:\n" + symbolsForCallStack(addresses: sourceStack).joined(separator: "\n"))
		}
	}()
#endif

	public init() {
		work = nil
	}
	
	public init(initial: @escaping () -> Void) {
		work = [initial]
	}
	
	public mutating func append(_ other: DeferredWork) {
#if DEBUG
		precondition(!invokeCheck.isCancelled, "Work appended to an already cancelled/invoked DeferredWork")
		other.invokeCheck.cancel()
#endif
		if var w = work, let o = other.work {
			w.append(contentsOf: o)
			work = w
		} else if work == nil {
			work = other.work
		}
	}
	
	public mutating func append(_ additionalWork: @escaping () -> Void) {
		if var w = work {
			w.append(additionalWork)
			work = w
		} else {
			work = [additionalWork]
		}
	}
	
	public func runWork() {
#if DEBUG
		precondition(!invokeCheck.isCancelled, "Work run multiple times")
		invokeCheck.cancel()
#endif
		work?.forEach { $0() }
	}
}
