//
//  CwlSysctl.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/02/03.
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

public enum SysctlError: Error {
	case unknown
	case malformedUTF8
	case invalidSize
	case posixError(POSIXErrorCode)
}

/// Wrapper around `sysctl` that preflights and allocates an [Int8] for the result and throws a Swift error if anything goes wrong.
public func sysctl(levels: [Int32]) throws -> [Int8] {
	return try levels.withUnsafeBufferPointer() { levelsPointer throws -> [Int8] in
		// Preflight the request to get the required data size
		var requiredSize = 0
		let preFlightResult = Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: levelsPointer.baseAddress), UInt32(levels.count), nil, &requiredSize, nil, 0)
		if preFlightResult != 0 {
			throw POSIXErrorCode(rawValue: errno).map { SysctlError.posixError($0) } ?? SysctlError.unknown
		}
		
		// Run the actual request with an appropriately sized array buffer
		let data = Array<Int8>(repeating: 0, count: requiredSize)
		let result = data.withUnsafeBufferPointer() { dataBuffer -> Int32 in
			return Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: levelsPointer.baseAddress), UInt32(levels.count), UnsafeMutableRawPointer(mutating: dataBuffer.baseAddress), &requiredSize, nil, 0)
		}
		if result != 0 {
			throw POSIXErrorCode(rawValue: errno).map { SysctlError.posixError($0) } ?? SysctlError.unknown
		}
		
		return data
	}
}

/// Generate an array of name levels (as can be used with the previous sysctl function) from a sysctl name string.
public func sysctlLevels(fromName: String) throws -> [Int32] {
	var levelsBufferSize = Int(CTL_MAXNAME)
	var levelsBuffer = Array<Int32>(repeating: 0, count: levelsBufferSize)
	try levelsBuffer.withUnsafeMutableBufferPointer { (lbp: inout UnsafeMutableBufferPointer<Int32>) throws in
		try fromName.withCString { (nbp: UnsafePointer<Int8>) throws in
			guard sysctlnametomib(nbp, lbp.baseAddress, &levelsBufferSize) == 0 else {
				throw POSIXErrorCode(rawValue: errno).map { SysctlError.posixError($0) } ?? SysctlError.unknown
			}
		}
	}
	if levelsBuffer.count > levelsBufferSize {
		levelsBuffer.removeSubrange(levelsBufferSize..<levelsBuffer.count)
	}
	return levelsBuffer
}

// Helper function used by the various int from sysctl functions, below
private func intFromSysctl(levels: [Int32]) throws -> Int64 {
	let buffer = try sysctl(levels: levels)
	switch buffer.count {
	case 4: return buffer.withUnsafeBufferPointer() { $0.baseAddress.map { $0.withMemoryRebound(to: Int32.self, capacity: 1) { Int64($0.pointee) } } ?? 0 }
	case 8: return buffer.withUnsafeBufferPointer() { $0.baseAddress.map {$0.withMemoryRebound(to: Int64.self, capacity: 1) { $0.pointee } } ?? 0 }
	default: throw SysctlError.invalidSize
	}
}

// Helper function used by the string from sysctl functions, below
private func stringFromSysctl(levels: [Int32]) throws -> String {
	let optionalString = try sysctl(levels: levels).withUnsafeBufferPointer() { dataPointer -> String? in
		dataPointer.baseAddress.flatMap { String(validatingUTF8: $0) }
	}
	guard let s = optionalString else {
		throw SysctlError.malformedUTF8
	}
	return s
}

/// Get an arbitrary sysctl value and interpret the bytes as a UTF8 string
public func sysctlString(levels: Int32...) throws -> String {
	return try stringFromSysctl(levels: levels)
}

/// Get an arbitrary sysctl value and interpret the bytes as a UTF8 string
public func sysctlString(name: String) throws -> String {
	return try stringFromSysctl(levels: sysctlLevels(fromName: name))
}

/// Get an arbitrary sysctl value and cast it to an Int64
public func sysctlInt(levels: Int32...) throws -> Int64 {
	return try intFromSysctl(levels: levels)
}

/// Get an arbitrary sysctl value and cast it to an Int64
public func sysctlInt(name: String) throws -> Int64 {
	return try intFromSysctl(levels: sysctlLevels(fromName: name))
}

public struct Sysctl {
	/// e.g. "MyComputer.local" (from System Preferences -> Sharing -> Computer Name) or
	/// "My-Name-iPhone" (from Settings -> General -> About -> Name)
	public static var hostName: String { return try! sysctlString(levels: CTL_KERN, KERN_HOSTNAME) }
	
	/// e.g. "x86_64" or "N71mAP"
	/// NOTE: this is *corrected* on iOS devices to fetch hw.model
	public static var machine: String {
		#if os(iOS) && !arch(x86_64) && !arch(i386)
			return try! sysctlString(levels: CTL_HW, HW_MODEL)
		#else
			return try! sysctlString(levels: CTL_HW, HW_MACHINE)
		#endif
	}
	
	/// e.g. "MacPro4,1" or "iPhone8,1"
	/// NOTE: this is *corrected* on iOS devices to fetch hw.machine
	public static var model: String {
		#if os(iOS) && !arch(x86_64) && !arch(i386)
			return try! sysctlString(levels: CTL_HW, HW_MACHINE)
		#else
			return try! sysctlString(levels: CTL_HW, HW_MODEL)
		#endif
	}
	
	/// e.g. "8" or "2"
	public static var activeCPUs: Int64 { return try! sysctlInt(levels: CTL_HW, HW_AVAILCPU) }
	
	/// e.g. "15.3.0" or "15.0.0"
	public static var osRelease: String { return try! sysctlString(levels: CTL_KERN, KERN_OSRELEASE) }
	
	/// e.g. 199506 or 199506
	public static var osRev: Int64 { return try! sysctlInt(levels: CTL_KERN, KERN_OSREV) }
	
	/// e.g. "Darwin" or "Darwin"
	public static var osType: String { return try! sysctlString(levels: CTL_KERN, KERN_OSTYPE) }
	
	/// e.g. "15D21" or "13D20"
	public static var osVersion: String { return try! sysctlString(levels: CTL_KERN, KERN_OSVERSION) }
	
	/// e.g. "Darwin Kernel Version 15.3.0: Thu Dec 10 18:40:58 PST 2015; root:xnu-3248.30.4~1/RELEASE_X86_64" or
	/// "Darwin Kernel Version 15.0.0: Wed Dec  9 22:19:38 PST 2015; root:xnu-3248.31.3~2/RELEASE_ARM64_S8000"
	public static var version: String { return try! sysctlString(levels: CTL_KERN, KERN_VERSION) }
	
	#if os(OSX)
		/// e.g. 2659000000 (not available on iOS)
		public static var cpuFreq: Int64 { return try! sysctlInt(name: "hw.cpufrequency") }

		/// e.g. 25769803776 (not available on iOS)
		public static var memSize: Int64 { return try! sysctlInt(levels: CTL_HW, HW_MEMSIZE) }
	#endif
}
