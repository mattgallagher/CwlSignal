//
//  XCTestExpectationFulfillOnMain.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/08/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import Foundation
import XCTest

public extension XCTestExpectation {
	/// Xcode 8 beta 6 sometimes times out in waitForExpectations *despite* the expectations being fulfilled. I suspect this is a bug in XCTest but I've added this extension to perform the fulfill on the main thread (which appears to avoid the problem).
	func fulfillOnMain() {
		if Thread.isMainThread {
			fulfill()
		} else {
			DispatchQueue.main.async { self.fulfill() }
		}
	}
}
