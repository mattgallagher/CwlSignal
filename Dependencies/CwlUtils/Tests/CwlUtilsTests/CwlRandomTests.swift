//
//  CwlRandomTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/05/17.
//  Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

#if SWIFT_PACKAGE
import ReferenceRandomGenerators
#endif

let VerificationIterations = 1000

class RandomTests: XCTestCase {
	func genericTest<Generator: RandomNumberGenerator>(generator: inout Generator, testUnique: Bool = true) {
		let a = generator.next()
		let b = generator.next()
		let c = generator.next()
		let d = generator.next()
		
		if testUnique {
			XCTAssert(a != b && a != c && a != d && b != c && b != d && c != d, "Technically, we *could* get a collision...")
		}
	}
	
	func testDevRandom() {
		var generator = DevRandom()
		genericTest(generator: &generator)
	}
	
	func testArc4Random() {
		var generator = SystemRandomNumberGenerator()
		genericTest(generator: &generator)
	}
	
	func testLfsr258() {
		var generator = Lfsr258()
		genericTest(generator: &generator)
	}
	
	func testLfsr176() {
		var generator = Lfsr176()
		genericTest(generator: &generator)
	}
	
	func testConstantNonRandom() {
		var generator = ConstantNonRandom()
		genericTest(generator: &generator, testUnique: false)
	}
	
	func testXoshiro() {
		var generator = Xoshiro()
		genericTest(generator: &generator)
		
		// Test Xoshiro against the reference implementation to verify output
		var g1 = Xoshiro(seed: (12345678, 87654321, 10293847, 29384756))
		var g2 = Xoshiro256starstar(seed: (12345678, 87654321, 10293847, 29384756))
		for _ in 0..<VerificationIterations {
			XCTAssert(g1.next() == g2.next())
		}
	}
	
	func testXoshiro256starstar() {
		var generator = Xoshiro256starstar()
		genericTest(generator: &generator)
	}
	
	func testMersenneTwister() {
		var generator = MersenneTwister()
		genericTest(generator: &generator)
		
		// Test MersenneTwister against the reference implementation to verify output
		var g1 = MersenneTwister(seed: 12345678)
		var g2 = MT19937_64(seed: 12345678)
		for _ in 0..<VerificationIterations {
			XCTAssert(g1.next() == g2.next())
		}
	}
	
	func testMT19937_64() {
		var generator = MT19937_64()
		genericTest(generator: &generator)
	}
}

// NOTE: I've moved the `ConstantNonRandom` and the two `Lfsr` implementations here. They're not advised for any common usage and I retain them here purely for performance comparison

public struct ConstantNonRandom: RandomNumberGenerator {
	public typealias WordType = UInt64
	var state: UInt64 = { var dr = DevRandom(); return dr.next() }()

	public init() {
	}

	public init(seed: UInt64) {
		self.state = seed
	}

	public mutating func next() -> UInt64 {
		return state
	}
}

public struct Lfsr258: RandomNumberGenerator {
	public typealias StateType = (UInt64, UInt64, UInt64, UInt64, UInt64)

	static let k: (UInt64, UInt64, UInt64, UInt64, UInt64) = (1, 9, 12, 17, 23)
	static let q: (UInt64, UInt64, UInt64, UInt64, UInt64) = (1, 24, 3, 5, 3)
	static let s: (UInt64, UInt64, UInt64, UInt64, UInt64) = (10, 5, 29, 23, 8)

	var state: StateType = (0, 0, 0, 0, 0)

	public init() {
		var r = DevRandom()
		repeat {
			r.randomize(value: &state.0)
		} while state.0 < Lfsr258.k.0
		repeat {
			r.randomize(value: &state.1)
		} while state.1 < Lfsr258.k.1
		repeat {
			r.randomize(value: &state.2)
		} while state.2 < Lfsr258.k.2
		repeat {
			r.randomize(value: &state.3)
		} while state.3 < Lfsr258.k.3
		repeat {
			r.randomize(value: &state.4)
		} while state.4 < Lfsr258.k.4
	}
	
	public init(seed: StateType) {
		self.state = seed
	}
	
	public mutating func next() -> UInt64 {
		// Constants from "Tables of Maximally-Equidistributed Combined LFSR Generators" by Pierre L'Ecuyer:
		// http://www.iro.umontreal.ca/~lecuyer/myftp/papers/tausme2.ps
		let l: UInt64 = 64
		let x0 = (((state.0 << Lfsr258.q.0) ^ state.0) >> (l - Lfsr258.k.0 - Lfsr258.s.0))
		state.0 = ((state.0 & (UInt64.max << Lfsr258.k.0)) << Lfsr258.s.0) | x0
		let x1 = (((state.1 << Lfsr258.q.1) ^ state.1) >> (l - Lfsr258.k.1 - Lfsr258.s.1))
		state.1 = ((state.1 & (UInt64.max << Lfsr258.k.1)) << Lfsr258.s.1) | x1
		let x2 = (((state.2 << Lfsr258.q.2) ^ state.2) >> (l - Lfsr258.k.2 - Lfsr258.s.2))
		state.2 = ((state.2 & (UInt64.max << Lfsr258.k.2)) << Lfsr258.s.2) | x2
		let x3 = (((state.3 << Lfsr258.q.3) ^ state.3) >> (l - Lfsr258.k.3 - Lfsr258.s.3))
		state.3 = ((state.3 & (UInt64.max << Lfsr258.k.3)) << Lfsr258.s.3) | x3
		let x4 = (((state.4 << Lfsr258.q.4) ^ state.4) >> (l - Lfsr258.k.4 - Lfsr258.s.4))
		state.4 = ((state.4 & (UInt64.max << Lfsr258.k.4)) << Lfsr258.s.4) | x4
		return (state.0 ^ state.1 ^ state.2 ^ state.3 ^ state.4)
	}
}

public struct Lfsr176: RandomNumberGenerator {
	public typealias StateType = (UInt64, UInt64, UInt64)

	static let k: (UInt64, UInt64, UInt64) = (1, 6, 9)
	static let q: (UInt64, UInt64, UInt64) = (5, 19, 24)
	static let s: (UInt64, UInt64, UInt64) = (24, 13, 17)

	var state: StateType = (0, 0, 0)

	public init() {
		var r = DevRandom()
		repeat {
			r.randomize(value: &state.0)
		} while state.0 < Lfsr176.k.0
		repeat {
			r.randomize(value: &state.1)
		} while state.1 < Lfsr176.k.1
		repeat {
			r.randomize(value: &state.2)
		} while state.2 < Lfsr176.k.2
	}
	
	public init(seed: StateType) {
		self.state = seed
	}
	
	public mutating func next() -> UInt64 {
		// Constants from "Tables of Maximally-Equidistributed Combined LFSR Generators" by Pierre L'Ecuyer:
		// http://www.iro.umontreal.ca/~lecuyer/myftp/papers/tausme2.ps
		let l: UInt64 = 64
		let x0 = (((state.0 << Lfsr176.q.0) ^ state.0) >> (l - Lfsr176.k.0 - Lfsr176.s.0))
		state.0 = ((state.0 & (UInt64.max << Lfsr176.k.0)) << Lfsr176.s.0) | x0
		let x1 = (((state.1 << Lfsr176.q.1) ^ state.1) >> (l - Lfsr176.k.1 - Lfsr176.s.1))
		state.1 = ((state.1 & (UInt64.max << Lfsr176.k.1)) << Lfsr176.s.1) | x1
		let x2 = (((state.2 << Lfsr176.q.2) ^ state.2) >> (l - Lfsr176.k.2 - Lfsr176.s.2))
		state.2 = ((state.2 & (UInt64.max << Lfsr176.k.2)) << Lfsr176.s.2) | x2
		return (state.0 ^ state.1 ^ state.2)
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

