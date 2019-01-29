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

/// This type describes 9 key execution context types. Most exist as a pair between a sychronous and asynchronous version:
///  * immediate and concurrentAsync
///  * mutex and mutexAsync
///  * recursive and recursiveAsync
///  * thread and threadAsync
/// With the final odd one lacking a synchronous version:
///  * serialAsync
/// This type offers an abstraction where these 9 types can be represented as a combination of the following properties:
///  * isImmediate
///  * isReentrant
///  * isConcurrent
///  * willNest
public enum ExecutionType {
	/// This execution type models a simple function invocation.
	///	* completes before `invoke` returns (immediate)
	///   * applies no mutex so nested calls to `invoke` will succeed (reentrant)
	///   * will let parallel calls run at the same time (concurrent)
	///   * invocation always inherits the caller's context (nest always)
	/// e.g. directly calling
	case immediate
	
	/// This execution type models a global concurrent work pool.
	///	* runs outside the current context and might not complete before `invoke` returns (asynchronous)
	///   * involves no mutex so nested calls to `invokeSync` are permitted (reentrant)
	///   * will let parallel calls run at the same time (concurrent)
	///   * normally async but `invokeSync` is invoked from the calling context (sync nests)
	/// e.g. DispatchQueue.global().async
	case concurrentAsync
	
	/// This execution type models a scoped non-recursive mutex.
	///	* completes before `invoke` returns (immediate)
	///   * applies a non-reentrant mutex so nested calls to `invoke` will deadlock (non-reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation always inherits the caller's context (nest always)
	/// e.g. dispatchQueue.sync
	case mutex
	
	/// This execution type models a scoped non-recursive mutex on which work is typically performed asynchronously.
	///	* runs outside the current context and might not complete before `invoke` returns (asynchronous)
	///   * applies a non-reentrant mutex so nested calls to `invokeSync` will deadlock (non-reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation only inherits the caller's context when calling `invokeSync` (nest sync)
	/// e.g. dispatchQueue.async
	case mutexAsync
	
	/// This execution type models a scoped recursive mutex.
	///	* completes before `invoke` returns (immediate)
	///   * applies a mutex but a nested `invoke` will safely re-enter the mutex (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation always inherits the caller's context (nest always)
	/// e.g. NSRecursiveLock.lock(before:)
	case recursiveMutex(() -> Bool)
	
	/// This execution type models a scoped recursive mutex on which work is typically performed asynchronously.
	///	* runs outside the current context and might not complete before `invoke` returns (asynchronous)
	///   * applies a reentrant mutex so nested calls to `invokeSync` will not deadlock (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation only inherits the caller's context when calling `invokeSync` (nest sync)
	/// e.g. dispatchQueue.async
	case recursiveAsync(() -> Bool)
	
	/// This execution type models a thread.
	///	* if test function returns true, then `invoke` is immediate in the current context, otherwise asychronous (immediate/asynchronous)
	///   * nested calls to `invoke` are permitted since they will simply be run immediately (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation only inherits the caller's context if test function returns true in current context (nest thread)
	/// e.g. `if Thread.isMainThread { /* do work */ } else { DispatchQueue.main.async { /* do work */ }`
	case thread(() -> Bool)
	
	/// This execution type models a thread on which work is typically performed asynchronously.
	///	* `invoke` is always asynchronous (asynchronous)
	///   * detects when it is already on the current thread so nested calls to `invokeSync` will not deadlock (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * normally async but `invokeSync` nests if already on its thread (nest syncThread)
	/// e.g. DispatchQueue.main.async
	case threadAsync(() -> Bool)
	
	/// This execution type models an asynchronous resource that lacks any synchronous access.
	///	* runs outside the current context and might not complete before `invoke` returns (asynchronous)
	///   * applies a non-reentrant mutex so nested calls to `invokeSync` will deadlock (non-reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation never inherits the caller's context (nest no)
	/// e.g. a serial resource that offers a `performAsync(_:() -> Void)` but doesn't offer a `performSync(_:() -> Void)`
	case serialAsync
}

public extension ExecutionType {
	/// Returns true if an invoked function is guaranteed to complete before the `invoke` returns.
	/// The inverse of this value is "async"
	var isImmediateInCurrentContext: Bool {
		switch self {
		case .immediate, .mutex, .recursiveMutex: return true
		case .thread(let isCurrent): return isCurrent()
		case .serialAsync, .recursiveAsync, .concurrentAsync, .mutexAsync, .threadAsync: return false
		}
	}
	
	/// Returns true if an invoked function is guaranteed to complete before the `invoke` returns.
	/// The inverse of this value is "async"
	var isImmediateAlways: Bool {
		switch self {
		case .immediate, .mutex, .recursiveMutex: return true
		case .thread, .serialAsync, .recursiveAsync, .concurrentAsync, .mutexAsync, .threadAsync: return false
		}
	}
	
	/// Returns true if an invoked function is guaranteed to complete before the `invoke` returns.
	/// The inverse of this value is "non-reentrant"
	var isReentrant: Bool {
		switch self {
		case .immediate, .recursiveAsync, .recursiveMutex, .thread, .threadAsync, .concurrentAsync: return true
		case .mutex, .serialAsync, .mutexAsync: return false
		}
	}
	
	/// Returns true if an invoked function is guaranteed to complete before the `invoke` returns.
	/// The inverse of this value is "non-reentrant"
	var isAsyncNonReentrant: Bool {
		switch self {
		case .immediate, .mutex, .recursiveAsync, .recursiveMutex, .thread, .threadAsync, .concurrentAsync: return true
		case .serialAsync, .mutexAsync: return false
		}
	}
	
	/// Returns true if simultaneous uses of the context from separate threads will run concurrently.
	/// The inverse of this value is "serial"
	var isConcurrent: Bool {
		switch self {
		case .immediate, .concurrentAsync: return true
		case .mutex, .recursiveMutex, .recursiveAsync, .serialAsync, .thread, .threadAsync, .mutexAsync: return false
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
