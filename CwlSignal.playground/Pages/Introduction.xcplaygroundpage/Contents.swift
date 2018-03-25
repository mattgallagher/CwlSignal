/*:

# Introduction

## A little about CwlSignal

CwlSignal is an implementation of "reactive programming". Reactive programming is programming by observing and transforming streams of values. In CwlSignal, this "stream of values" is called a "signal" and is managed through the `Signal` class. The stream is threadsafe, potentially asynchronous and includes logic for processing, merging and combining streams. Signals can be used to implement the observer-pattern, communication channels, command queues, dependency graphs, stream-processors, state reducers (catamorphisms) or async promises.

Processing a `Signal` uses language similar to Swift's `Collection` processing. Functions with some of the same names, including `map`, `filter`, `flatMap`, `compactMap` and `zip`. Where Swift's `Collection` usually processes values from a single buffer (e.g. an array), `Signal` processes values that will be delivered over time. Each time processing operations are applied to a `Signal`, a new `Signal` is returned and the structured of all connected `Signal`s is called the "signal graph".

### Some differences between CwlSignal an other reactive programming implementations

CwlSignal uses separate input (`SignalInput`) and output (`Signal`) interfaces – there are no "subjects". The whole signal graph is mutable, even while signals are being asynchronously delivered and everything remains threadsafe. There's no re-entrancy (it is detected and serialized using queues).

CwlSignal is "single listener by default". This means that a normal `Signal` may be transformed or subscribed just once. This is an important point for graph coherence – if a signal is exposed to multiple potential listeners, you must use multi-listener transformations (like `continuous()`, `playback()` or `multicast()`) that return `SignalMulti`, which supports multiple listeners. These multi-listener transformations encode how additional listeners will be brought up-to-speed upon joining.

An important concept in CwlSignal is "activation", which allows CwlSignal to avoid the need for ReactiveX-style "cold observables" or ReactiveSwift-style "signal producers". The idea behind activation is that values must go somewhere: either to an endpoint (where values can escape the signal graph) or to a signal that can cache values for later delivery. Until an endpoint or caching signal is added to the graph, the graph is "inactive" (sending values will have no effect) and upon activation, certain lazy generation can start (or be restarted). Between the "inactive" and "active" phases, the signal graph goes through a special phase called "activation" where cached values in the graph are delivered to new listeners. Values delivered in this special activation phase can be read separately, if desired.

## Build instructions

This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme. To satisfy this requirement:

1. You must open the CwlSignal.playground from inside the CwlSignal.xcodeproj (do not open this playground on its own).
2. Make certain the "CwlSignal_macOS.framework" is build by selecting the CwlSignal_macOS scheme (from the "Product" → "Scheme" menu or the scheme popup menu if it's available in your toolbar) and choose build ("Product" → "Build").
3. You may need to close and re-open any playground page before it will pick up the newly built framework. Close an already open playground page by pressing Command-Control-W (or selecting "Close Introduction.xcplaygroundpage" from the File menu) before clicking in the file tree to re-open.

Failure to follow these steps correctly will result in a "Playground execution failed: error: no such module 'CwlSignal'" error (along with a large number of stack frames) logged to the Debug Area (show with the "View" → "Debug Area" → "Show Debug Area" menu if it is not visible.

## Playground pages

1. [Basic input-signal pair](Basic%20input-signal%20pair)
2. [Serial pipelines - transform](Serial%20pipelines%20-%20transform)
3. [Serial pipelines - map](Serial%20pipelines%20-%20map)
4. [Serial pipelines - channel](Serial%20pipelines%20-%20channel)
5. [Serial pipelines - asynchronous](Serial%20pipelines%20-%20asynchronous)
6. [Parallel composition - combine](Parallel%20composition%20-%20combine)
7. [Parallel composition - merging](Parallel%20composition%20-%20merging)
8. [Advanced behaviors - continuous](Advanced%20behaviors%20-%20continuous)
9. [Advanced behaviors - lazy generation](Advanced%20behaviors%20-%20lazy%20generation)
10. [Advanced behaviors - capturing](Advanced%20behaviors%20-%20capturing)
11. [Advanced composition - nested operators](Advanced%20composition%20-%20nested%20operators)
12. [Advanced composition - loopback](Advanced%20composition%20-%20loopback)
13. [App scenario - threadsafe key-value storage](App%20scenario%20-%20threadsafe%20key-value%20storage)
14. [App scenario - dynamic view properties](App%20scenario%20-%20dynamic%20view%20properties)
15. And a [Play area](Play%20area) if you just want to goof around.

[Next: Basic channel](@next)
*/
