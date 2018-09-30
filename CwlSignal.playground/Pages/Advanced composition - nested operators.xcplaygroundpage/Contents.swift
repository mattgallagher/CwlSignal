/*:

# Advanced composition

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Signals containing Signals

The following code is interesting because instead of creating and transforming *values*, the `map` operator is used to create a wholly new `Signal` (representing a new network connection). This new `Signal` is then observed by the `switchLatest` operator which abandons any previously create `Signal` to observe the newly created one.

The `timeout` function is used to enforce the timeout. There are also other functions like `materialize`, `timer` and `multicast` in use (I'll leave you to explore and understand what each does).

---
 */
import CwlSignal
import Foundation

// When a timeout value is sent to the `startWithTimeout` input, this
// class starts the `fakeConnectionLogic` connection.
// If the timeout expires before the the new connection sends a result, an error
// will be send instead of the connection result.
// If multiple attempts to start a connection occur, the subsequent attempt will
// be used and any previous attempt will be cancelled.
struct Service {
   let startWithTimeout: SignalMultiInput<DispatchTimeInterval>
   let signal: SignalMulti<Result<String>>
	
   init() {
		(startWithTimeout, signal) = Signal<DispatchTimeInterval>.multiChannel()
			.map { seconds in
				Service.fakeConnectionLogic()
					.timeout(interval: seconds)
					.materialize()
			}
			.switchLatest()
			.multicast()
			.tuple
   }
	
	static func fakeConnectionLogic() -> Signal<String> {
		// Simulate a network connection that takes a couple seconds and returns a string
		return Signal<String>.timer(interval: .seconds(2), value: "Hello, world!")
	}
}

// Our "connection" is a timer that will return a string after a fixed delay
let service = Service()

// Subscribe to the output of the service. Since we've used `materialize`, we'll get the values *and* the errors from the child `connect()` signals wrapped in `.success` cases of the enclosing `Service.signal`.
let output = service.signal.subscribe { result in
	switch result {
	case .success(.success(let message)): print("Connected with message: \(message)")
	case .success(.failure(SignalComplete.closed)): print("Connection closed successfully")
	case .success(.failure(SignalReactiveError.timeout)): print("Connection failed with timeout")
	default: print(result)
	}
}

// SOMETHING TO TRY: replace 3 seconds with 1
service.startWithTimeout.send(.seconds(3))

// Let everything run for 10 seconds.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 10.0))

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced composition - loopback](@next)

[Previous page: Advanced behaviors - capturing](@previous)
*/
