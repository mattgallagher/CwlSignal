/*:

# Parallel composition 2

> **This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme.** If you're seeing errors finding or building module 'CwlSignal', follow the Build Instructions on the [Contents](Contents) page.

## Merging

The `combine` operator can take a fixed number of inputs with different types. There are a number of different ways of joining signals with different types, most of them based around CwlSignal's underlying `SignalMergeSet`.

Let's look at how the different merging patterns work by exammining three different signals, "smileys", "spookeys" and "animals". In their construction, these signal differ by how they are closed ("smileys" is not closed, "spookeys" is closed normally and "animals" is closed with a `timeout` error).

---
 */
import CwlSignal

// Some signals that we'll use for the remainder of this page
let smileys = Signal<String>.from("😀", "🙃", "😉", "🤣").playback()
let spookeys = Signal<String>
	.from(
		sequence: ["👻", "🎃", "👹", "😈"],
		error: SignalComplete.closed
	)
	.playback()
let animals = Signal<String>
	.from(
		sequence: ["🐶", "🐱", "🐭", "🐨"],
		error: SignalReactiveError.timeout
	)
	.playback()
//: We can combine them into a single signal with `merge`
print("Merge:")
Signal<String>.merge(smileys, spookeys, animals).subscribeValuesUntilEnd {
	print($0, terminator: "")
}

// Should print: 😀🙃😉🤣👻🎃👹😈🐶🐱🐭🐨
/*:
NOTE: you won't be able to merge more signals after the `animals` signal because it emits an "unexpected error" (any error type except `SignalComplete`). This *unexpected* error causes the `merge` operator to immediately close, instead of running until the last input closes. This is an example of how `merge` (as well as `concat`, `flatMap` and other combining transformations) distinguish between `SignalComplete` and other kinds of error.

If the two signals were interleaved, `merge` would interleave them as they arrived. If you want one signal in its entirety, then the other, you can use `concat` but `concat` which won't emit the second signal until the first has closed. For this to work, you need to know that the first signal is guaranteed to close.

SOMETHING TO TRY: comment out the `smileys2.input.close()` line and see that the animals will never be sent.
*/
print("\n\nConcat:")
let smileys2 = Signal<String>.create()
let animals2 = Signal<String>.create()
smileys2.signal.concat(animals2.signal).subscribeValuesUntilEnd {
	print($0, terminator: "")
}
smileys2.input.send("😀")
animals2.input.send("🐶")
smileys2.input.send("🙃")
animals2.input.send("🐱")
smileys2.input.send("😉")
animals2.input.send("🐭")
smileys2.input.send("🤣")
animals2.input.send("🐨")
smileys2.input.close()
animals2.input.close()

// Should print: 😀🙃😉🤣🐶🐱🐭🐨
/*:
We can also expose a `SignalMultiInput` which lets you send or join new signals whenever you like.

Since a "multi" input is intended to be exposed in interfaces, it does not propagate errors (it merely disconnects the joined signal).

SOMETHING TO TRY: replace `multiChannel` with `channel` (so you get a regular `SignalInput` instead) and see how the input is consumed by the first `bind` causing the remaining use of the input to send no signal data (will instead return an error).
*/
print("\n\nSignalMultiInput:")
let multiInput = Signal<String>.multiChannel().subscribeValuesUntilEnd {
	print($0, terminator: "")
}
multiInput.send("Start ")
smileys.bind(to: multiInput)
spookeys.bind(to: multiInput)
animals.bind(to: multiInput)
multiInput.send(" End")

// Should print: Start 😀🙃😉🤣👻🎃👹😈🐶🐱🐭🐨 End
/*:
If you want incoming joined signals to be able close the output, you can use `SignalMergeSet`. This offers a `closePropagation` parameter that lets you control if any error or close message (`.all`) or merely non-successful errors (`.errors`) are propagated to the output – or if all attempts to close the stream, succesful or otherwise should be blocked (`.none`).

The use cases for SignalMergeSet are fairly uncommon, so there's deliberately no convenient typealias for it. Instead, we construct the tuple from `Signal` and then wrap it in a `SignalChannel`.

Notice that in this first case, the closed at the end of the `spookeys` sequence closes the whole stream and neither animals nor `End` are emitted.

SOMETHING TO TRY: replace the `.all` parameters with `.errors` or `.none`.
*/
print("\n\nSignalMergeSet:")
let mergeSet = Signal<String>.mergedChannel().subscribeValuesUntilEnd {
	print($0, terminator: "")
}
mergeSet.send("Start")
smileys.bind(to: mergeSet, closePropagation: .all)
spookeys.bind(to: mergeSet, closePropagation: .all)
animals.bind(to: mergeSet, closePropagation: .all)
mergeSet.send("End")

// Should print: Start 😀🙃😉🤣👻🎃👹😈 End


print("\n\nDone")

/*:
---

*This example writes to the "Debug Area". If it is not visible, show it from the menubar: "View" → "Debug Area" → "Show Debug Area".*

[Next page: Advanced behaviors - continuous](@next)

[Previous page: Serial pipelines - asynchronous](@previous)
*/
