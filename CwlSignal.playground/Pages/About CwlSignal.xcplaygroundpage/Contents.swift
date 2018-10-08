/*:
# About CwlSignal

CwlSignal is an implementation of reactive programming.

**Reactive programming** is programming by responding to events delivered over time. Reactive programming can be used to implement the observer-pattern, communication channels, command queues, dependency graphs, stream-processors, state reducers or promise/future-like deferred operations. The wide range of behaviors solved by reactive programming in a single overarching pattern makes it one of the most important tools in modern programming.

In CwlSignal, the streams of events are called a **signals** and are managed through the `Signal` class. The signal managed by the `Signal` class is threadsafe, potentially asynchronous and `Signal` offers tools for processing, merging and combining signals. Processing a signal uses language similar to Swift's `Collection` processing; functions including `map`, `filter`, `flatMap`, `compactMap` and `zip` apply similar logic on signals that they do on Swift collections except that the incoming and outgoing signal data is streamed over time. `Signal` processing operations can be chained, merged or branched to form a structure called a **signal graph** that connects arbitrary components in your program.
	
## CwlSignal versus other reactive programming implementations

CwlSignal is not the only implementation of reactive programming so this will be a quick look at what it does different compared to other implementations. Most reactive programming implementations are derived from the model established by the *Reactive Extentions for .NET* (Rx) which models reactive programming as a lazyily evaluated sequence of observable events.

I want to list 5 common traits in Rx implementations:

1. "observable" is a protocol with multiple implementations, sharing only the fact that you can receive a callback when the observable emits an event
2. locking, asynchrony, storage and lifecycle management need to be implemented and managed per-observable since observables don't share implementations and don't necessarily share details with surrounding observables
3. "operators" are difficult to write so knowledge of the built-in (and sometimes confusing) vocabulary of operators is required
4. connecting and subscribing lifecycles are complex so the default – to repeat all work for each new subscriber – is common, resulting in significant duplication and difficulty coordinating shared lifetimes
5. changing the structure of the observable pipeline requires using "subjects" which don't participate in lifecycle, are usually thread unsafe and can trigger accidental re-entrancy

Rx is devoted to the "observable" end of reactive programming but the focus on the output offers little to help the input end or even the middle of the pipeline. Rx's inherits its tendency to obscure the middle and input of the pipeline from functional reactive programming (the ancestor of reactive programming but focussed on continuous behaviors, not discrete events).

Functional reactive programming hides inputs as a necessity (input is a side effect and can't be represented in strict functional programming) but hiding the input and middle stages of the pipeline is annoying in an otherwise imperative programming environment. Additionally, where functional languages typically cache previous calculations (avoiding the need to recalculate), imperative Rx lacks this advantage, so the tendency of Rx to repeat work without caching or sharing is a noticeable drawback.

CwlSignal starts from a different conceptual model. Instead of using lazily evaluated observable sequences as its foundation, CwlSignal is inspired by the actor model. In CwlSignal, you build a graph of `Signal` nodes. Each node is modelled like an actor, with messages queued on input, processed in its own context and subsequent messages sent to destination `Signal`s. `SignalInput`s and `SignalOutput`s form the interface between this graph and other parts of your program.

In many cases, the effect is similar to Rx: `Signal`s perform similar work to operators in Rx and often share the same names and the graph is connected like an Rx processing pipeline.

However, compared to the 5 common traits I listed for Rx implementations, CwlSignal has the following traits:

1. there is just one implementation of `Signal` which handles receiving of data from its `SignalInput`, processing of work in the private execution context and delivery of values to listeners
2. all synchronization, delivery ordering, asychrony, graph construction are managed by the `Signal` implementation
3. operators in CwlSignal are built on underlying `Signal` operators – primarily `transform`, `combine` and `merge` – often in less than a dozen lines. The result is that custom operators are trivial to implement.
4. subscribing multiple simultaneous times will never trigger multiple calculations of the same data – if a signal graph can be simultaneously subscribed, it must be constructed with rules stating how the data is shared (e.g. caching last value, replaying all values, sharing future values only)
5. the signal graph is fully mutable in a threadsafe manner and the rules about how data is shared also ensure that the data remains appropriately coherent during these mutations – avoiding most of the problematic aspects of subjects from Rx

In general, these differences are intended to make CwlSignal more aesthetically pleasing, easier to use and less likely to accidentally trigger surprising behaviors.

## Unique features of CwlSignal

With CwlSignal, you have full control over the processing graph from the inputs (`SignalInput`) through the processing nodes (`Signal`) to the outputs (`SignalOutput`).

The signal is a stream of `Result` instances, either a value or an error. This is distinct from Rx implementations where the stream of "events" is either a value, error or completed. Using `Result` simplifies processing of streams from three cases down to two, in most cases, and interoperates better with other libraries that may also use a `Result` type.

The `Signal` class is **single listener**. This means that a normal `Signal` may be transformed or subscribed just once at any given time. This is an important point for graph coherence – if a signal is exposed to multiple potential listeners, you are forced to use multi-listener transformations (like `continuous()`, `playback()` or `multicast()`) to create the subtype `SignalMulti`, which supports multiple listeners. These multi-listener transformations encode how additional listeners will be brought up-to-speed upon joining.

> If Swift's proposed [Ownership Manifesto](https://github.com/apple/swift/blob/master/docs/OwnershipManifesto.md) is ever implemented, the `Signal` class is intended to be a non-copyable type, preventing multiple subscriptions to a `Signal` at compile-time. Until then, you must remember that multiple subscriptions to a single listener `Signal` are not permitted and will trigger a precondition failure if attempted.

An important concept in CwlSignal is **activation** which allows CwlSignal to avoid the need for Rx-style "cold observables" or ReactiveSwift-style "signal producers". The idea behind activation is that values must go somewhere: either to an output (where values can escape the signal graph) or to a signal that can cache values for later delivery. Until an output or caching signal is added to the graph, the graph is "inactive" (sending values will have no effect) and upon activation, certain lazy generation can start (or be restarted). Between the "inactive" and "active" phases, the signal graph goes through a special phase called "activation" where cached values in the graph are delivered to new listeners. Values delivered in this special activation phase can be read separately, if desired.

[Next: Basic channel](@next)

[Previous page: Contents](@previous)
*/
