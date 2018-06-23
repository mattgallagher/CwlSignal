/*:

# Advanced composition

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Introduction](Introduction) page.

## Graph loops

In some cases, you want a loop in your graph. A reason you might want this is to send a signal to the head of the graph when an element is emitted from the tail (allowing you to carefully manage how many elements are processing in the middle at any given time).

You're not allowed to subscribe an antecedent (earlier) signal directly to the output of a postcedent (later) signal. It's difficult to do by accident but you'll see a *precondition failure* error if you use the `bind(to:)` function to try and permanently link the output of a `Signal` with a `SignalInput` that feeds into the `Signal`.

However, while you're not allowed to create a loop in the graph itself, you can hold onto a preceeding `SignalInput` in a subsequent transformation function and `send` values to that `SignalInput`, which has a similar loopback effect. Re-entrancy will never occur during this type of loopback (if the value propagates through the graph to an in-use `Signal` processor, the value will be queued until the `Signal` is idle, like with any other `send`).

In the following example, all the values 'b' to 'k' will be queued while 'a' is still processing. Queueing one item while the next processor is busy is standard behavior but this graph uses its own queue to queue in *reverse* order. So 'a' will be processed first but then the items will be emitted from 'k' to 'b'.

---
*/
import CwlSignal

let (input, signal) = Signal<String>.create()
let (loopbackInput, loopbackSignal) = Signal<()>.create()
let semaphore = DispatchSemaphore(value: 0)

signal.combine(loopbackSignal, initialState: [Result<String>](), context: .global) { (queue: inout [Result<String>], either: EitherResult2<String, ()>, next: SignalNext<String>) in
	switch either {
	case .result1(let r) where queue.isEmpty:
		print("Received input \(r). Sending immediately.")
		queue.append(r)
		next.send(result: r)
	case .result1(let r) where r.value != nil:
		print("Received input \(r) while still processing \(queue[0]). Reverse queuing.")
		queue.insert(r, at: 1)
	case .result1(let r):
		print("Received close \(r) while still processing \(queue[0]). Forward queueing.")
		queue.append(r)
	case .result2(.success):
		print("Received completion notification for \(queue[0])")
		queue.remove(at: 0)
		if !queue.isEmpty {
			print("Dequeuing \(queue[0])")
			next.send(result: queue[0])
		}
	case .result2(.failure(let e)):
		next.send(error: e)
	}
}.transform(context: .global) { r, n in
	// A 0.1 second sleep is used to simulate heavy processing
	Thread.sleep(forTimeInterval: 0.1)
	
	// Emit the output
	n.send(result: r)
	print("Finished processing \(r)")
	
	// Notify that we're ready for the next item
	loopbackInput.send(value: ())
}.subscribeUntilEnd { (r: Result<String>) in
	// Wait until the signal is complete
	switch r {
	case .failure: semaphore.signal()
	default: break
	}
}

input.send(value: "a")
input.send(value: "b")
input.send(value: "c")
input.send(value: "d")
input.send(value: "e")
input.send(value: "f")
input.send(value: "g")
input.send(value: "h")
input.send(value: "i")
input.send(value: "j")
input.send(value: "k")
input.close()

semaphore.wait()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: App scenario - threadsafe key-value storage](@next)

[Previous page: Advanced composition - nested operators](@previous)
*/
