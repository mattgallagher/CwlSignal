/*:
# Advanced behaviors 1

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Continuous

The basic `Signal` type in CwlSignal is "single listener". This means that it is a *precondition failure* to try and subscribe or transform it more than once. The primary reason for this is that once you're allow to add multiple listeners, you need to decide how to bring each listener "up to speed" with the signal so far.

The `SignalMulti` type supports multiple listeners and the simplest way to get a `SignalMulti` is to call `continuous()` on any `Signal`. When a new listener joins a `continuous` signal, it will immediately receive the most recent value. In CwlSignal this "up to speed" data is called the "activation" signal and it is sent synchronously, even if the signal is otherwise configured for asychronous processing.

In addition to `continuous`, other `SignalMulti` options include `multicast` (multiple listeners allowed but they get no "activation" signal), `playback` (for re-emitting *all* values) or `customActivation` (which lets you create custom "activation" sequences).

---
*/
import CwlSignal

// Create an input/output pair, making the output continuous before returning
// SOMETHING TO TRY: replace `.continuous()` with `.playback()`
let (input, output) = Signal<Int>.channel().continuous().tuple

// Send values before a subscriber exists
input.send(1)
input.send(2)

print("We just sent a '2' but we weren't listening. Now let's subscribe and get the last value.")

// Subscribe to listen to the values output by the channel
let output1 = output.subscribeValues { value in print("Output 1 received: \(value)") }

print("We're already listening so the next value will be immediately delivered to us.")

// Send a value after a subscriber exists
input.send(3)

print("A new listener to the same signal will receive just the latest value.")

let output2 = output.subscribeValues { value in print("Output 2 received: \(value)") }

/*:
SOMETHING TO TRY: replace `.channel().continuous().tuple` at the top with `.create()`. In that case, `output` will be a `Signal`, instead of a `SignalMulti` and adding a second listener like this will be a "**Fatal error**". Unless you know you have a `SignalMulti` (a signal which supports multiple listeners), like the one created by `.continuous()`, you may subscribe or transform it *only once*.
*/

print("Done.")

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Parallel composition - operators](@next)

[Previous page: Parallel composition - combine](@previous)
*/
