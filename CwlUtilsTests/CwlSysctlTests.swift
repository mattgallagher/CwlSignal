//
//  CwlSysctlTests.swift
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
import XCTest
import CwlUtils

class SysctlTests: XCTestCase {
	func testSysctl() {
		let hostName = Sysctl.hostName
		XCTAssert(hostName != "")
		
		let machine = Sysctl.machine
		
		#if arch(x86_64)
			XCTAssert(machine == "x86_64")
		#else
			XCTAssert(machine != "")
		#endif
		
		let model = Sysctl.model
		XCTAssert(model != "")
		
		let osRelease = Sysctl.osRelease
		XCTAssert(osRelease != "")
		
		let osRev = Sysctl.osRev
		XCTAssert(osRev != 0)
		
		let osType = Sysctl.osType
		XCTAssert(osType == "Darwin")
		
		let osVersion = Sysctl.osVersion
		XCTAssert(osVersion != "")
		
		let version = Sysctl.version
		XCTAssert(version.hasPrefix("Darwin Kernel Version"))
		
		let activeCPUs = Sysctl.activeCPUs
		XCTAssert(activeCPUs > 0)
		
		#if os(macOS)
			let cpuFreq = Sysctl.cpuFreq
			XCTAssert(cpuFreq > 1_000_000_000)
			
			let memSize = Sysctl.memSize
			XCTAssert(memSize > 1_000_000_000)
		#endif
	}
}
