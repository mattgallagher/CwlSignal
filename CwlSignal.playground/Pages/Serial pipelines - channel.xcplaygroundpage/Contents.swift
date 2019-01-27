/*:
# Serial pipelines 3: channel

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Contents](Contents) page.

## Nicer syntax for pipelines

Programming with `Signal` involves building lots of little pipelines which we've called "channels" – since they model a structure into which you can send values that will be communicated through to the output. However, the loose tuple of `SignalInput` and `SignalChannel` that `Signal.create()` returns is a clumsy way of manipulating this channel, requiring separate holding and manipulation of both ends.

The `Signal.channel()` function returns a `SignalChannel`. This `SignalChannel` wraps the same `SignalInput` and `Signal` that would be returned from `Signal.create()` but you can apply transformations directly to the `SignalChannel` and they are applied to the `Signal` half, returning another `SignalChannel` wrapping the old input and new signal or other result from the transform. This lets you construct a signal pipeline with multiple stages in a single, linear expression.

Here's the example from the previous page, using `Signal<Int>.channel()` instead of `Signal<Int>.create()`.

---
*/
import CwlSignal

// On the previous page, this line required two separate lines and an otherwise unusued `signal` declaration.
let input = Signal.channel().map { $0 * 2 }.subscribeValuesUntilEnd { print("Value received: \($0)") }

// Send values to the input end
input.send(1, 2, 3)
input.complete()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - asynchronous](@next)

[Previous page: Serial pipelines - map](@previous)
*/
