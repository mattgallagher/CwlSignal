//
//  ViewController.swift
//  CwlUtils_iOSHarness
//
//  Created by Matt Gallagher on 4/18/16.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//

import UIKit
import CwlUtils

func showAlert(error: NSError) {
 #if os(OSX)
	  NSAlert(error: error).runModal()
 #else
	  let alert = UIAlertController(title: error.localizedDescription, message: error.localizedFailureReason, preferredStyle: UIAlertControllerStyle.Alert)
	  alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: UIAlertActionStyle.Default, handler: nil))
	  UIApplication.sharedApplication().windows[0].rootViewController!.presentViewController(alert, animated: true, completion: nil)
 #endif
}

class ViewController: UIViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func processData(data: NSData) {
	}

	func someProcessingTask1(path: String) {
		do {
			let data = try NSData(contentsOfFile: path, options: .DataReadingMappedIfSafe)
			processData(data)
		} catch let error as NSError {
			showAlert(error)
		}
	}

	@IBAction func someUserAction1(sender: AnyObject) {
		someProcessingTask1("/invalid/path")
	}

	func someProcessingTask2(path: String) throws {
		try rethrowUnanticipated {
			let data = try NSData(contentsOfFile: path, options: .DataReadingMappedIfSafe)
			processData(data)
		}
	}

	@IBAction func someUserAction2(sender: AnyObject) {
		do {
			try someProcessingTask2("/invalid/path")
		} catch {
			presentError(error as NSError)
		}
	}
}

