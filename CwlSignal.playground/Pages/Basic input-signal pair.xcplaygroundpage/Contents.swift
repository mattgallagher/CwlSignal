/*:
# Basic input-signal pair

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Contents](Contents) page.

## The create function

The CwlSignal library is centered around one-way communication channels built from the `Signal` type (and a few related friends). The input to a channel is usually a `SignalInput`, then there's a number of `Signal` stages in the middle to transform and process the data moving through the pipeline and then the pipeline ends with a `SignalOutput`.

The data moving through the pipeline are `Result<Value>` instances. This means that they may be *values*, e.g. `Result.success(Value)`, or they may be *errors*, e.g. `Result.failure(Error)` . The first error received is the end-of-stream (closes the signal). *Expected* errors are instances of `SignalComplete` (indicating signal `.closed` or sender `.cancelled`) and any other kind of error is indicates an *unexpected* error. In either case, a signal pipeline will send no further values after the first error is received.

The `(SignalInput, Signal)` pair returned from `create` lets you start building a channel from the initial input and the first intermediate `Signal`.

The `subscribe` function creates a `SignalOutput` which allows us to extract values from the channel. An output isn't just a point to extract signal values; it also maintains the lifetime of the channel. The signal only becomes "active" (ready for receiving values) when a `SignalOutput` is connected. When all outputs are released, the channel will be closed and all resources cleaned up.



---
*/
import CwlSignal

// Create an input/output pair
let (input, signal) = Signal<Int>.create()

// Subscribe to listen to the values output by the signal.
// A signal pipeline will remain active while there is an output listening.
//
// NOTE: A signal pipeline will remain active while there is an output listening.
// We don't need to retain the output here, because everything at the top level of
// a playground page is retained but in other contexts, you'll need to store the output
// in a parent, or the signal pipeline will be deactivated.
let output = signal.subscribe { result in
	switch result {
	case .success(let v): print("Value received: \(v)")
	case .failure(let e): print("Error received: \(e)")
	}
}

// Send values to the input end
input.send(1)
input.send(2)
input.send(3)

// This `close` function is the same as calling `input.send(error: SignalComplete.closed)`
input.close()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Serial pipelines - transform](@next)

[Previous page: Introduction to CwlSignal](@previous)
*/
