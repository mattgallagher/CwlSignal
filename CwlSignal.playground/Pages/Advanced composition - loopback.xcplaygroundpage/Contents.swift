/*:

# Advanced composition

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Graph loops

In some cases, you want a loop in your graph. A reason you might want this is to send a signal to the head of the graph when an element is emitted from the tail. This can be used to control how many elements are processing in the middle at a given time (queue control) or may be used when two peers are interdependent and are communicating values back and forth (co-dependency loops).

It's difficult to accidentally bind a `Signal` to one of its preceeding `SignalInput`s and if you do try this but you'll see a *precondition failure* error.

However, while you're not allowed to create a loop in the graph structure itself, you can hold onto a preceeding `SignalInput` and manually `send` values to that `SignalInput`. This will simulate the same loopback effect. Re-entrancy will never occur during this type of loopback because if the value propagates through the graph to an in-use `Signal` processor, the value will be queued until the `Signal` is idle, like with any other `send`. You can accidentally create an infinite loop if your logic has no completion state but that's true of any looping code.

The following example prevents more than one value processing at a time. When an old value finishes processing, the next values are processed in a last-in-first-out order. The result is that all the values 'b' to 'k' will be queued while 'a' is still processing but when 'a' (and each subsequent value) is completed the remaining items will be emitted in reverse order (from 'k' to 'b').

---
*/
import CwlSignal

let (input, signal) = Signal<String>.create()
let (loopbackInput, loopbackSignal) = Signal<Void>.create()
let semaphore = DispatchSemaphore(value: 0)

signal.combine(loopbackSignal, initialState: [Result<String>](), context: .global) { (queue: inout [Result<String>], either: EitherResult2<String, ()>, next: SignalNext<String>) in
	switch either {
	case .result1(let r) where queue.isEmpty:
		print("Received input \(r). Sending immediately.")
		queue.append(r)
		next.send(result: r)
	case .result1(.success(let v)):
		print("Received input \(v). This will be inserted at the start of the queue.")
		queue.insert(.success(v), at: 1)
	case .result1(.failure(let e)):
		print("Received \(e). This will be added to the end of the queue.")
		queue.append(.failure(e))
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
	loopbackInput.send(())
}.subscribeUntilEnd { (r: Result<String>) in
	// Wait until the signal is complete
	switch r {
	case .failure: semaphore.signal()
	default: break
	}
}

input.send("a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k")
input.close()

semaphore.wait()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: App scenario - threadsafe key-value storage](@next)

[Previous page: Advanced composition - nested operators](@previous)
*/
