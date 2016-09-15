//
//  CwlRandomPerformanceTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/06/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import Foundation
import XCTest
import CwlUtils

let PerformanceIterations = 100_000_000

class RandomPerformanceTests: XCTestCase {
	
	func testDevRandom() {
		var generator = DevRandom()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testArc4Random() {
		var generator = Arc4Random()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testLfsr258() {
		var generator = Lfsr258()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testLfsr176() {
		var generator = Lfsr176()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testConstantNonRandom() {
		var generator = ConstantNonRandom()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testXoroshiro() {
		var generator = Xoroshiro()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testXoroshiro128plus() {
		var generator = xoroshiro128plus()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testMersenneTwister() {
		var generator = MersenneTwister()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}

	func testMT19937_64() {
		var generator = MT19937_64()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.random64()
			}
			XCTAssert(sum != 0)
		}
	}
}

//
// NOTE: the following two implementations are duplicated in CwlRandomPerformanceTests.swift and in CwlRandomTests.swift file.
// The reason for this duplication is that CwlRandomPerformanceTests.swift is normally excluded from the build, so CwlRandomTests.swift can't rely on it. But CwlRandomPerformanceTests.swift needs these structs included locally because they need to be inlined (to make the performance comparison fair) and whole module optimization is disabled for this testing bundle (to allow testing across module boundaries where desired).
//

private struct MT19937_64: RandomWordGenerator {
	typealias WordType = UInt64
	var state = mt19937_64()

	init() {
		init_genrand64(&state, DevRandom.random64())
	}

	init(seed: UInt64) {
		init_genrand64(&state, seed)
	}

	mutating func random64() -> UInt64 {
		return genrand64_int64(&state)
	}

	mutating func randomWord() -> UInt64 {
		return genrand64_int64(&state)
	}
}

private struct xoroshiro128plus: RandomWordGenerator {
	typealias WordType = UInt64
	var state = xoroshiro_state(s: (DevRandom.random64(), DevRandom.random64()))

	init() {
	}

	init(seed: (UInt64, UInt64)) {
		self.state.s = seed
	}

	mutating func random64() -> UInt64 {
		return xoroshiro_next(&state)
	}

	mutating func randomWord() -> UInt64 {
		return xoroshiro_next(&state)
	}
}


