/*:

# Serial pipelines 1: transform

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Contents](Contents) page.

## The `transform` function

The previous example merely passed values from the input through to the output. The real strength of reactive programming starts when we add multiple stages to the channel that process values as they pass through.

There are lots of different "operator" functions for chaining `Signal` instances together (including names like `map` and `compactMap` that you might recognize from `Sequence` and `Collection` processing in Swift) but most are implemented on top of the underlying `transform` function.

In this example, we turn each `Int` value that passes through the channel into an equal number of `Beep` strings.

---
 */
import CwlSignal

let (input, signal) = Signal<Int>.create()

// Transform into signal that emits the string "Beep", a number of times equal to the integer received
let output = signal.transform { result in
	switch result {
	case .success(let v): return .values(sequence: (0..<v).map { i in "Beep \(v): \(i + 1)" })
	case .failure(let e): return .end(e)
	}
}.subscribeValues { value in
	// In this example, we use `subscribeValues` which works like `subcribe` but unwraps the `Result<T>` automatically, ignoring errors (good if you don't need to know about end-of-stream conditions).
	print(value)
}

input.send(1)
input.send(2)
input.send(3)
input.complete()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Serial pipelines - map](@next)

[Previous page: Basic channel](@previous)
*/
