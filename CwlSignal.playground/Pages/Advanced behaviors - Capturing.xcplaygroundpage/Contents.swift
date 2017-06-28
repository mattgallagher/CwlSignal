/*:
# Advanced behaviors 3

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Capturing

SignalCapture allows activation values to be pulled synchronously from a signal. This provides potential solutions to scenarios where code cannot proceed without being able to obtain an immediate value. Simply put: activation in CwlSignal provides pull-based synchronous behaviors, whereas typical reactive programming is push-based and potentially asynchronous.

The `poll` property on `Signal` and `SignalPollableEndpoint` provide slightly different semantics but can also be used to synchronously obtain values from a stream when interface constraints demands this.

---
*/
import CwlSignal

// Create an input/output pair, transforming the output before returning
let (input, output) = Signal<Int>.channel().continuous()

// The `continuous` signal will cache the most recently sent value
input.send(value: 1)
input.send(value: 2)

// Capture the "2" activation value cached by the `continuous` signal
let capture = output.capture()
let (values, error) = capture.activation()
print("Activation values: \(values)")

// Capturing blocks signal delivery so *both* of these will be queued for later
input.send(value: 3)
input.send(value: 4)

// Subscribing unblocks the signal so the "3" and the "4" will now be sent through.
let ep = capture.subscribeValues { value in print("Regular value: \(value)") }

// We normally store endpoints in a parent. Without a parent, this `cancel` lets Swift consider the variable "used".
ep.cancel()
/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced composition - nested operators](@next)

[Previous page: Advanced behaviors - lazy generation](@previous)
*/