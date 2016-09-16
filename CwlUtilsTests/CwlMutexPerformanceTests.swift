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

private extension PThreadMutex {
	func fastsync<R>(f: () throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f()
	}
}
private func fastsync<R>(_ mutex: PThreadMutex, f: () throws -> R) rethrows -> R {
	pthread_mutex_lock(&mutex.unsafeMutex)
	defer { pthread_mutex_unlock(&mutex.unsafeMutex) }
	return try f()
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
	
	func testDispatchCurriedPerformance() {
		let queue = DispatchQueue(label: "")
		measure { () -> Void in
			let test = TestClass()
			for _ in 0..<iterations {
				queue.sync(execute: test.increment)
			}
			XCTAssert(test.testVariable == iterations)
		}
	}
	
	func testFreeFunctionWrappingPThreadPerformance() {
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
	
	func testPThreadSyncPerformance() {
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
		let queue = DispatchQueue(label: "")
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
