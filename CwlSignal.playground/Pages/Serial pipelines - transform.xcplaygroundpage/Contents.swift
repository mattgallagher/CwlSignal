/*:

# Serial pipelines 1: transform

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## The `transform` function

The previous example merely passed values from the input through to the endpoint. The real strength of reactive programming starts when we add multiple stages to the channel that process values as they pass through.

There are lots of different "operator" functions for chaining `Signal` instances together (including names like `map` and `flatMap` that you might recognize from `Sequence` and `Collection` processing in Swift) but most are implemented on top of the underlying `transform` function.

In this example, we turn each `Int` value that passes through the channel into an equal number of `Beep` strings.

---
 */
import CwlSignal

let (i, o) = Signal<Int>.create()

// Transform into signal that emits the string "Beep", a number of times equal to the integer received
let endpoint = o.transform { (result: Result<Int>, next: SignalNext<String>) in
	switch result {
	case .success(let intValue): (0..<intValue).forEach { _ in next.send(value: "Beep") }
	case .failure(let error): next.send(error: error)
	}
}.subscribeValues { value in
	// In this example, we use `subscribeValues` which works like `subcribe` but unwraps the `Result<T>` automatically, ignoring errors (good if you don't need to know about end-of-stream conditions).
	print(value)
}

i.send(value: 3)
i.close()

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Serial pipelines - map](@next)

[Previous page: Basic channel](@previous)
*/
