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

// Imagine you have a function that performs some asynchronous work (in this case, the function is
// `basicAsynchronousWork` which returns a message after a few seconds). You might want to apply a
// timelimit to that work – if it doesn't finish within the time limit, you want to return a timeout
// error instead of the result of the function.
//
// When a timeout value is sent to the `startWithTimeout` input on this `TimeoutService`, the
// class starts the `asynchronousWork` function that was provided to it on construction. If the timeout
// elapses before the the asynchronous work sends a result, a `SignalReactiveError.timeout`
// will be sent instead of the connection result.
// 
// If multiple attempts to start a connection occur, any previous attempt will be cancelled and only the
// latest start will be used.
struct TimeoutService {
   let startWithTimeout: SignalMultiInput<DispatchTimeInterval>
   let signal: SignalMulti<Result<String>>
	
   init(asynchronousWork: @escaping () -> Signal<String>) {
		(startWithTimeout, signal) = Signal<DispatchTimeInterval>.multiChannel()
			.map { seconds in
				asynchronousWork()
					.timeout(interval: seconds)
					.materialize()
			}
			.switchLatest()
			.multicast()
			.tuple
   }
}

func basicAsynchronousWork() -> Signal<String> {
	// Simulate a network connection that takes a couple seconds and returns a string
	return Signal<String>.timer(interval: .seconds(2), value: "Hello, world!")
}

// Our "connection" is a timer that will return a string after a fixed delay
let service = TimeoutService(asynchronousWork: basicAsynchronousWork)

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
