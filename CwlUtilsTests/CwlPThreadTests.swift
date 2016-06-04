//
//  CwlPthreadTests.swift
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
	private func sync<R>(_ f: @noescape () throws -> R) rethrows -> R {
		pthread_mutex_lock(&unsafeMutex)
		defer { pthread_mutex_unlock(&unsafeMutex) }
		return try f()
	}
}
private func sync<R>(_ mutex: PThreadMutex, f: @noescape () throws -> R) rethrows -> R {
	pthread_mutex_lock(&mutex.unsafeMutex)
	defer { pthread_mutex_unlock(&mutex.unsafeMutex) }
	return try f()
}
#endif

class PthreadTests: XCTestCase {
#if PERFORMANCE_TESTS
	static let iterations = 10_000_000
	
	func testPThreadSync2Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				mutex.sync_2(&total) { (t: inout Int) -> Void in
					t += 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadFreePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				sync(mutex) {
					total += 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadSlowSyncPerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				mutex.slowsync {
					total += 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadSync3Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				total = mutex.sync_3(&total) { t in
					return t + 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadSync4Performance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for var i in 0..<PthreadTests.iterations {
				mutex.sync_4(&i, &total) { (i: inout Int, t: inout Int) in
					t = i + 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testObjcSyncPerformance() {
		let mutex = NSObject()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				objc_sync_enter(mutex)
				total += 1
				objc_sync_exit(mutex)
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadCopiedPerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				mutex.sync { t in
					total += 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testPThreadInlinePerformance() {
		let mutex = PThreadMutex()
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				pthread_mutex_lock(&mutex.unsafeMutex)
				total += 1
				pthread_mutex_unlock(&mutex.unsafeMutex)
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
		
	func testDispatchSyncPerformance() {
		let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)!
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				dispatch_sync(queue) {
					total += 1
				}
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
	
	func testSpinLockPerformance() {
		var lock = OS_SPINLOCK_INIT
		measure { () -> Void in
			var total = 0
			for _ in 0..<PthreadTests.iterations {
				OSSpinLockLock(&lock)
				total += 1
				OSSpinLockUnlock(&lock)
			}
			XCTAssert(total == PthreadTests.iterations)
		}
	}
#endif

	func testPthreadMutex() {
		let mutex1 = PThreadMutex()
		
		let e1 = expectation(withDescription: "Block1 not invoked")
		mutex1.slowsync {
			e1.fulfill()
			let reenter: Void? = mutex1.trySlowsync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
		}
		
		let mutex2 = PThreadMutex(type: .Recursive)

		let e2 = expectation(withDescription: "Block2 not invoked")
		let e3 = expectation(withDescription: "Block3 not invoked")
		mutex2.slowsync {
			e2.fulfill()
			let reenter: Void? = mutex2.trySlowsync() {
				e3.fulfill()
			}
			XCTAssert(reenter != nil)
		}
		
		let e4 = expectation(withDescription: "Block4 not invoked")
		let r = mutex1.slowsync { n -> Int in
			e4.fulfill()
			let reenter: Void? = mutex1.trySlowsync() {
				XCTFail()
			}
			XCTAssert(reenter == nil)
			return 13
		}
		XCTAssert(r == 13)
		
		waitForExpectations(withTimeout: 0, handler: nil)
	}
}
