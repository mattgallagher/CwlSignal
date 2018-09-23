/*:

# Serial pipelines 2: map

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Contents](Contents) page.

## The `map` function.

Most of the time, using `transform` is a little verbose. If we only want to process values (not errors) and we want to emit the same number of values as we receive, then we can use the much simpler `map`. Along with `subscribeValues` (which extracts only values from the signal), this lets us build much simpler signal pipelines.

---
*/

import CwlSignal

// Create an input/output pair
let (input, signal) = Signal<Int>.create()

// Transform and listen to the signal
let output = signal.map { $0 * 2 }.subscribeValues { print("Value received: \($0)") }

// Send values to the input end
input.send(1, 2, 3)
input.close()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Serial pipelines - channel](@next)

[Previous page: Serial pipelines - transform](@previous)
*/
