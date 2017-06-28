/*:
# Serial pipelines - channel

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Nicer syntax for pipelines

Programming with `Signal` involves building lots of little pipelines. `SignalChannel` provides cleaner syntax for building piplines.

A `SignalChannel` is usually just a `SignalInput` and a `Signal` (same as the tuple returned from `Signal.create()`) but you can transform the `SignalChannel` and it applies the transform to the `Signal` half, returning another `SignalChannel` wrapping the old input and new signal (or, in some cases, just the old input).

---
*/
import CwlSignal

// Create an input/output pair
let (input, endpoint) = Signal<Int>.channel()
	.map { $0 * 2 }
	.subscribeValues { print("Value received: \($0)") }

// Send values to the input end
input.send(value: 1)
input.send(value: 2)
input.send(value: 3)
input.close()

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - combine](@next)

[Previous page: Serial pipelines - map](@previous)
*/
