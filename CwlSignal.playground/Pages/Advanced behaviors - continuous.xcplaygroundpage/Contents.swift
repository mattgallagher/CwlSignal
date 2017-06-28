/*:
# Advanced behaviors 1

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Continuous

Making the signal `continuous`, as in this example, causes it to re-emit the most recent value when a new subscriber connects. Other options include `playback` (for re-emitting *all* values) or `buffer` (which lets you update a custom series of values each time a value is processed).

---
*/
import CwlSignal

// Create an input/output pair, making the output continuous before returning
//
// SOMETHING TO TRY: replace `continuous` with `playback`
let (input, output) = Signal<Int>.channel().continuous()

// Send values before a subscriber exists
input.send(value: 1)
input.send(value: 2)

print("We just sent a two but we weren't listening. Now let's subscribe and get the last value.")

// Subscribe to listen to the values output by the channel
let endpoint = output.subscribeValues { value in print(value) }

print("We're already listening so the next value will be immediately delivered to us.")

// Send a value after a subscriber exists
input.send(value: 3)

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - operators](@next)

[Previous page: Parallel composition - combine](@previous)
*/
