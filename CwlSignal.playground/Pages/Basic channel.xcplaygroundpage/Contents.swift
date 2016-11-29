/*:
# Basic channel

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## The createPair function

The CwlSignal library is centered around the Signal type; a one-way communication channel.

The `(SignalInput, Signal)` pair returned from `createPair` are the two ends of the channel and can be passed around your program to locations where values are emitted or where values are needed.

The `subscribeValues` function creates a `SignalEndpoint which allows us to extract values from the channel. The endpoint maintains the lifetime of the channel – when the endpoint is released, the channel will be closed and all resources cleaned up.

---
*/
import CwlSignal

// Create an input/output pair
let (input, signal) = Signal<Int>.createPair()

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

// You'd normally store the endpoint in a parent and let ARC control its lifetime.
endpoint.cancel()
/*:
---

[Next page: Serial pipelines - transform](@next)

[Previous page: Introduction](@previous)

*/
