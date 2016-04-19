//
//  CwlUtils_iOSHarnessUITests.swift
//  CwlUtils_iOSHarnessUITests
//
//  Created by Matt Gallagher on 4/18/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import XCTest

class CwlUtils_iOSHarnessUITests: XCTestCase {
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

		let alertContents = app.alerts["The file “path” couldn’t be opened because there is no such file."].collectionViews

		app.buttons["Trigger site handled error"].tap()
		alertContents.buttons["OK"].tap()
		
		let unanticipatedButton = app.buttons["Trigger unanticipated error"]
		
		unanticipatedButton.tap()
		alertContents.buttons["OK"].tap()

		unanticipatedButton.tap()
		alertContents.buttons["Copy details"].tap()
	}
}
