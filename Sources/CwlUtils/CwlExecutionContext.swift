//
//  CwlExecutionContext.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 19/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

/// A description about how the default `invoke` function will behave for an execution context.
/// Note that it is possible to call `invokeAsync` to force an asychronous invocation or `invokeSync` to block and wait for completion for any context.
public enum ExecutionType {
	/// Any function provided to `invoke` will be completed before the call to `invoke` returns. There is no inherent mutex – simultaneous invocations from multiple threads may run concurrently so therefore this case returns `true` from `isConcurrent`.
	case immediate
	
	/// Any function provided to `invoke` will be completed before the call to `invoke` returns. Mutual exclusion is applied preventing invocations from multiple threads running concurrently.
	case mutex
	
	/// Completion of the provided function is independent of the return from `invoke`. Subsequent functions provided to `invoke`, before completion if preceeding provided functions will be serialized and run after the preceeding calls have completed.
	case serialAsync
	
	/// In this case, the execution context may be synchronous or asynchronous, depending on a test function that needs to be run in the current context.
	/// This case is primarily intended to handle `Exec.main` which performs asynchronously on the main thread if the current context is a different thread but will invoke immediately if the current thread is already the main thread.
	case conditionallyAsync(() -> Bool)
	
	/// Completion of the provided function is independent of the return from `invoke`. Subsequent functions provided to `invoke` will be run concurrently.
	case concurrentAsync
	
	/// Returns true if an invoked function is guaranteed to complete before the `invoke` returns.
	public var isImmediate: Bool {
		switch self {
		case .immediate: return true
		case .mutex: return true
		case .conditionallyAsync(let async): return !async()
		default: return false
		}
	}
	
	/// Returns true if simultaneous uses of the context from separate threads will run concurrently.
	public var isConcurrent: Bool {
		switch self {
		case .immediate: return true
		case .concurrentAsync: return true
		default: return false
		}
	}
}

/// An abstraction of common execution context concepts
public protocol ExecutionContext {
	/// A description about how functions will be invoked on an execution context.
	var type: ExecutionType { get }
	
	/// Run `execute` normally on the execution context
	func invoke(_ execute: @escaping () -> Void)
	
	/// Run `execute` asynchronously on the execution context
	/// NOTE: a default implementation of this is provided that, if `type.isImmediate` is false, directly calls `invoke`, otherwise it runs an asynchronous block on the global dispatch queue and calls `invoke` from there.
	func invokeAsync(_ execute: @escaping () -> Void)
	
	/// Run `execute` on the execution context but don't return from this function until the provided function is complete.
	/// NOTE: a default implementation of this is provided that, if `type.isImmediate` is true, simply calls `invoke`, otherwise it calls `invoke` and blocks waiting on a semaphore in the calling context until `invoke` completes. Creating a semphore for every call is inefficient so you should implement this a different way, if possible.
	func invokeSync<Return>(_ execute: () -> Return) -> Return
	
	/// Run `execute` asynchronously *outside* the execution context.
	/// NOTE: a default implementation of this function is provided that calls `DispatchQueue.global().async`. With the exception of debug, test and other host-isolated contexts, this is usually sufficient. 
	func globalAsync(_ execute: @escaping () -> Void)
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`) unless the returned `Lifetime` is cancelled or released before running occurs.
	/// NOTE: a default implementation of this function is provided that runs the timer on the global dispatch queue and calls `invoke` when it fires. This implementation is likely sufficient for most cases but may not be appropriate if your context has strict timing or serialization requirements.
	func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, unless the returned `Lifetime` is cancelled or released before running occurs.
	/// NOTE: a default implementation of this function is provided that runs the timer on the global dispatch queue and calls `invoke` when it fires. This implementation is likely sufficient for most cases but may not be appropriate if your context has strict timing or serialization requirements.
	func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	/// NOTE: a default implementation of this function is provided that runs the timer on the global dispatch queue and calls `invoke` when it fires. This implementation is likely sufficient for most cases but may not be appropriate if your context has strict timing or serialization requirements.
	func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	/// NOTE: a default implementation of this function is provided that runs the timer on the global dispatch queue and calls `invoke` when it fires. This implementation is likely sufficient for most cases but may not be appropriate if your context has strict timing or serialization requirements.
	func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime
	
	/// Gets a timestamp representing the host uptime the in the current context
	/// NOTE: a default implementation of this function is provided that calls `DispatchTime.now()`. With the exception of debug, test and other host-isolated contexts, this is usually sufficient. 
	func timestamp() -> DispatchTime
}

/// Many of the ExecutionContext functions returns a `Lifetime` and in most cases, that lifetime is just a dispatch timer. Annoyingly, a `DispatchSourceTimer` is an existential, so we can't extend it to conform to `Lifetime` (a limitation of Swift 4).
/// In these cases, you can force cast to DispatchSource and use this extension.
extension DispatchSource: Lifetime {
}

// Since it's not possible to have default parameters in protocols (yet) the "leeway" free functions are all default-implemented to call the "leeway" functions with a 0 second leeway.
public extension ExecutionContext {
	func singleTimer(interval: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return singleTimer(interval: interval, leeway: .seconds(0), handler: handler)
	}
	func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return singleTimer(parameter: parameter, interval: interval, leeway: .seconds(0), handler: handler)
	}
	func periodicTimer(interval: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return periodicTimer(interval: interval, leeway: .seconds(0), handler: handler)
	}
	func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return periodicTimer(parameter: parameter, interval: interval, leeway: .seconds(0), handler: handler)
	}
}

public extension ExecutionContext {
	func timestamp() -> DispatchTime {
		return DispatchTime.now()
	}
	
	func invokeAsync(_ execute: @escaping () -> Void) {
		if type.isImmediate == false {
			invoke(execute)
		} else {
			DispatchQueue.global().async { self.invoke(execute) }
		}
	}
	
	func invokeSync<Return>(_ execute: () -> Return) -> Return {
		return withoutActuallyEscaping(execute) { ex in
			var r: Return? = nil
			if type.isImmediate == true {
				invoke {
					r = ex()
				}
			} else {
				let s = DispatchSemaphore(value: 0)
				self.invoke {
					r = ex()
					s.signal()
				}
				s.wait()
			}
			return r!
		}
	}
	
	func globalAsync(_ execute: @escaping () -> Void) {
		DispatchQueue.global().async(execute: execute)
	}
	
	func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return DispatchSource.singleTimer(interval: interval, leeway: leeway, queue: DispatchQueue.global(), handler: { self.invoke(handler) }) as! DispatchSource
	}
	
	func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return DispatchSource.singleTimer(parameter: parameter, interval: interval, leeway: leeway, queue: DispatchQueue.global(), handler: { p in self.invoke{ handler(p) } }) as! DispatchSource
	}
	
	func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return DispatchSource.repeatingTimer(interval: interval, leeway: leeway, queue: DispatchQueue.global(), handler: { self.invoke(handler) }) as! DispatchSource
	}
	
	func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return DispatchSource.repeatingTimer(parameter: parameter, interval: interval, leeway: leeway, queue: DispatchQueue.global(), handler: { p in self.invoke{ handler(p) } }) as! DispatchSource
	}
}
