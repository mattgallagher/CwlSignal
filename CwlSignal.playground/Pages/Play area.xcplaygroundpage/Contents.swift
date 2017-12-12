/*:

# Experiment with CwlSignal

This page contains a couple quick and simple examples you can play with to try and understand some of the basics of CwlSignal.

*/
import CwlSignal

print("Prints ghost and pumpkin on their own lines, then stops:")

// A lazily `generate`d sequence of strings that feeds into `subscribeValuesWhile`, a subscribe function that manages the endpoint internally (which is convenient in unscoped locations like playgrounds where there's no context in which to store the endpoint).
Signal<String>.generate { input in
	if let i = input {
		i.send(values: "👻", "🎃", "👹", "😈")
	}
}.subscribeValuesWhile {
	print($0)
	
	// Stop immediately after the pumpkin"
	return $0 == "🎃" ? false : true
}

print("Aggregates four smileys into single string:")

// Signal.from(values:) creates a signal using the provided values and `toSequence` offers synchronous conversion back to a Swift `Sequence` type. The `aggregate` operator turns a signal of many values into a signal of one value (in this case, by concatenating the strings). The `next()` function is the Swift Standard Library Sequence function – it gets the only value in the sequence after the `reduce` operator collapsed the four smileys down to a single string.
let aggregated = Signal<String>
	.from(values: ["😀", "🙃", "😉", "🤣"])
	.aggregate("") { return $0 + $1 }
	.toSequence()
	.next()!
print(aggregated)
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

*/

