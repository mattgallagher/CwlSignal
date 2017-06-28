/*:

# Experiment with CwlSignal

Reactive programming is not a difficult concept: you create channels, values go in one end of the channel and come out the other.

However, the number of different operators and transformations can be difficult to understand. Combined with concepts like "activation" and the structure of the signal graph being manipulated at construction or during use, it can make signal code a little difficult to understand at first glance.

This page contains a couple quick and simple examples you can play with to try and understand some of the basics of CwlSignal.

*/
import CwlSignal

// A lazily `generate`d sequence of strings that feeds into `subscribeValuesAndKeepAlive`, a subscribe function that manages the endpoint internally (which is convenient in unscoped locations like playgrounds where there's no context in which to store the endpoint).
Signal<String>.generate { input in
	if let i = input {
		i.send(value: "🤖")
		i.send(value: "🎃")
		i.send(value: "😡")
		i.send(value: "😈")
	}
}.subscribeValuesAndKeepAlive {
	print($0);
	
	// Stop immediately after the orange "pouting face"
	return $0 == "😡" ? false : true
}

// Signal.from(values:) creates a signal using the provided values and `toSequence` offers synchronous conversion back to a Swift `Sequence` type. The `reduce` operator turns a signal of many values into a signal of one value (in this case, by concatenating the strings). The `next()` function is the Swift Standard Library Sequence function – it gets the only value in the sequence after the `reduce` operator collapsed the four smileys down to a single string.
let reduced = Signal<String>
	.from(values: ["😀", "🙃", "😉", "🤣"])
	.reduce("") { return $0 + $1 }
	.toSequence()
	.next()!
print(reduced)

/*:
---

*`print` statements write to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

*/
