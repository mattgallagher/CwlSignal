/*:
# Serial pipelines 3: channel

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Nicer syntax for pipelines

Programming with `Signal` involves building lots of little pipelines. `Channel` provides cleaner syntax for building piplines.

A `Channel` wraps the same `SignalInput` and `Signal` that are returned from `Signal.create()` but you can apply transformations directly to the `Channel` and it applies the transform to the `Signal` half, returning another `Channel` wrapping the old input and new signal or other result from the transform. This lets you construct a signal pipeline with multiple stages in a single, linear expression.

Since the purpose of `Channel` is syntactic convenience, it omits the word "Signal" from the type name. If you find this confusing, you can construct it through `Signal<T>.channel()`, instead.

Here's the example from the previous page, using `Channel<Int>()` instead of `Signal<Int>.create()`.

---
*/
import CwlSignal

// On the previous page, this line required two separate lines and an otherwise unusued `signal` declaration.
let (input, endpoint) = Channel<Int>().map { $0 * 2 }.subscribeValues { print("Value received: \($0)") }

// Send values to the input end
input.send(values: 1, 2, 3)
input.close()

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - asynchronous](@next)

[Previous page: Serial pipelines - map](@previous)
*/
