//
//  CwlRandomTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/05/17.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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
let PerformanceIterations = 100_000_000
#endif
let VerificationIterations = 1000

class RandomTests: XCTestCase {
	func testDevRandom() {
		var generator = DevRandom()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testArc4Random() {
		var generator = Arc4Random()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testWellRng512() {
		var generator = WellRng512()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testLfsr258() {
		var generator = Lfsr258()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testLfsr176() {
		var generator = Lfsr176()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testJRand48() {
		var generator = JRand48()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testConstantNonRandom() {
		var generator = ConstantNonRandom()

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testXoroshiro() {
		var generator = Xoroshiro()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif

		var g1 = Xoroshiro(seed: (12345678, 87654321))
		var g2 = xoroshiro128plus(seed: (12345678, 87654321))
		for _ in 0..<VerificationIterations {
			XCTAssert(g1.random64() == g2.random64())
		}
	}

	func testXoroshiro128plus() {
		var generator = xoroshiro128plus()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}

	func testMersenneTwister() {
		var generator = MersenneTwister()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif

		var g1 = MersenneTwister(seed: 12345678)
		var g2 = MT19937_64(seed: 12345678)
		for _ in 0..<VerificationIterations {
			XCTAssert(g1.random64() == g2.random64())
		}
	}

	func testMT19937_64() {
		var generator = MT19937_64()
		let a = generator.random64()
		let b = generator.random64()
		let c = generator.random64()
		let d = generator.random64()

		XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")

	#if PERFORMANCE_TESTS
		measure { () -> Void in
			for _ in 0..<PerformanceIterations {
				_ = generator.random64()
			}
		}
	#endif
	}
}

public struct MT19937_64: RandomWordGenerator {
	public typealias WordType = UInt64
	var state = mt19937_64()

	public init() {
		init_genrand64(&state, DevRandom.random64())
	}

	public init(seed: UInt64) {
		init_genrand64(&state, seed)
	}

	public mutating func random64() -> UInt64 {
		return genrand64_int64(&state)
	}

	public mutating func randomWord() -> UInt64 {
		return genrand64_int64(&state)
	}
}

public struct xoroshiro128plus: RandomWordGenerator {
	public typealias WordType = UInt64
	var state = xoroshiro_state(s: (DevRandom.random64(), DevRandom.random64()))

	public init() {
	}

	public init(seed: (UInt64, UInt64)) {
		self.state.s = seed
	}

	public mutating func random64() -> UInt64 {
		return xoroshiro_next(&state)
	}

	public mutating func randomWord() -> UInt64 {
		return xoroshiro_next(&state)
	}
}

