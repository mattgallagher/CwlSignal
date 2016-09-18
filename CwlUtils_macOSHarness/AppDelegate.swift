//
//  AppDelegate.swift
//  CwlUtils_OSXHarness
//
//  Created by Matt Gallagher on 2016/18/04.
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

import Cocoa
import CwlUtils

func showAlert(error: NSError) {
	NSAlert(error: error).runModal()
}

@NSApplicationMain
class AppDelegate: NSResponder, NSApplicationDelegate {
	@IBOutlet weak var window: NSWindow!

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		// Insert code here to initialize your application
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}

	func process(data: NSData) {
	}
	
	func someProcessingTask1(path: String) {
		do {
			let data = try NSData(contentsOfFile: path, options: .mappedIfSafe)
			process(data: data)
		} catch let error as NSError {
			showAlert(error: error)
		}
	}

	@IBAction func someUserAction1(_ sender: AnyObject) {
		someProcessingTask1(path: "/invalid/path")
	}

	func someProcessingTask2(path: String) throws {
		try rethrowUnanticipated {
			let data = try NSData(contentsOfFile: path, options: .mappedIfSafe)
			process(data: data)
		}
	}

	@IBAction func someUserAction2(_ sender: AnyObject) {
		do {
			try someProcessingTask2(path: "/invalid/path")
		} catch {
			presentError(error as NSError)
		}
	}
}

