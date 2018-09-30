//
//  CwlUtils_iOSTestAppUITests.swift
//  CwlUtils_iOSTestAppUITests
//
//  Created by Matt Gallagher on 2016/18/04.
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

import XCTest

class CwlUtils_iOSTestAppUITests: XCTestCase {
	override func setUp() {
		super.setUp()
		
		// Put setup code here. This method is called before the invocation of each test method in the class.
		
		// In UI tests it is usually best to stop immediately when a failure occurs.
		continueAfterFailure = false
		// UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
		XCUIApplication().launch()

		// In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func testAlerts() {
		let app = XCUIApplication()
		app.buttons["Trigger site handled error"].tap()
		
		let theFilePathCouldnTBeOpenedBecauseThereIsNoSuchFileAlert = app.alerts["The file “path” couldn’t be opened because there is no such file."]
		let okButton = theFilePathCouldnTBeOpenedBecauseThereIsNoSuchFileAlert.buttons["OK"]
		okButton.tap()
		
		let triggerUnanticipatedErrorButton = app.buttons["Trigger unanticipated error"]
		triggerUnanticipatedErrorButton.tap()
		okButton.tap()
		
		triggerUnanticipatedErrorButton.tap()
		let copyDetailsButton = theFilePathCouldnTBeOpenedBecauseThereIsNoSuchFileAlert.buttons["Copy details"]
		copyDetailsButton.tap()
	}
}
