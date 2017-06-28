/*:
# Advanced behaviors 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Lazy generation

In many cases, we want to defer the actual generation of values until *after* a subscriber is ready to receive them. In CwlSignal, we can use the `generate` function, which invokes its closure every time the "activation" state changes, to start after the signal graph becomes active.

The `generate` function's closure will also be invoke with a `nil` value when the signal graph *deactives* so you can clean up resources.

---
*/
import CwlSignal

// Create an output immediately but only start creating data to feed into the pipeline after a listener connects.
let output = Signal<Int>.generate { input in
   if let i = input {
		print("Generation has started")
      i.send(value: 1)
      i.send(value: 2)
      i.send(value: 3)
   }
}

print("We're just about to subscribe.")

// Subscribe to listen to the values output by the channel
let endpoint = output.subscribeValues { value in print(value) }

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
endpoint.cancel()

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced behaviors - capturing](@next)

[Previous page: Advanced behaviors - continuous](@previous)
*/
