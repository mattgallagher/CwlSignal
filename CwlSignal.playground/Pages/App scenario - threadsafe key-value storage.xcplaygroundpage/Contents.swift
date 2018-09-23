/*:

# App scenario 1

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## A threadsafe, notifying key-value storage

The following is a threadsafe dictionary of values. You might use something similar for the "model" in a trivial app. Even if more sophisticated storage than a dictionary is required, the pattern of updating and notifying will likely be the same.

1. The same work is involved in accessing a value once or subscribing properly so good behavior is encouraged.
2. If separate handling of initial value and subsequent values is required (e.g. using a `capture` and `subscribe` sequence as described in the previous article) the stream is correctly paused so you can't miss a notification.
3. Everything is threadsafe (the `map` closure will never be concurrently invoked and re-entrancy is not possible)
4. All changes go through the `map` function and can be coordinated there.
5. A `SignalError.cancelled` message is automatically sent to subscribers if `input` is released.

---
 */
import CwlSignal

// Create the storage
let dv = DocumentValues()

// Watch the contents
let out = dv.signal.subscribeValues { v in print("Latest update: \(v)") }

// Change the contents
dv.setValue("Hi, there.", forKey: "Oh!")
dv.removeValue(forKey: "Oh!")
dv.setValue("World", forKey: "Hello")

// We normally store outputs in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
out.cancel()

/// A threadsafe key-value storage using reactive programming
class DocumentValues {
   typealias Dict = Dictionary<AnyHashable, Any>
   typealias Tuple = (AnyHashable, Any?)
	
   private let input: SignalInput<Tuple>
   
   // Access to the data is via the signal.
   public let signal: SignalMulti<Dict>

   init() {
      // Actual values storage is encapsulated within the signal
      (self.input, self.signal) = Signal<Tuple>.channel().map(initialState: [:]) { (state: inout Dict, update: Tuple) in
			// All updates pass through this single, common function.
			switch update {
			case (let key, .some(let value)): state[key] = value
			case (let key, .none): state.removeValue(forKey: key)
			}
			return state
			
		// Convert single `Signal` into multi-subscribable `SignalMulti` with `continuous`
		}.continuous(initialValue: [:]).tuple
   }
   
	func removeValue(forKey key: AnyHashable) {
		input.send((key, nil))
	}
	
	func setValue(_ value: Any, forKey key: AnyHashable) {
		input.send((key, value))
	}
}

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: App scenario - dynamic view properties](@next)

[Previous page: Advanced composition - loopback](@previous)
*/
