/*:

# App scenario, part 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Dynamic view properties

This page shows a fictional scenario: you're selecting files to upload to a server. In the foreground, the user selects files to upload while in the background, the server connection changes between two different servers or not connected at all.

1. Checkbox (checked if connected to a server, label shows server's name)
2. Text label (show the count of selected files)
3. Add to favorites button (enabled only if server is connected *and* file selection is non-empty).

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

PlaygroundPage.current.liveView = ViewController()

// This is a dummy Server (all it has is a name).
class Server {
	let name: String
	init(name: String) { self.name = name }
	
	// The `currentServer` value changes every five seconds, on a background thread, between no server,
	// and two different named servers, to simulate changing external conditions.
	static let currentServer: Signal<Server?> = Signal
		.interval(.seconds(5))
		.map { v in v % 3 == 0 ? nil : Server(name: v % 3 == 1 ? "Peach" : "Pear") }
		.continuous(initialValue: Server(name: "Pear"))
}

// This is a FileSelection class. To simulate changing user actions, every 0.65 seconds, the number of
// selected items is changed and every 3 seconds the selection object itself is deleted or recreated.
class FileSelection {
	let selection: Signal<[Int]> = Signal
		.interval(.milliseconds(650))
		.map { v in Array<Int>(repeating: 0, count: v % 3) }
		.continuous(initialValue: Array<Int>())
	
	static let currentSelection: Signal<FileSelection?> = Signal
		.interval(.seconds(3), context: .main)
		.map { v in v % 2 == 0 ? FileSelection() : nil }
		.continuous(initialValue: FileSelection())
}

class ViewController: NSViewController {
	// Child controls
	let uploadButton = NSButton(title: "Upload selection", target: nil, action: nil)
	let serverStatusButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
	let filesSelectedLabel = NSTextField(labelWithString: "")
	
	// Maintain the lifetime of the observations as long as the view controller lasts
	var lifetimes = [Lifetime]()
	
	override func loadView() {
		// The view is an NSStackView (for layout convenience)
		let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
		
		// Set static properties
		view.orientation = .vertical
		view.setHuggingPriority(.required, for: .horizontal)
		
		// Construct the view tree
		view.addView(uploadButton, in: .center)
		view.addView(serverStatusButton, in: .center)
		view.addView(filesSelectedLabel, in: .center)
		view.layoutSubtreeIfNeeded()
		
		// Transform the current selection, which may be nil, into a stream that's empty instead of nil
		let latestSelection = FileSelection.currentSelection
			.flatMapLatest { cur in cur?.selection.map(Optional.some) ?? .just(nil) }
			.continuous()

		// Configure dynamic properties
		lifetimes += Server.currentServer
			.subscribeValues(context: .main) { [serverStatusButton] server in
				serverStatusButton.state = server == nil ? .off : .on
				serverStatusButton.title = server.map { s in "Server name: \(s.name)" } ?? "None"
			}
		lifetimes += latestSelection
			.subscribeValues(context: .main) { [filesSelectedLabel] s in
				filesSelectedLabel.stringValue = s.map { "Selected file count: \($0.count)" } ?? "Selection empty"
			}
		lifetimes += Server.currentServer
			.combineLatestWith(latestSelection) { server, selection in server != nil && selection?.isEmpty == false }
			.subscribeValues(context: .main) { [uploadButton] canUpload in uploadButton.isEnabled = canUpload }
		
		// Set the view
		self.view = view
	}
}

/*:
---

[Previous page: App scenario - threadsafe key-value storage](@previous)
*/
