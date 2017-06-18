/*:

# Advanced composition

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Some advanced operators

There are lots of different "operator" functions for merging and combining `Signal` instances. This page demonstrates `switchLatest` and `timeout` but there are many more (including the `combineLatest` used in [App scenario - dynamic view properties](App%20scenario%20-%20dynamic%20view%20properties)).

This page contains a `Service`. The service constructs an underlying signal and times out if the underlying signal runs longer than a specified timeout time. The service is complicated by the requirement that the `connect` function can be called at any time and any previous connection must be abandoned.

The `switchLatest` function is used to abandon previous connection attempts. The `timeout` function is used to enforce the timeout. There are also other functions like `fromSeconds`, `timer` and `multicast` in use (I'll leave you to explore and understand what each does).

---
 */
import CwlSignal
import Foundation

// This `Service` class shows a number of piecese of logic built together. This can be a little tricky to read since a straight path through the signal pipeline jumps into and out of code syntax nestings. Here's how it looks:
// 1. When `runWithTimeout` is called, a new timeout value is sent to `input`. This value travels into the signal pipeline formed by `create` so the timeout value passes into the `create` function's trailing closure via the `s` parameter (i.e. `s` is a `Signal<DispatchTimeInterval>` carrying the latest timeout value).
// 2. Every value `v` that passes through the `s` signal is `map`ped onto (the mathematical way of saying "turned into") a new `connect` signal with a trailing `timeout` transformation. This is the primary connection with timeout logic: either the connect completes first or the timeout fires and closes the connection.
// 3. The entire connection pipeline logic is wrapped in `switchLatest` so that the `runWithTimeout` function can be called repeatedly and any previous connection attempt will simply be abandoned without consequence.
class Service {
   private let input: SignalInput<DispatchTimeInterval>
   
   // Instead of "handler" callbacks, output is now via this signal
   let signal: SignalMulti<Result<String>>
	
	// The behavior of this class is is encapsulated in the signal, constructed on `init`.
   init(connect: @escaping () -> Signal<String>) {
      (self.input, self.signal) = Signal<DispatchTimeInterval>.create { s in
			Signal<Result<String>>.switchLatest(
				s.map { v in connect().timeout(interval: v).materialize() }
			).multicast()
      }
   }

   // Calling connect just sends the timeout value to the existing signal input
   func runWithTimeout(seconds: Double) {
      input.send(value: .fromSeconds(seconds))
   }
}

// Create an instance of the service
let service = Service { Signal<String>.timer(interval: .fromSeconds(2), value: "Hello, world!") }

// Subscribe to the output of the service
let endpoint = service.signal.subscribe { result in
	switch result {
	case .success(.success(let message)): print("Connected with message: \(message)")
	case .success(.failure(SignalError.closed)): print("Connection closed successfully")
	case .success(.failure(SignalError.timeout)): print("Connection failed with timeout")
	default: print("Service end (\(result)). Service was probably released.")
	}
}

// Try to connect.
// If this number is greater than the `.fromSeconds` value above, the "Hello, world!" response will be sent.
// If this number is smaller than the `.fromSeconds` value above, the timeout behavior will occur.
// SOMETHING TO TRY: replace 3.0 seconds with 1.0
service.runWithTimeout(seconds: 3.0)

// Let everything run for a 10 seconds.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 10.0))

// You'd normally store the endpoint in a parent and let ARC automatically control its lifetime.
endpoint.cancel()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: App scenario - threadsafe key-value storage](@next)

[Previous page: Advanced behaviors - capturing](@previous)
*/
