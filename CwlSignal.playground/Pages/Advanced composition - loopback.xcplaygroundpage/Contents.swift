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

signal.combine(loopbackSignal, initialState: [Result<String, SignalEnd>](), context: .global) { (queue: inout [Result<String, SignalEnd>], either: EitherResult2<String, ()>) in
	switch either {
	case .result1(let r) where queue.isEmpty:
		print("Received input \(r). Sending immediately.")
		queue.append(r)
		return .single(r)
	case .result1(.success(let v)):
		print("Received input \(v). This will be inserted at the start of the queue.")
		queue.insert(.success(v), at: 1)
		return .none
	case .result1(.failure(let e)):
		print("Received \(e). This will be added to the end of the queue.")
		queue.append(.failure(e))
		return .none
	case .result2(.success):
		print("Received completion notification for \(queue[0])")
		queue.remove(at: 0)
		if !queue.isEmpty {
			print("Dequeuing \(queue[0])")
			return .single(queue[0])
		}
		return .none
	case .result2(.failure(let e)):
		return .end(e)
	}
}.transform(context: .global) { (r: Result<String, SignalEnd>) in
	// A 0.1 second sleep is used to simulate heavy processing
	Thread.sleep(forTimeInterval: 0.1)
	
	// Notify that we're ready for the next item
	print("Finished processing \(r)")
	loopbackInput.send(())

	// Emit the output
	return .single(r)
}.subscribeUntilEnd { (r: Result<String, SignalEnd>) in
	// Wait until the signal is complete
	switch r {
	case .failure: semaphore.signal()
	default: break
	}
}

input.send("a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k")
input.complete()

semaphore.wait()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: App scenario - threadsafe key-value storage](@next)

[Previous page: Advanced composition - nested operators](@previous)
*/
