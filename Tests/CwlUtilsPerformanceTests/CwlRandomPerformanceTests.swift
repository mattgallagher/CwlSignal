//
//  CwlRandomPerformanceTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/06/16.
//  Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation
import XCTest
import CwlUtils

let PerformanceIterations = 10_000_000

class RandomPerformanceTests: XCTestCase {
	
	func testDevRandom() {
		var generator = DevRandom()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testArc4Random() {
		var generator = Random.default

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testLfsr258() {
		var generator = Lfsr258()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testLfsr176() {
		var generator = Lfsr176()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testConstantNonRandom() {
		var generator = ConstantNonRandom()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testXoshiro() {
		var generator = Xoshiro()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testXoshiro256starstar() {
		var generator = Xoshiro256starstar()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testMersenneTwister() {
		var generator = MersenneTwister()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}

	func testMT19937_64() {
		var generator = MT19937_64()

		measure { () -> Void in
			var sum: UInt64 = 0
			for _ in 0..<PerformanceIterations {
				sum = sum &+ generator.next()
			}
			XCTAssert(sum != 0)
		}
	}
}

//
// NOTE: the following two implementations are duplicated in CwlRandomPerformanceTests.swift and in CwlRandomTests.swift file.
// The reason for this duplication is that CwlRandomPerformanceTests.swift is normally excluded from the build, so CwlRandomTests.swift can't rely on it. But CwlRandomPerformanceTests.swift needs these structs included locally because they need to be inlined (to make the performance comparison fair) and whole module optimization is disabled for this testing bundle (to allow testing across module boundaries where desired).
//

private struct MT19937_64: RandomNumberGenerator {
	typealias WordType = UInt64
	var state = mt19937_64()

	init() {
		var dr = DevRandom()
		init_genrand64(&state, dr.next())
	}

	init(seed: UInt64) {
		init_genrand64(&state, seed)
	}

	mutating func next() -> UInt64 {
		return genrand64_int64(&state)
	}
}

private struct Xoshiro256starstar: RandomNumberGenerator {
	var state = { () -> xoshiro_state in var dr = DevRandom(); return xoshiro_state(s: (dr.next(), dr.next(), dr.next(), dr.next())) }()

	init() {
	}

	init(seed: (UInt64, UInt64, UInt64, UInt64)) {
		self.state.s = seed
	}

	mutating func next() -> UInt64 {
		return xoshiro_next(&state)
	}
}

