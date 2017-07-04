/*:
# Basic input-signal pair

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## The create function

The CwlSignal library is centered around one-way communication channels built from the `Signal` type (and a few related friends). The input to a channel is usually a `SignalInput`, there's a number of `Signal` stages in the middle to transform and process the data and then the channel ends with a `SignalEndpoint`.

The `(SignalInput, Signal)` pair returned from `create` lets you start building a channel from the initial input and the first intermediate `Signal`.

The `subscribe` function creates a `SignalEndpoint` which allows us to extract values from the channel. An endpoint isn't just a point to extract signal values; it also maintains the lifetime of the channel. The signal only becomes "active" (ready for receiving values) when a `SignalEndpoint` is connected. When all endpoints are released, the channel will be closed and all resources cleaned up.

---
*/
import CwlSignal

// Create an input/output pair
let (input, signal) = Signal<Int>.create()

// Subscribe to listen to the values output by the channel
let endpoint = signal.subscribe { result in
	switch result {
	case .success(let v): print("Value received: \(v)")
	case .failure(let e): print("Error received: \(e)")
	}
}

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

[Next page: Serial pipelines - transform](@next)

[Previous page: Introduction](@previous)
*/
