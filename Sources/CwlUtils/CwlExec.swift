//
//  CwlExec.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
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

/// `Exec` is a transparent representation of come common execution contexts – allowing interrogation of whether the context is `sync` or `main`, so that the user of the `Exec` can perform appropriate optimizations, avoiding the need to actually invoke.
public enum Exec {
	/// Invoked directly from the caller's context
	case direct
	
	/// Invoked on the main thread, directly if the current thread is the main thread, otherwise asynchronously (unless invokeSync is used)
	case main
	
	/// Invoked using a Dispatch Queue
	case queue(DispatchQueue, ExecutionType)
	
	/// Invoked using the wrapped existential.
	case custom(ExecutionContext)
}

public extension Exec {
	/// If this context is concurrent, returns a serialization around this context, otherwise returns this context.
	func serialized() -> Exec {
		if self.type.isConcurrent {
			return Exec.custom(SerializingContext(concurrentContext: self))
		}
		return self
	}
	
	/// Invoked on the main thread, always asynchronously (unless invokeSync is used)
	static var mainAsync: Exec {
		return .queue(.main, .serialAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_DEFAULT priority
	static var global: Exec {
		return .queue(.global(), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_USER_INTERACTIVE priority
	static var interactive: Exec {
		return .queue(.global(qos: .userInteractive), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_USER_INITIATED priority
	static var user: Exec {
		return .queue(.global(qos: .userInitiated), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_UTILITY priority
	static var utility: Exec {
		return .queue(.global(qos: .utility), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_BACKGROUND priority
	static var background: Exec {
		return .queue(.global(qos: .background), .concurrentAsync)
	}
	
	/// Constructs an `Exec.custom` wrapping a synchronous `DispatchQueue`
	static func syncQueue() -> Exec {
		return Exec.queue(DispatchQueue(label: ""), ExecutionType.mutex)
	}
	
	/// Constructs an `Exec.custom` wrapping a synchronous `DispatchQueue` with a `DispatchSpecificKey` set for the queue (so that it can be identified when active).
	static func syncQueueWithSpecificKey() -> (Exec, DispatchSpecificKey<()>) {
		let q = DispatchQueue(label: "")
		let specificKey = DispatchSpecificKey<()>()
		q.setSpecific(key: specificKey, value: ())
		return (Exec.queue(q, ExecutionType.mutex), specificKey)
	}
	
	/// Constructs an `Exec.custom` wrapping an asynchronous `DispatchQueue`
	static func asyncQueue(qos: DispatchQoS = .default) -> Exec {
		return Exec.queue(DispatchQueue(label: "", qos: qos), ExecutionType.serialAsync)
	}
	
	/// Constructs an `Exec.custom` wrapping an asynchronous `DispatchQueue` with a `DispatchSpecificKey` set for the queue (so that it can be identified when active).
	static func asyncQueueWithSpecificKey(qos: DispatchQoS = .default) -> (Exec, DispatchSpecificKey<()>) {
		let q = DispatchQueue(label: "", qos: qos)
		let specificKey = DispatchSpecificKey<()>()
		q.setSpecific(key: specificKey, value: ())
		return (Exec.queue(q, ExecutionType.serialAsync), specificKey)
	}
}

extension Exec: ExecutionContext {
	/// A description about how functions will be invoked on an execution context.
	public var type: ExecutionType {
		switch self {
		case .direct: return .immediate
		case .main: return .conditionallyAsync { !Thread.isMainThread }
		case .custom(let c): return c.type
		case .queue(_, let t): return t
		}
	}
	
	/// Run `execute` normally on the execution context
	public func invoke(_ execute: @escaping () -> Void) {
		switch self {
		case .direct: execute()
		case .custom(let c): c.invoke(execute)
		case .main where Thread.isMainThread: execute()
		case .main: DispatchQueue.main.async(execute: execute)
		case .queue(let q, let t) where t.isImmediate: q.sync(execute: execute)
		case .queue(let q, _): q.async(execute: execute)
		}
	}
	
	/// Run `execute` asynchronously on the execution context
	public func invokeAsync(_ execute: @escaping () -> Void) {
		switch self {
		case .direct: DispatchQueue.global().async(execute: execute)
		case .custom(let c): c.invokeAsync(execute)
		case .main: DispatchQueue.main.async(execute: execute)
		case .queue(let q, _): q.async(execute: execute)
		}
	}
	
	@available(*, deprecated, message: "Use invokeSync instead")
	public func invokeAndWait(_ execute: @escaping () -> Void) {
		_ = invokeSync(execute)
	}
	
	/// Run `execute` on the execution context but don't return from this function until the provided function is complete.
	public func invokeSync<Result>(_ execute: () -> Result) -> Result {
		switch self {
		case .direct: return execute()
		case .custom(let c): return c.invokeSync(execute)
		case .main where Thread.isMainThread: return execute()
		case .main: return DispatchQueue.main.sync(execute: execute)
		case .queue(_, let t) where t.isConcurrent: return execute()
		case .queue(DispatchQueue.main, _) where Thread.current.isMainThread: return execute()
		case .queue(let q, _): return q.sync(execute: execute) 
		}
	}
	
	public func globalAsync(_ execute: @escaping () -> Void) {
		switch self {
		case .custom(let c): c.globalAsync(execute)
		default: DispatchQueue.global().async(execute: execute)
		}
	}
	
	private var timerQueue: DispatchQueue {
		switch self {
		case .direct: return DispatchQueue.global()
		case .main: return DispatchQueue.main
		case .queue(let q, _): return q
		case .custom: fatalError()
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping () -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.singleTimer(interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.singleTimer(interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.singleTimer(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.singleTimer(parameter: parameter, interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping () -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.periodicTimer(interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.repeatingTimer(interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.periodicTimer(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.repeatingTimer(parameter: parameter, interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Gets a timestamp representing the host uptime the in the current context
	public func timestamp() -> DispatchTime {
		if case .custom(let c) = self {
			return c.timestamp()
		}
		return DispatchTime.now()
	}
}

public extension Exec {
	@available(*, deprecated, message:"Values returned from this may be misleading. Perform your own switch to precisely get the information you need.")
	var dispatchQueue: DispatchQueue {
		switch self {
		case .direct, .custom: return DispatchQueue.global()
		case .main: return DispatchQueue.main
		case .queue(let q, _): return q
		}
	}
}
