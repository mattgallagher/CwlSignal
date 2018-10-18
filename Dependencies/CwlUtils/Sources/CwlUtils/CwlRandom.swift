//
//  CwlRandom.swift
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

#if !swift(>=4.2)
	public protocol RandomNumberGenerator {
		mutating func next() -> UInt64
	}
	public struct SystemRandomNumberGenerator: RandomNumberGenerator {
		public init() {}
		public mutating func next() -> UInt64 {
			var value: UInt64 = 0
			arc4random_buf(&value, MemoryLayout<UInt64>.size)
			return value
		}
	}
#endif

public protocol RandomGenerator: RandomNumberGenerator {
	mutating func randomize(buffer: UnsafeMutableRawBufferPointer)
}

extension RandomGenerator {
	public mutating func randomize<Value>(value: inout Value) {
		withUnsafeMutablePointer(to: &value) { ptr in
			self.randomize(buffer: UnsafeMutableRawBufferPointer(start: ptr, count: MemoryLayout<Value>.size))
		}
	}
}

public struct DevRandom: RandomGenerator {
	class FileDescriptor {
		let value: CInt
		init() {
			value = open("/dev/urandom", O_RDONLY)
			precondition(value >= 0)
		}
		deinit {
			close(value)
		}
	}
	
	let fd: FileDescriptor
	public init() {
		fd = FileDescriptor()
	}
	
	public mutating func randomize(buffer: UnsafeMutableRawBufferPointer) {
		let result = read(fd.value, buffer.baseAddress, buffer.count)
		precondition(result == buffer.count)
	}
	
	public mutating func next() -> UInt64 {
		var bits: UInt64 = 0
		withUnsafeMutablePointer(to: &bits) { ptr in
			self.randomize(buffer: UnsafeMutableRawBufferPointer(start: ptr, count: MemoryLayout<UInt64>.size))
		}
		return bits
	}
}

public struct Xoshiro: RandomNumberGenerator {
	public typealias StateType = (UInt64, UInt64, UInt64, UInt64)

	private var state: StateType = (0, 0, 0, 0)

	public init() {
		var dr = DevRandom()
		dr.randomize(value: &state)
	}
	
	public init(seed: StateType) {
		self.state = seed
	}
	
	public mutating func next() -> UInt64 {
		// Derived from public domain implementation of xoshiro256** here:
		// http://xoshiro.di.unimi.it
		// by David Blackman and Sebastiano Vigna
		let x = state.1 &* 5
		let result = ((x &<< 7) | (x &>> 57)) &* 9
		let t = state.1 &<< 17
		state.2 ^= state.0
		state.3 ^= state.1
		state.1 ^= state.2
		state.0 ^= state.3
		state.2 ^= t
		state.3 = (state.3 &<< 45) | (state.3 &>> 19)
		return result
	}
}

public struct MersenneTwister: RandomNumberGenerator {
	// 312 words of storage is 13 x 6 x 4
	private typealias StateType = (
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,

		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,

		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,

		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
		UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64
	)
	
	private var state_internal: StateType = (
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	)
	private var index: Int
	private static let stateCount: Int = 312
	
	public init() {
		var dr = DevRandom()
		dr.randomize(value: &state_internal)
		index = MersenneTwister.stateCount
	}
	
	public init(seed: UInt64) {
		index = MersenneTwister.stateCount
		withUnsafeMutablePointer(to: &state_internal) { $0.withMemoryRebound(to: UInt64.self, capacity: MersenneTwister.stateCount) { state in
			state[0] = seed
			for i in 1..<MersenneTwister.stateCount {
				state[i] = 6364136223846793005 &* (state[i &- 1] ^ (state[i &- 1] >> 62)) &+ UInt64(i)
			}
		} }
	}

	public mutating func next() -> UInt64 {
		if index == MersenneTwister.stateCount {
			withUnsafeMutablePointer(to: &state_internal) { $0.withMemoryRebound(to: UInt64.self, capacity: MersenneTwister.stateCount) { state in
				let n = MersenneTwister.stateCount
				let m = n / 2
				let a: UInt64 = 0xB5026F5AA96619E9
				let lowerMask: UInt64 = (1 << 31) - 1
				let upperMask: UInt64 = ~lowerMask
				var (i, j, stateM) = (0, m, state[m])
				repeat {
					let x1 = (state[i] & upperMask) | (state[i &+ 1] & lowerMask)
					state[i] = state[i &+ m] ^ (x1 >> 1) ^ ((state[i &+ 1] & 1) &* a)
					let x2 = (state[j] & upperMask) | (state[j &+ 1] & lowerMask)
					state[j] = state[j &- m] ^ (x2 >> 1) ^ ((state[j &+ 1] & 1) &* a)
					(i, j) = (i &+ 1, j &+ 1)
				} while i != m &- 1
				
				let x3 = (state[m &- 1] & upperMask) | (stateM & lowerMask)
				state[m &- 1] = state[n &- 1] ^ (x3 >> 1) ^ ((stateM & 1) &* a)
				let x4 = (state[n &- 1] & upperMask) | (state[0] & lowerMask)
				state[n &- 1] = state[m &- 1] ^ (x4 >> 1) ^ ((state[0] & 1) &* a)
			} }
			
			index = 0
		}
		
		var result = withUnsafePointer(to: &state_internal) { $0.withMemoryRebound(to: UInt64.self, capacity: MersenneTwister.stateCount) { ptr in
			return ptr[index]
		} }
		index = index &+ 1

		result ^= (result >> 29) & 0x5555555555555555
		result ^= (result << 17) & 0x71D67FFFEDA60000
		result ^= (result << 37) & 0xFFF7EEE000000000
		result ^= result >> 43

		return result
	}
}
