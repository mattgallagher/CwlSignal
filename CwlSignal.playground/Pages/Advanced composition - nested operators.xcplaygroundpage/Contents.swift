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

// This `Service` class takes a `connect` function on construction that attempts a new connection each time it is called – the result of the connect is emitted as a `Signal`.
// The `connect` signal is created every time a new value is sent to `newConnectionWithTimeout` and the value is used to apply a `timeout` to the `connect` signal.
// Additionally, the `Service` can handle multiple connection attempts and `switchLatest` will ignore all but the most recent attempt.
class Service {
   let newConnectionWithTimeout: SignalMultiInput<DispatchTimeInterval>
   let signal: SignalMulti<Result<String>>
	
   init(connect: @escaping () -> Signal<String>) {
		(newConnectionWithTimeout, signal) = Signal<DispatchTimeInterval>.multiChannel()
			.map { seconds in
				connect().timeout(interval: seconds).materialize()
			}.next { allConnectionAttempts in
				allConnectionAttempts.switchLatest()
			}.multicast().tuple
   }
}

// Our "connection" is a timer that will return a string after a fixed delay
let service = Service { Signal<String>.timer(interval: .fromSeconds(2), value: "Hello, world!") }

// Subscribe to the output of the service. Since we've used `materialize`, we'll get the values *and* the errors from the child `connect()` signals wrapped in `.success` cases of the enclosing `Service.signal`.
let endpoint = service.signal.subscribe { result in
	switch result {
	case .success(.success(let message)): print("Connected with message: \(message)")
	case .success(.failure(SignalComplete.closed)): print("Connection closed successfully")
	case .success(.failure(SignalReactiveError.timeout)): print("Connection failed with timeout")
	default: print(result)
	}
}

// Try to connect.
// If this number is greater than the `.fromSeconds` value above, the "Hello, world!" response will be sent.
// If this number is smaller than the `.fromSeconds` value above, the timeout behavior will occur.
// SOMETHING TO TRY: replace 3 seconds with 1
service.newConnectionWithTimeout.send(value: .seconds(3))

// Let everything run for 10 seconds.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 10.0))

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced composition - loopback](@next)

[Previous page: Advanced behaviors - capturing](@previous)
*/
