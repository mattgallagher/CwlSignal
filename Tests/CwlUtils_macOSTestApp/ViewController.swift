//
//  ViewController.swift
//  CwlUtils_macOSTestApp
//
//  Created by Matt Gallagher on 2017/01/31.
//  Copyright © 2017 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

func showAlert(error: Error) {
	NSAlert(error: error).runModal()
}

class ViewController: NSViewController {

	let b = NSButton()

	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
	}

	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}

	func process(data: NSData) {
	}
	
	func someProcessingTask1(path: String) {
		do {
			let data = try NSData(contentsOfFile: path, options: .mappedIfSafe)
			process(data: data)
		} catch {
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
			presentError(error)
		}
	}
}

