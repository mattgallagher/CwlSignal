/*:
# Advanced behaviors 3

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Capturing

SignalCapture allows activation values to be pulled synchronously from a signal. This provides potential solutions to scenarios where code cannot proceed without being able to obtain an immediate value. Simply put: activation in CwlSignal provides pull-based synchronous behaviors, whereas typical reactive programming is push-based and potentially asynchronous.

The `peek()` function on `Signal` and the helper type `SignalLatest` provide slightly different semantics but can also be used to synchronously obtain values from outside of the stream when interface constraints demand it.

---
*/
import CwlSignal

// Create an input/output pair, transforming the output before returning
// SOMETHING TO TRY: replace `.continuous()` with `.playback()`
let pair = Signal<Int>.channel().continuous()

// The `continuous` signal will cache the most recently sent value
pair.input.send(1)
pair.input.send(2)

// Capture the "2" activation value cached by the `continuous` signal
let capture = pair.signal.capture()

print("Activation: \(capture.values)")

// Capturing blocks signal delivery so *both* of these will be queued for later
pair.input.send(3)
pair.input.send(4)

print("Values sent during capture are paused until we subscribe.")

// Subscribing unblocks the signal so the "3" and the "4" will now be sent through.
// SOMETHING TO TRY: replace `subscribeValues` with `subscribeValues(resend: true)`
let out = capture.subscribeValues { value in print("Value: \(value)") }

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced composition - nested operators](@next)

[Previous page: Advanced behaviors - lazy generation](@previous)
*/
