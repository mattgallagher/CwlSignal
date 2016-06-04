//
//  CwlMutexTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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
import XCTest
import CwlUtils

#if PERFORMANCE_TESTS
extension PThreadMutex {
	private func fastsync<R>(@noescape f: () throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f()
	}
}
private func sync<R>(mutex: PThreadMutex, @noescape f: () throws -> R) rethrows -> R {
	pthread_mutex_lock(&mutex.unsafeMutex)
	defer { pthread_mutex_unlock(&mutex.unsafeMutex) }
	return try f()
}
private struct DispatchSemaphore {
	let s = dispatch_semaphore_create(1)
	init() {}
	func sync<R>(@noescape f: () throws -> R) rethrows -> R {
		_ = dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
		defer { _ = dispatch_semaphore_signal(s) }
		return try f()
	}
}

#endif

class MutexTests: XCTestCase {
#if PERFORMANCE_TESTS
	static let iterations = 10_000_000
	
	func testPThreadSync2Performance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				mutex.sync_2(&total) { t in
					t += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testDispatchSemaphoreSlowPerformance() {
		let s = CwlUtils.DispatchSemaphore()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				s.sync {
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testDispatchSemaphorePerformance() {
		let s = DispatchSemaphore()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				s.sync {
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadFreePerformance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				sync(mutex) {
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadSlowSyncPerformance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				mutex.sync {
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadSync3Performance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				total = mutex.sync_3(&total) { t in
					return t + 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadSync4Performance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for var i in 0..<MutexTests.iterations {
				mutex.sync_4(&i, &total) { (inout i: Int, inout t: Int) in
					t = i + 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testObjcSyncPerformance() {
		let mutex = NSObject()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				objc_sync_enter(mutex)
				total += 1
				objc_sync_exit(mutex)
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadCopiedPerformance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				mutex.fastsync { t in
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testPThreadInlinePerformance() {
		let mutex = PThreadMutex()
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				pthread_mutex_lock(&mutex.unsafeMutex)
				total += 1
				pthread_mutex_unlock(&mutex.unsafeMutex)
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
		
	func testDispatchSyncPerformance() {
		let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				dispatch_sync(queue) {
					total += 1
				}
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
	
	func testSpinLockPerformance() {
		var lock = OS_SPINLOCK_INIT
		measureBlock { () -> Void in
			var total = 0
			for _ in 0..<MutexTests.iterations {
				OSSpinLockLock(&lock)
				total += 1
				OSSpinLockUnlock(&lock)
			}
			XCTAssert(total == MutexTests.iterations)
		}
	}
#endif

	func testPthreadMutex() {
		let mutex1 = PThreadMutex()
		
		let e1 = expectationWithDescription("Block1 not invoked")
		mutex1.sync {
			e1.fulfill()
			let reenter: Void? = mutex1.trySync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
		}
		
		let mutex2 = PThreadMutex(type: .Recursive)

		let e2 = expectationWithDescription("Block2 not invoked")
		let e3 = expectationWithDescription("Block3 not invoked")
		mutex2.sync {
			e2.fulfill()
			let reenter: Void? = mutex2.trySync() {
				e3.fulfill()
			}
			XCTAssert(reenter != nil)
		}
		
		let e4 = expectationWithDescription("Block4 not invoked")
		let r = mutex1.sync { n -> Int in
			e4.fulfill()
			let reenter: Void? = mutex1.trySync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
			return 13
		}
		XCTAssert(r == 13)
		
		waitForExpectationsWithTimeout(0, handler: nil)
	}
}
