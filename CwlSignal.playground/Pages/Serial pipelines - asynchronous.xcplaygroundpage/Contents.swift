/*:

# Serial pipelines 4: asynchrony

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Using the `context` parameter.

Most functions in CwlSignal that accept a closure or other processing function will also take a `context` parameter immediately before the closure. This `context` specifies the execution context where the closure or function should run.

By default, this `context` is `.direct` (specifying that the closure should be directly invoked like a regular function) but you can specify an asynchronous context (like one of the Dispatch global concurrent queues or a private queue) to have the signal processed asychronously. In this way, reactive programming can snake across multiple contexts, multiple threads and multiple delays over time.

> `Signal` will ensure that values sent through the channel are delivered in-order, even if the context is concurrent.

---
 */
import CwlSignal

let semaphore = DispatchSemaphore(value: 0)
let completionContext = Exec.asyncQueue()

// Create an input/output pair
let (input, endpoint) = Signal<Int>.channel()
	.map(context: .default) { value in
		// Perform the background work
		return sqrt(Double(value)) }
	.subscribe(context: completionContext) { result in
		// Deliver to a completion thread.
		switch result {
		case .success(let value): print(value)
		case .failure: print("Done"); semaphore.signal()
		}
	}

// Send values to the input end
input.send(values: 1, 2, 3, 4, 5, 6, 7, 8, 9)
input.close()

// In reactive programming, blocking is normally "bad" but we need to block or the playground will finish before the background work.
semaphore.wait()

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - combine](@next)

[Previous page: Serial pipelines - channel](@previous)
*/
