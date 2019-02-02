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

/// An abstraction of common execution context concepts
public protocol CustomExecutionContext {
	/// A description about how functions will be invoked on an execution context.
	var type: ExecutionType { get }
	
	/// Run `execute` normally on the execution context
	func invoke(_ execute: @escaping () -> Void)
	
	/// Run `execute` asynchronously on the execution context
	/// NOTE: a default implementation of this is provided that, if `type.isImmediate` is false, directly calls `invoke`, otherwise it runs an asynchronous block on the global dispatch queue and calls `invoke` from there.
	func invokeAsync(_ execute: @escaping () -> Void)
	
	/// Run `execute` on the execution context but don't return from this function until the provided function is complete.
	/// NOTE: a default implementation of this is provided that, if `type.isImmediate` is true, simply calls `invoke`, otherwise it calls `invoke` and blocks waiting on a semaphore in the calling context until `invoke` completes. Creating a semphore for every call is inefficient so you should implement this a different way, if possible.
	func invokeSync<Return>(_ execute: () throws -> Return) rethrows -> Return
	
	/// A context that can be used to safely escape the current context.
	/// NOTE: a default implementation of this function is provided that calls `DispatchQueue.global().async`. 
	/// - Parameter qos: The desired DispatchQoS.QoSClass for the new context. If `nil`, then inherit from `self` where possible
	func relativeAsync(qos: DispatchQoS.QoSClass?) -> Exec
	
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
public extension CustomExecutionContext {
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

public extension CustomExecutionContext {
	var isImmediateInCurrentContext: Bool { return type.isImmediateInCurrentContext }
	var isAsyncInCurrentContext: Bool { return type.isAsyncInCurrentContext }
	var isImmediateAlways: Bool { return type.isImmediateAlways }
	var isPotentiallyAsync: Bool { return type.isPotentiallyAsync }
	var isReentrant: Bool { return type.isReentrant }
	var isNonReentrant: Bool { return type.isNonReentrant }
	var isConcurrent: Bool { return type.isConcurrent }
	var isSerial: Bool { return type.isSerial }


	func timestamp() -> DispatchTime {
		return DispatchTime.now()
	}
	
	func invokeAsync(_ execute: @escaping () -> Void) {
		if type.isImmediateInCurrentContext == false {
			invoke(execute)
		} else {
			DispatchQueue.global().async { self.invoke(execute) }
		}
	}
	
	func invokeSync<Return>(_ execute: () -> Return) -> Return {
		return withoutActuallyEscaping(execute) { ex in
			var r: Return? = nil
			if type.isImmediateInCurrentContext == true {
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
	
	func relativeAsync(qos: DispatchQoS.QoSClass?) -> Exec {
		return Exec.global(qos: qos ?? .default)
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

@available(*, deprecated, message: "Use Exec for variables or CustomExecutionContext for conformances used in the `custom` case of Exec")
public typealias ExecutionContext = CustomExecutionContext
