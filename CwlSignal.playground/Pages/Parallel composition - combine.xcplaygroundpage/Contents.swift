/*:

# Parallel composition 1

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## The `combine` function

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

Any number of `Signal` instances can be chained in series to form pipelines, allowing value transformations and other "stream processing" to be applied to values between the sender and the subscriber.

While there are lots of different "operator" functions for chaining `Signal` instances together (including names like `map` and `flatMap` that you might recognize from `Sequence` and `Collection` processing in Swift) most are implemented on top of the `transform` function which works as follows:

---
 */
import CwlSignal

let semaphore = DispatchSemaphore(value: 0)

// Two signals compete, over time
let intSignal = Signal<Int>.timer(interval: .fromSeconds(1), value: 1)
let doubleSignal = Signal<Double>.timer(interval: .fromSeconds(0.5), value: 0.5)

// The signals are combined – first to send a value wins
let endpoint = intSignal.combine(second: doubleSignal) { (eitherResult: EitherResult2<Int, Double>, next: SignalNext<String>) in
   switch eitherResult {
   case .result1(.success(let intValue)): next.send(value: "\(intValue)")
   case .result2(.success(let doubleValue)): next.send(value: "\(doubleValue)")
	default: break
   }
	
	// Output always closes after the first value
	next.close()
}.subscribe { result in
	switch result {
	case .success(let v): print("The smaller value is: \(v)")
	case .failure: print("Signal complete"); semaphore.signal()
	}
}

semaphore.wait()

// You'd normally store the endpoint in a parent and let ARC control its lifetime.
endpoint.cancel()
/*:
---

[Next page: Parallel composition - operators](@next)

[Previous page: Serial pipelines - map](@previous)
*/