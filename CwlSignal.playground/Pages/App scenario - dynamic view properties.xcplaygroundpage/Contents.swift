/*:

# App scenario, part 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Dynamic view properties

This page creates and maintains a view with an "Add to favorites" button that is enabled if (and only if) both of the following are true:

1. the user is logged in
2. the file selection is non-empty

The login status and the number of selected files are also displayed in the view as a checkbox and a text label. Neither of these are "real" (they cycle through states on a timer) but they should allow you to see how everything is connected and updated.

The most important part of the code are the three "dynamic properties" at the bottom of the `loadView` function. These take data provided by incoming signals and apply the result to the views.

## Using the Assistant View

To display the "view" for this playgrounds page, you should enable the Playgrounds "Timeline" Assistant View. To do this,

1. Make sure you can see Assistant Editor (from the menubar: "View" → "Assistant Editor" → "Show Assistant Editor").
2. Use the toolbar at the top of the Assistant Editor to select "Timeline" (the popup you need is to the right of the "< >" arrows but to the left of the filename/filepath.

After the page has run, you should be able to use the "timeline" slider to move forwards and backwards in time and see how the view state changed in response to the two state values.

---
 */
import Cocoa
import CwlSignal
import PlaygroundSupport

// Create an instance of our view controller and handle a few other Swift 3/4 differences on macOS.
#if swift(>=4)
	let controller = ViewController(nibName: nil, bundle: nil)
	let center = NSStackView.Gravity.center
	let required = NSLayoutConstraint.Priority.required
	let onState = NSControl.StateValue.on
	let offState = NSControl.StateValue.off
#else
	let controller = ViewController(nibName: nil, bundle: nil)!
	let center = NSStackViewGravity.center
	let required = NSLayoutPriorityRequired
	let onState = NSOnState
	let offState = NSOffState
#endif
	
PlaygroundPage.current.liveView = controller.view

// This is a dummy Login class. Every 1.5 seconds, it toggles login on the background thread
class Login {
	let signal = Signal.interval(.fromSeconds(1.5)).map { v in v % 2 == 0 }.continuous(initialValue: false)
}

// This is a FileSelection class. Every 0.5 seconds, it changes the number of selected files on the main thread
class FileSelection {
	let signal = Signal.interval(.fromSeconds(0.5), context: .main).map { v in Array<Int>(repeating: 0, count: v % 3) }.continuous(initialValue: Array<Int>())
}

class ViewController: NSViewController {
	// Child controls
	let addToFavoritesButton = NSButton(title: "Add to favorites", target: nil, action: nil)
	let loggedInStatusButton = NSButton(checkboxWithTitle: "Logged In", target: nil, action: nil)
	let filesSelectedLabel = NSTextField(labelWithString: "")

	// Connections to model objects
	let login = Login()
	let fileSelection = FileSelection()
	var endpoints = [Cancellable]()

	override func loadView() {
		// The view is an NSStackView (for layout convenience)
		let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
		
		// Set static properties
		view.orientation = .vertical
		view.setHuggingPriority(required, for: .horizontal)

		// Construct the view tree
		view.addView(addToFavoritesButton, in: center)
		view.addView(loggedInStatusButton, in: center)
		view.addView(filesSelectedLabel, in: center)
		view.layoutSubtreeIfNeeded()
		
		// Configure dynamic properties
		endpoints += login.signal.subscribe(context: .main) { r in
			self.loggedInStatusButton.state = (r.value ?? false) ? onState : offState
		}
		endpoints += fileSelection.signal.subscribe(context: .main) { r in
			self.filesSelectedLabel.stringValue = "Selected file count: \(r.value?.count ?? 0)"
		}
		endpoints += login.signal.combineLatest(second: fileSelection.signal) { $0 && !$1.isEmpty }.subscribe(context: .main) { result in
			self.addToFavoritesButton.isEnabled = result.value ?? false
		}
		
		// Set the view
		self.view = view
	}
}
/*:
---

[Previous page: App scenario - threadsafe key-value storage](@previous)
*/
