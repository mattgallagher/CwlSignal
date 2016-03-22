//
//  CwlAddressInfo.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/02/26.
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

import Darwin

/// A wrapper around dl_info, used for symbolicating instruction addresses.
public struct AddressInfo {
	private let info: dl_info
	
	/// Address for which this struct was constructed
	public let address: UInt
	
	/// Construct for an address
	public init(address: UInt) {
		self.address = address

		var i = dl_info()
		dladdr(UnsafePointer<Void>(bitPattern: address), &i)
		self.info = i
	}
	
	/// -returns: the "image" (shared object pathname) for the instruction
	public var image: String {
		if info.dli_fname != nil, let fname = String.fromCString(info.dli_fname), _ = fname.rangeOfString("/", options: NSStringCompareOptions.BackwardsSearch, range: nil, locale: nil) {
			return (fname as NSString).lastPathComponent
		} else {
			return "???"
		}
	}
	
	/// - returns: the symbol nearest the address
	public var symbol: String {
		if let sname = String.fromCString(info.dli_sname) {
			return sname
		} else if let _ = String.fromCString(info.dli_fname) {
			return self.image
		} else {
			return String(format: "0x%1x", info.dli_saddr)
		}
	}
	
	/// - returns: the address' offset relative to the nearest symbol
	public var offset: Int {
		if let _ = String.fromCString(info.dli_sname) {
			return info.dli_saddr.distanceTo(UnsafeMutablePointer<Void>(bitPattern: address))
		} else if let _ = String.fromCString(info.dli_fname) {
			return info.dli_fbase.distanceTo(UnsafeMutablePointer<Void>(bitPattern: address))
		} else {
			return info.dli_saddr.distanceTo(UnsafeMutablePointer<Void>(bitPattern: address))
		}
	}
	
	/// - parameter index: the stack frame index
	/// - returns: a formatted string matching that used by NSThread.callStackSymbols
	public func formattedDescriptionForIndex(index: Int) -> String {
		return self.image.nulTerminatedUTF8.withUnsafeBufferPointer { (imageBuffer: UnsafeBufferPointer<UTF8.CodeUnit>) -> String in
			return String(format: "%-4ld%-35s 0x%016llx %@ + %ld", index, imageBuffer.baseAddress, self.address, self.symbol, self.offset)
		}
	}
}

/// Get the calling function's address and look it up, attempting to find the symbol.
/// NOTE: This is mostly useful in debug environements. Outside this, non-public functions and images without symbols will return incomplete information.
/// - parameter skipCount: the number of stack frames to skip over before analyzing
/// - returns: the `dladdr` identifier for the specified frame, if one exists
@inline(never)
public func callingFunctionIdentifier(skipCount skipCount: UInt = 0) -> String {
	let address = callStackReturnAddresses(skip: skipCount + 1, maximumAddresses: 1).first ?? 0
	return AddressInfo(address: address).symbol
}

/// When applied to the output of callStackReturnAddresses, produces identical output to the execinfo function "backtrace_symbols" or NSThread.callStackSymbols
/// - parameter addresses: an array of memory addresses, generally as produced by `callStackReturnAddresses`
/// - returns: an array of formatted, symbolicated stack frame descriptions.
public func symbolsForCallStackAddresses(addresses: [UInt]) -> [String] {
	return addresses.enumerate().map { (index: Int, address: UInt) -> String in
		return AddressInfo(address: address).formattedDescriptionForIndex(index)
	}
}
