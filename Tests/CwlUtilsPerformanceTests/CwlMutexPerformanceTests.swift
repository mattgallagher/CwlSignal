//
//  CwlMutexAdditionalComparisons.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/06/16.
//  Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation
import CwlUtils
import XCTest

private extension PThreadMutex {
	func sync_same_file<R>(f: () throws -> R) rethrows -> R {
		pthread_mutex_lock(&underlyingMutex)
		defer { pthread_mutex_unlock(&underlyingMutex) }
		return try f()
	}
}

public struct DispatchSemaphoreWrapper {
	let s = DispatchSemaphore(value: 1)
	init() {}
	func sync<R>(f: () throws -> R) rethrows -> R {
		_ = s.wait(timeout: DispatchTime.distantFuture)
		defer { s.signal() }
		return try f()
	}
}

let iterations = 10_000_000

class TestClass {
	var testVariable: Int = 0
	init() {
	}
	func increment() {
		testVariable += 1
	}
}

class MutexPerformanceTests: XCTestCase {
	
	func testPThreadSyncCapturingClosurePerformance() {
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
	
	func testPThreadSyncGenericParamPerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				total = mutex.sync_generic_param(&total) { t in
					return t + 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testDispatchSemaphorePerformance() {
		let mutex = DispatchSemaphoreWrapper()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				total = mutex.sync {
					return total + 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testPThreadSyncSameFilePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				mutex.sync_same_file {
					total += 1
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
	
	func testPThreadInlinePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				pthread_mutex_lock(&mutex.underlyingMutex)
				total += 1
				pthread_mutex_unlock(&mutex.underlyingMutex)
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testDispatchSyncPerformance() {
		let queue = DispatchQueue(label: "")
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				queue.sync(flags: []) {
					total += 1
				}
			}
			XCTAssert(total == iterations)
		}
	}
	
	func testSpinLockInlinePerformance() {
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
	
	@available(OSX 10.12, *)
	func testUnfairLockInlinePerformance() {
		var lock = os_unfair_lock()
		measure { () -> Void in
			var total = 0
			for _ in 0..<iterations {
				os_unfair_lock_lock(&lock)
				total += 1
				os_unfair_lock_unlock(&lock)
			}
			XCTAssert(total == iterations)
		}
	}
}
