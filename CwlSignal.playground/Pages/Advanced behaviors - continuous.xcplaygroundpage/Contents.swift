/*:
# Advanced behaviors 1

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Continuous

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

Making the signal `continuous`, as in this example, causes it to re-emit the most recent value when a new subscriber connects. Other options include `playback` (for re-emitting *all* values) or `buffer` (which lets you update a custom series of values each time a value is processed).

---
*/
import CwlSignal

// Create an input/output pair, making the output continuous before returning
//
// SOMETHING TO TRY: replace `continuous` with `playback`
let (input, output) = Signal<Int>.create { signal in signal.continuous() }

// Send values before a subscriber exists
input.send(value: 1)
input.send(value: 2)

// Subscribe to listen to the values output by the channel
let endpoint = output.subscribeValues { value in print(value) }

// Send a value after a subscriber exists
input.send(value: 3)

// You'd normally store the endpoint in a parent and let ARC automatically control its lifetime.
endpoint.cancel()

/*:
---

[Next page: Parallel composition - operators](@next)

[Previous page: Advanced behaviors - lazy generation](@previous)
*/
