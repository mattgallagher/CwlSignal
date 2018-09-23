/*:
# Serial pipelines 3: channel

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Contents](Contents) page.

## Nicer syntax for pipelines

Programming with `Signal` involves building lots of little pipelines. A "channel" provides cleaner syntax for building piplines.

A `SignalChannel` wraps the same `SignalInput` and `Signal` that are returned from `Signal.create()` but you can apply transformations directly to the `SignalChannel` and it applies the transform to the `Signal` half, returning another `SignalChannel` wrapping the old input and new signal or other result from the transform. This lets you construct a signal pipeline with multiple stages in a single, linear expression.

The constructor `Signal<Value>.channel()` is usually used for starting a channel with a `SignalInput` (variants exist for starting with different kinds of inputs). It is uncommon to use `SignalChannel` directly since its full name is clumsy (`SignalChannel<InputValue, Input, OutputValue, Output>`). If you want to declare a `SignalChannel` variable, you might prefer the typealias, `SignalPair<InputValue, OutputValue>` instead.

Here's the example from the previous page, using `Signal<Int>.channel()` instead of `Signal<Int>.create()`.

---
*/
import CwlSignal

// On the previous page, this line required two separate lines and an otherwise unusued `signal` declaration.
let (input, output) = Signal.channel().map { $0 * 2 }.subscribeValues { print("Value received: \($0)") }

// Send values to the input end
input.send(1, 2, 3)
input.close()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - asynchronous](@next)

[Previous page: Serial pipelines - map](@previous)
*/
