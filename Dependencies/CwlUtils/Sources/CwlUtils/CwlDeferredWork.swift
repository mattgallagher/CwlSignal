//
//  CwlDeferredWork.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 5/10/2015.
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

// This type is designed for guarding against mutex re-entrancy by following two simple rules:
//
//  1. No user "work" (functions or closures) should be invoked inside a private mutex
//  2. No user supplied data should be released inside a private mutex
//
// To facilitate these requirements, any user "work" or data ownership should be handled inside `DeferredWork` blocks. These blocks allow this user code to be queued in the desired order but since the `runWork` function should only be called outside the mutex, these blocks run safely outside the mutex.
//
// This pattern has two associated risks:
//  1. If the deferred work calls back into the mutex, it must be able to ensure that it is still relevant (hasn't been superceded by an action that may have occurred between the end of the mutex and the performing of the `DeferredWork`. This may involve a token (inside the mutex, only the most recent token is accepted) or the mutex queueing further requests until the most recent `DeferredWork` completes.
//  2. The `runWork` must be manually invoked. Automtic invocation (e.g in the `deinit` of a lifetime managed `class` instance) would add heap allocation overhead and would also be easy to accidentally release at the wrong point (inside the mutex) causing erratic problems. Instead, the `runWork` is guarded with a `DEBUG`-only `OnDelete` check that ensures that the `runWork` has been correctly invoked by the time the `DeferredWork` falls out of scope.
public struct DeferredWork {
	enum PossibleWork {
		case none
		case single(() -> Void)
		case multiple(Array<() -> Void>)
	}
	
	var work: PossibleWork

	#if DEBUG
		let invokeCheck: OnDelete = { () -> OnDelete in
			var sourceStack = Thread.callStackReturnAddresses
			return OnDelete {
				let symbols = symbolsForCallStack(addresses: sourceStack.map { $0.uintValue })
				preconditionFailure("Failed to perform work deferred at location:\n" + symbols.joined(separator: "\n"))
			}
		}()
	#endif

	public init() {
		work = .none
	}
	
	public init(initial: @escaping () -> Void) {
		work = .single(initial)
	}
	
	public mutating func append(_ other: DeferredWork) {
		#if DEBUG
			precondition(invokeCheck.isValid && other.invokeCheck.isValid, "Work appended to an already cancelled/invoked DeferredWork")
				other.invokeCheck.invalidate()
		#endif
		
		switch other.work {
		case .none: break
		case .single(let otherWork): self.append(otherWork)
		case .multiple(let otherWork):
			switch work {
			case .none: work = .multiple(otherWork)
			case .single(let existing):
				var newWork: Array<() -> Void> = [existing]
				newWork.append(contentsOf: otherWork)
				work = .multiple(newWork)
			case .multiple(var existing):
				work = .none
				existing.append(contentsOf: otherWork)
				work = .multiple(existing)
			}
		}
	}
	
	public mutating func append(_ additionalWork: @escaping () -> Void) {
		#if DEBUG
			precondition(invokeCheck.isValid, "Work appended to an already cancelled/invoked DeferredWork")
		#endif
		
		switch work {
		case .none: work = .single(additionalWork)
		case .single(let existing): work = .multiple([existing, additionalWork])
		case .multiple(var existing):
			work = .none
			existing.append(additionalWork)
			work = .multiple(existing)
		}
	}
	
	public mutating func runWork() {
		#if DEBUG
			precondition(invokeCheck.isValid, "Work run multiple times")
			invokeCheck.invalidate()
		#endif
		
		switch work {
		case .none: break
		case .single(let w): w()
		case .multiple(let ws):
			for w in ws {
				w()
			}
		}
		work = .none
	}
}
