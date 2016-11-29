/*:

# Parallel composition, part 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Some advanced operators

There are lots of different "operator" functions for merging and combining `Signal` instances. This page demonstrates `switchLatest` and `timeout` but there are many more (including the `combineLatest` used in [App scenario - dynamic view properties](App%20scenario%20-%20dynamic%20view%20properties)).

This page contains a `Service`. The service constructs an underlying signal and times out if the underlying signal runs longer than a specified timeout time. The service is complicated by the requirement that the `connect` function can be called at any time and any previous connection must be abandoned.

The `switchLatest` function is used to abandon previous connection attempts. The `timeout` function is used to enforce the timeout. There are also other functions like `materialize` and `multicast` in use (I'll leave you to guess why).

---
 */
import CwlSignal
import Foundation

/// This is the "Service". When `connect` is called, it creates a `connect` signal (using the function provided on `init`) and runs it until it either completes or a timeout expires. Connect can be called repeatedly and any previous connection attempt will be abandoned.
class Service {
   private let input: SignalInput<DispatchTimeInterval>
   
   // Instead of "handler" callbacks, output is now via this signal
   let signal: SignalMulti<Result<String>>
	
	// The behavior of this class is is encapsulated in the signal, constructed on `init`.
   init(connect: @escaping () -> Signal<String>) {
      (self.input, self.signal) = Signal<DispatchTimeInterval>.createPair { s in
      	// Return results only from the latest connection attempt
			Signal<Result<String>>.switchLatest(
	      	// Convert each incoming timeout duration into a connection attempt
				s.map { interval in connect().timeout(interval: interval, resetOnValue: false).materialize() }
			).multicast()
      }
   }

   // Calling connect just sends the timeout value to the existing signal input
   func connect(seconds: Double) {
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
	default: print("Service was probably released")
	}
}

// Try to connect
service.connect(seconds: 1.0)

// Let everything run for a 10 seconds.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 10.0))
withExtendedLifetime(endpoint) {}
/*:
---

[Next page: App scenario - threadsafe key-value storage](@next)

[Previous page: Parallel composition - combine](@previous)

*/
