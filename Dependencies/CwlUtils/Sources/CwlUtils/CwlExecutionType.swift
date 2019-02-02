//
//  CwlExecutionType.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 30/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

/// Describes 7 key execution context types. The six most common exist as a pair between a sychronous and asynchronous version:
///  * immediate and concurrentAsync
///  * mutex and serialAsync
///  * thread and threadAsync
/// With the final context being an additional variation on mutex:
///  * recursiveMutex
///
/// This list of of execution context types should *not* be considered exhaustive so in general, it is better to interrogate the boolean properties in which you're interested.
/// These properties are currently:
///  * isImmediate[InCurrentContext|Always]
///  * isReentrant
///  * isConcurrent
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
	
	/// This execution type models a scoped recursive mutex. The associated test function returns `true` if the `invoke` or `invokeSync` function can be elided (replaced by direct invocation, since the current context is known to be inside the mutex).
	///	* completes before `invoke` returns (immediate)
	///   * applies a mutex but a nested `invoke` will safely re-enter the mutex (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation always inherits the caller's context (nest always)
	/// e.g. NSRecursiveLock.lock(before:)
	case recursiveMutex(() -> Bool)
	
	/// This execution type models a thread. The associated test function returns `true` if the `invoke` or `invokeSync` function can be elided (replaced by direct invocation, since the current context is known to be inside the thread).
	///	* if test function returns true, then `invoke` is immediate in the current context, otherwise asychronous (immediate/asynchronous)
	///   * nested calls to `invoke` are permitted since they will simply be run immediately (reentrant)
	///   * will serialize parallel calls to run one at a time (serial)
	///   * invocation only inherits the caller's context if test function returns true in current context (nest thread)
	/// e.g. `if Thread.isMainThread { /* do work */ } else { DispatchQueue.main.async { /* do work */ }`
	case thread(() -> Bool)
	
	/// This execution type models a thread on which work is typically performed asynchronously. The associated test function returns `true` if the `invoke` or `invokeSync` function can be elided (replaced by direct invocation, since the current context is known to be inside the thread).
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
	/// Returns true if a block executed with `invoke` is guaranteed to complete before `invoke` returns in the current context.
	/// The inverse of this value is "isAsyncInCurrentContext".
	///
	/// NOTE: this property runs a function for case `.thread` to see if the current thread is the target thread. Any change queue/thread may break the guarantee (the name "thread" is representative-only and might not refer to a literal thread).
	var isImmediateInCurrentContext: Bool {
		switch self {
		case .immediate, .mutex, .recursiveMutex: return true
		case .thread(let isCurrent): return isCurrent()
		case .serialAsync, .concurrentAsync, .threadAsync: return false
		}
	}
	
	/// Inverse of `isImmediateInCurrentContext`
	var isAsyncInCurrentContext: Bool { return !isImmediateInCurrentContext }
	
	/// Returns true if a block executed with `invoke` is always guaranteed to complete before `invoke` returns.
	/// The inverse of this value is "isPotentiallyAsync"
	var isImmediateAlways: Bool {
		switch self {
		case .immediate, .mutex, .recursiveMutex: return true
		case .thread, .serialAsync, .concurrentAsync, .threadAsync: return false
		}
	}
	
	/// Inverse of `isImmediateAlways`
	var isPotentiallyAsync: Bool { return !isImmediateInCurrentContext }
	
	/// Returns true if calling `invoke` or `invokeSync` within an executed block will succeed (not deadlock).
	/// The inverse of this value is "non-reentrant"
	var isReentrant: Bool {
		switch self {
		case .immediate, .recursiveMutex, .thread, .threadAsync, .concurrentAsync: return true
		case .mutex, .serialAsync: return false
		}
	}
	
	/// Inverse of `isReentrant`
	var isNonReentrant: Bool { return !isReentrant }
	
	/// Returns true if calling `invoke` simultaneously on separate threads may result in simultaneous execution.
	/// The inverse of this value is "serial"
	var isConcurrent: Bool {
		switch self {
		case .immediate, .concurrentAsync: return true
		case .mutex, .recursiveMutex, .serialAsync, .thread, .threadAsync: return false
		}
	}
	
	/// Inverse of `isConcurrent`
	var isSerial: Bool { return !isConcurrent }
}

