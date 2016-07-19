//
//  CwlMutexAdditionalComparisons.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/06/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import Foundation
import CwlUtils
import XCTest

extension PThreadMutex {
	private func fastsync<R>(f: @noescape () throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f()
	}
}
private func fastsync<R>(_ mutex: PThreadMutex, f: @noescape () throws -> R) rethrows -> R {
	pthread_mutex_lock(&mutex.unsafeMutex)
	defer { pthread_mutex_unlock(&mutex.unsafeMutex) }
	return try f()
}

public struct DispatchSemaphoreWrapper {
	let s = DispatchSemaphore(value: 1)
	init() {}
	func sync<R>(f: @noescape () throws -> R) rethrows -> R {
		_ = s.wait(timeout: DispatchTime.distantFuture)
		defer { s.signal() }
		return try f()
	}
}

extension PThreadMutex {
	public func sync_2<T>(_ param: inout T, f: @noescape (inout T) throws -> Void) rethrows -> Void {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		try f(&param)
	}
	public func sync_3<T, R>(_ param: inout T, f: @noescape (inout T) throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f(&param)
	}
	public func sync_4<T, U>(_ param1: inout T, _ param2: inout U, f: @noescape (inout T, inout U) throws -> Void) rethrows -> Void {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f(&param1, &param2)
	}
}

let iterations = 10_000_000

class MutexPerformanceTests: XCTestCase {
	
	func testPThreadSync2Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				mutex.sync_2(&total) { (t: inout Int) -> Void in
					t += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadFreePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				fastsync(mutex) {
					total += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadSlowSyncPerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				mutex.sync {
					total += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadSync3Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				total = mutex.sync_3(&total) { t in
					return t + 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadSync4Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for i in 0..<iterations {
				var j = i
				mutex.sync_4(&j, &total) { (j: inout Int, t: inout Int) in
					t = j + 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testObjcSyncPerformance() {
		let mutex = NSObject()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				objc_sync_enter(mutex)
				total += 1
				objc_sync_exit(mutex)
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadCopiedPerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				mutex.fastsync { t in
					total += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadInlinePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				pthread_mutex_lock(&mutex.unsafeMutex)
				total += 1
				pthread_mutex_unlock(&mutex.unsafeMutex)
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testDispatchSyncPerformance() {
		let queue = DispatchQueue(label: "", attributes: .serial)
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				queue.sync {
					total += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testSpinLockPerformance() {
		var lock = OS_SPINLOCK_INIT
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				OSSpinLockLock(&lock)
				total += 1
				OSSpinLockUnlock(&lock)
			}
			XCTAssert(total == iterations)
		}
	}
}
