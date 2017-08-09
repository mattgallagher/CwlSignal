/*:

# Parallel composition 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing the error: "no such module 'CwlSignal'" follow the Build Instructions on the [Introduction](Introduction) page.

## Merging

The `combine` operator can take a fixed number of inputs with different types. There are a number of different ways of joining signals with different types, most of them based around CwlSignal's underlying `SignalMergeSet`.

Let's look at how the different merging patterns work by exammining three different signals, "smileys", "spookeys" and "animals". In their construction, these signal differ by how they are closed ("smileys" is not closed, "spookeys" is closed normally and "animals" is closed with a cancelled error).

---
 */
import CwlSignal
let smileys = Signal<String>.from(values: ["😀", "🙃", "😉", "🤣"], error: nil).playback()
let spookeys = Signal<String>.from(values: ["👻", "🎃", "👹", "😈"], error: SignalError.closed).playback()
let animals = Signal<String>.from(values: ["🐶", "🐱", "🐭", "🐨"], error: SignalError.cancelled).playback()

//: We can combine them into a single signal with `merge`
print("Merge:")
Signal<String>.merge(smileys, spookeys, animals).subscribeValuesAndKeepAlive {
	print($0, terminator: "")
	return true
}

//: If the two signals were asynchronous, `merge` would interleave them as they arrived. If you truly want one, then the other, you can use `concat` but concat won't emit the second signal until the first has closed.
//: SOMETHING TO TRY: swap `smileys` to the front... since smileys never emits a closing `error`, the other signals won't be emitted.
print("\n\nConcat:")
spookeys.concat(animals).concat(smileys).subscribeValuesAndKeepAlive {
	print($0, terminator: "")
	return true
}

//: We can also expose a `SignalMultiInput` which lets you send or join new signals whenever you like.
//: Since `multiInput` is intended to be exposed in interfaces, it does not propagate errors (it merely disconnects the joined signal).
//: SOMETHING TO TRY: replace `multiInputChannel` with `channel` (so you get a regular `SignalInput` instead), write `_ = try? ` in front of the three `join` statements (so the code compiles) and see how the input is consumed by the first `join` causing the remaining use of the input to send no signal data (returns an error).
print("\n\nSignalMultiInput:")
let multiInput = MultiChannel<String>().subscribeValuesAndKeepAlive {
	print($0, terminator: "")
	return true
}
multiInput.send(value: "Start ")
smileys.join(to: multiInput)
spookeys.join(to: multiInput)
animals.join(to: multiInput)
multiInput.send(value: " End")

//: If you want incoming joined signals to be able close the output, you can use `SignalMergeSet`. This offers a `closePropagation` parameter that lets you control if `SignalError.closed` (.all) or other errors (.errors) are propagated to the output or not (.none).
//: Notice that in this first case, the closed at the end of the `spookeys` sequence closes the whole stream and neither animals nor `End` are emitted.
//: SOMETHING TO TRY: replace the `.all` parameters with `.errors` or `.none`.
print("\n\nSignalMergeSet:")
let mergeSet = MergedChannel<String>().subscribeValuesAndKeepAlive {
	print($0, terminator: "")
	return true
}
mergeSet.send(value: "Start")
_ = try? smileys.join(to: mergeSet, closePropagation: .all)
_ = try? spookeys.join(to: mergeSet, closePropagation: .all)
_ = try? animals.join(to: mergeSet, closePropagation: .all)
mergeSet.send(value: "End")

print("\n\nDone")

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced behaviors - continuous](@next)

[Previous page: Serial pipelines - asynchronous](@previous)
*/
