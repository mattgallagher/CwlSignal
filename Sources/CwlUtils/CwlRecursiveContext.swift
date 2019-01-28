//
//  CwlRecursiveContext.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 28/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation

public extension DispatchQueue {
	static func queueWithKey(qos: DispatchQoS = .default) -> (DispatchQueue, DispatchSpecificKey<()>) {
		let q = DispatchQueue(label: "", qos: qos)
		let specificKey = DispatchSpecificKey<()>()
		q.setSpecific(key: specificKey, value: ())
		return (q, specificKey)
	}
}

public struct RecursiveContext: ExecutionContext {
	let queue: DispatchQueue
	let key: DispatchSpecificKey<()>
	
	public init(qos: DispatchQoS = .default) {
		(queue, key) = DispatchQueue.queueWithKey(qos: qos)
	}
	
	public var type: ExecutionType { return .recursiveMutex }
	
	public func invoke(_ execute: @escaping () -> Void) {
		withoutActuallyEscaping(execute) { e in invoke(e) }
	}
	
	public func invokeAsync(_ execute: @escaping () -> Void) {
		queue.async(execute: execute)
	}
	
	public func invokeSync<Return>(_ execute: () -> Return) -> Return {
		if DispatchQueue.getSpecific(key: key) != nil {
			return execute()
		} else {
			return queue.sync(execute: execute)
		}
	}
}

@available(*, deprecated, message:"Use Exec.queue instead")
public struct CustomDispatchQueue {}

@available(*, deprecated, message:"Use Exec.queue instead")
public struct DispatchQueueContext {}
