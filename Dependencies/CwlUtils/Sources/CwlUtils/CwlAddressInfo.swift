//
//  CwlAddressInfo.swift
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

import Foundation

/// A wrapper around dl_info, used for symbolicating instruction addresses.
public struct AddressInfo {
	private let info: dl_info
	
	/// Address for which this struct was constructed
	public let address: UInt
	
	/// Construct for an address
	public init(address: UInt) {
		self.address = address

		var i = dl_info()
		dladdr(UnsafeRawPointer(bitPattern: address), &i)
		self.info = i
	}
	
	/// -returns: the "image" (shared object pathname) for the instruction
	public var image: String {
		if let dli_fname = info.dli_fname, let fname = String(validatingUTF8: dli_fname), let _ = fname.range(of: "/", options: .backwards, range: nil, locale: nil) {
			return (fname as NSString).lastPathComponent
		} else {
			return "???"
		}
	}
	
	/// - returns: the symbol nearest the address
	public var symbol: String {
		if let dli_sname = info.dli_sname, let sname = String(validatingUTF8: dli_sname) {
			return sname
		} else if let dli_fname = info.dli_fname, let _ = String(validatingUTF8: dli_fname) {
			return self.image
		} else {
			return String(format: "0x%1x", UInt(bitPattern: info.dli_saddr))
		}
	}
	
	/// - returns: the address' offset relative to the nearest symbol
	public var offset: Int {
		if let dli_sname = info.dli_sname, let _ = String(validatingUTF8: dli_sname) {
			return Int(address - UInt(bitPattern: info.dli_saddr))
		} else if let dli_fname = info.dli_fname, let _ = String(validatingUTF8: dli_fname) {
			return Int(address - UInt(bitPattern: info.dli_fbase))
		} else {
			return Int(address - UInt(bitPattern: info.dli_saddr))
		}
	}
	
	/// - parameter index: the stack frame index
	/// - returns: a formatted string matching that used by NSThread.callStackSymbols
	public func formattedDescription(index: Int) -> String {
		return self.image.utf8CString.withUnsafeBufferPointer { (imageBuffer: UnsafeBufferPointer<CChar>) -> String in
			#if arch(x86_64) || arch(arm64)
				return String(format: "%-4ld%-35s 0x%016llx %@ + %ld", index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.symbol, self.offset)
			#else
				return String(format: "%-4d%-35s 0x%08lx %@ + %d", index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.symbol, self.offset)
			#endif
		}
	}
}

/// When applied to the output of callStackReturnAddresses, produces identical output to the execinfo function "backtrace_symbols" or NSThread.callStackSymbols
/// - parameter addresses: an array of memory addresses, generally as produced by `callStackReturnAddresses`
/// - returns: an array of formatted, symbolicated stack frame descriptions.
public func symbolsForCallStack(addresses: [UInt]) -> [String] {
	return Array(addresses.enumerated().map { tuple -> String in
		return AddressInfo(address: tuple.element).formattedDescription(index: tuple.offset)
	})
}
