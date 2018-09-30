//
//  CwlStackFrame.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/02/26.
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

import Darwin

#if SWIFT_PACKAGE
import CwlFrameAddress
#endif

/// A utility class for walking through stack frames.
public struct StackFrame {
	/// The underlying data of the struct is a basic UInt. A value of 0 represents an invalid frame.
	public let address: UInt
	
	/// The return address is pushed onto the stack immediately ahead of the previous frame pointer. If `self.address` is `0` this will return `0`
	/// - returns: the return address for the stack frame identified by `address`
	public var returnAddress: UInt { get {
		guard address != 0 else { return 0 }
		return UnsafeMutablePointer<UInt>(bitPattern: address)!.advanced(by: FP_LINK_OFFSET).pointee
	} }

	/// Preferred constructor gives the "current" StackFrame (where "current" refers to the frame that invokes this function). Also returns the `stackBounds` for use in subsequent calls to `next`.
	/// - returns: a `StackFrame` representing the caller's stack frame and `stackBounds` which should be passed into any future calls to `next`.
	@inline(never)
	public static func current() -> (frame: StackFrame, stackBounds: ClosedRange<UInt>) {
		let stackBounds = currentStackBounds()
		let frame = StackFrame(address: frame_address())
		
		if !stackBounds.contains(frame.address) || !isAligned(frame.address) {
			return (StackFrame(address: 0), stackBounds: stackBounds);
		}
		
		return (frame: frame.next(inBounds: stackBounds), stackBounds: stackBounds)
	}

	/// Follow the frame link pointer and return the result as another StackFrame.
	/// - returns: a `StackFrame` representing the stack frame after self, if it exists and is valid.
	public func next(inBounds stackBounds: ClosedRange<UInt>) -> StackFrame {
		guard address != 0 else { return self }
		let nextFrameAddress = UnsafeMutablePointer<UInt>(bitPattern: address)?.pointee
		if !stackBounds.contains(nextFrameAddress!) || !isAligned(nextFrameAddress!) || (nextFrameAddress ?? 0) <= address {
			return StackFrame(address: 0)
		}
		
		return StackFrame(address: nextFrameAddress!)
	}
}

/// Traverses the frames on current stack and gathers the return addresses for traversed stack frames as an array of UInt.
/// - parameter skip: number of stack frames to skip over before copying return addresses to the result array.
/// - parameter maximumAddresses: limit on the number of return addresses to return (default is `Int.max`)
/// - returns: The array of return addresses on the current stack within the skip/maximumAddresses bounds.
@inline(never)
public func callStackReturnAddresses(skip: UInt = 0, maximumAddresses: Int = Int.max) -> [UInt] {
	guard maximumAddresses > 0 else { return [] }

	var result = [UInt]()
	var skipsRemaining = skip
	var addressesRemaining = maximumAddresses

	let maximumReserve = 32
	result.reserveCapacity(maximumAddresses < maximumReserve ? maximumAddresses : maximumReserve)

	var (frame, bounds) = StackFrame.current()
	var returnAddress = frame.returnAddress
	
	while returnAddress != 0 && addressesRemaining > 0 {
		if skipsRemaining > 0 {
			skipsRemaining -= 1
		} else {
			result.append(returnAddress)
			addressesRemaining -= 1
		}
		frame = frame.next(inBounds: bounds)
		returnAddress = frame.returnAddress
	}
	
	return result
}

// These values come from:
// http://www.opensource.apple.com/source/Libc/Libc-997.90.3/gen/thread_stack_pcs.c
#if arch(x86_64)
	let ISALIGNED_MASK: UInt = 0xf
	let ISALIGNED_RESULT: UInt = 0
	let FP_LINK_OFFSET = 1
#elseif arch(i386)
	let ISALIGNED_MASK: UInt = 0xf
	let ISALIGNED_RESULT: UInt = 8
	let FP_LINK_OFFSET = 1
#elseif arch(arm) || arch(arm64)
	let ISALIGNED_MASK: UInt = 0x1
	let ISALIGNED_RESULT: UInt = 0
	let FP_LINK_OFFSET = 1
#endif

/// Use the pthread functions to get the bounds of the current stack as a closed interval.
/// - returns: a closed interval containing the memory address range for the current stack
private func currentStackBounds() -> ClosedRange<UInt> {
	let currentThread = pthread_self()
	let t = UInt(bitPattern: pthread_get_stackaddr_np(currentThread))
	return ((t - UInt(bitPattern: pthread_get_stacksize_np(currentThread))) ... t)
}

/// We traverse the stack using "downstack links". To avoid problems with these links, we ensure that frame pointers are "aligned" (valid stack frames are 16 byte aligned on x86 and 2 byte aligned on ARM).
/// - parameter address: the address to analyze
/// - returns: true if `address` is aligned according to stack rules for the current architecture
private func isAligned(_ address: UInt) -> Bool {
	return (address & ISALIGNED_MASK) == ISALIGNED_RESULT
}

/// Get the calling function's address and look it up, attempting to find the symbol.
/// NOTE: This is mostly useful in debug environements. Outside this, non-public functions and images without symbols will return incomplete information.
/// - parameter skipCount: the number of stack frames to skip over before analyzing
/// - returns: the `dladdr` identifier for the specified frame, if one exists
@inline(never)
public func callingFunctionIdentifier(skipCount: UInt = 0) -> String {
	let address = callStackReturnAddresses(skip: skipCount + 1, maximumAddresses: 1).first ?? 0
	return AddressInfo(address: address).symbol
}
