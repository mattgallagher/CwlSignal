/*:

# App scenario, part 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Dynamic view properties

This page shows how to implement user-interface controls dependent on multiple sources of changing data using CwlSignal.

There are two data dependencies in the example:

1. User login status (changes on a background thread)
2. File selection (changes on the main thread)

In this example, the login is just a `Bool` and the file selection is just an array of `Int` – and they are automatically cycled on a timer – but they should allow you to see how everything is connected and updated.

There are three user-interface controls dependent on this data:

1. Checkbox (checked if user is logged in)
2. Text label (show the count of selected files)
3. Add to favorites button (enabled only if user is logged in *and* file selection is non-empty).

If you're reading through the code, the most important part to focus on is the three "dynamic properties" at the bottom of the `loadView` function. These take data provided by incoming signals and apply the result to the views.

## Using the Assistant View

To display the "view" for this playgrounds page, you should enable the Playgrounds "Live View" Assistant View. To do this,

1. Make sure you can see Assistant Editor (from the menubar: "View" → "Assistant Editor" → "Show Assistant Editor").
2. Use the toolbar at the top of the Assistant Editor to select "Live View" (the popup you need is to the right of the "< >" arrows but to the left of the filename/filepath.

The page will automatically animate through a series of states.

---
 */
import Cocoa
import CwlSignal
import PlaygroundSupport

PlaygroundPage.current.liveView = ViewController(nibName: nil, bundle: nil).view

// This is a dummy Login class. Every 3.0 seconds, it toggles login on the background thread
class Login {
	let signal = Signal
		.interval(.from(seconds: 3.0))
		.map { v in v % 2 == 0 }
		.continuous(initialValue: false)
}

// This is a FileSelection class. Every 0.75 seconds, it changes the number of selected files on the main thread
class FileSelection {
	let signal = Signal
		.interval(.from(seconds: 0.75), context: .main)
		.map { v in Array<Int>(repeating: 0, count: v % 3) }
		.continuous(initialValue: Array<Int>())
}

class ViewController: NSViewController {
	// Child controls
	let addToFavoritesButton = NSButton(title: "Add to favorites", target: nil, action: nil)
	let loggedInStatusButton = NSButton(checkboxWithTitle: "Logged In", target: nil, action: nil)
	let filesSelectedLabel = NSTextField(labelWithString: "")

	// Connections to model objects
	let login = Login()
	let fileSelection = FileSelection()
	var outputs = [Cancellable]()

	override func loadView() {
		// The view is an NSStackView (for layout convenience)
		let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
		
		// Set static properties
		view.orientation = .vertical
		view.setHuggingPriority(.required, for: .horizontal)

		// Construct the view tree
		view.addView(addToFavoritesButton, in: .center)
		view.addView(loggedInStatusButton, in: .center)
		view.addView(filesSelectedLabel, in: .center)
		view.layoutSubtreeIfNeeded()
		
		// Configure dynamic properties
		outputs += login.signal
			.subscribe(context: .main) { loginResult in
				self.loggedInStatusButton.state = (loginResult.value ?? false) ? .on : .off
			}
		outputs += fileSelection.signal
			.subscribe(context: .main) { r in
				self.filesSelectedLabel.stringValue = "Selected file count: \(r.value?.count ?? 0)"
			}
		outputs += login.signal
			.combineLatest(fileSelection.signal) { isLoggedIn, selectedIndices in
				isLoggedIn && !selectedIndices.isEmpty
			}
			.subscribe(context: .main) { result in
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
