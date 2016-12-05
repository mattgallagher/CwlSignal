
//  CwlSignal.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2016/06/05.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose with or without
//  fee is hereby granted, provided that the above copyright notice and this permission notice
//  appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
//  SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
//  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
//  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
//  OF THIS SOFTWARE.
//

import Foundation

/// A composable one-way communication channel that delivers a sequence of `Result<T>` items to a `handler` function running in a potentially different execution context. Delivery is serial (FIFO) queuing as required.
///
/// The intended use case is as a serialized asynchronous change propagation framework.
///
/// The word "signal" may be used in a number of ways, so keep in mind:
///	- `Signal`: this class
///	- signal graph: one or more `Signal` instances connected together via handlers (instances of the private class `SignalHandler`)
///	- signal: the sequence of `Result` instances, or individual instances of `Result` that pass through instances of `Signal`
///	- `signal`: when used as a parameter label, refers to an instance of `Signal` (invidivual `Result` instances are identified as `result`, `value` or `error` in parameter labels).
///
/// The primary design goals for this implementation are:
///	1. All possible actions are threadsafe
///	2. No possible action results in undefined, corrupt or assertion failure behavior
///	3. Values will never be delivered out-of-order.
///	4. After a disconnection and reconnection, only values from the latest connection will be delivered.
///	5. Loops and reentrant-like behavior in the graph is permitted and reentrant delivery is simply queued to be delivered after any in-flight behavior.
///
/// That's quite a list of goals but it's largely covered by two ideas:
///	1. No user code ever invoked inside a mutex
///	2. Delivery to a `Signal` includes the "predecessor" and the "activationCount". If either fail to match the internal state of the `Signal`, then the delivery is out-of-date and can be discarded.
///
/// The first of these points is ensured through the use of `holdCount` and `DeferredWork`. The former blocks a queue while out-of-mutex work is performed. The latter defers work to be performed outside a mutex.
/// This ensures that no problematic work is performed inside a mutex but it means that we often have "in-flight" work occurring outside a mutex that might no longer be valid. So we need to combine this work identifiers that allow us to reject out-of-date work. That's where the second point becomes important.
/// The "activationCount" for an `Signal` changes any time a manual input control is generated (`SignalInput`/`SignalMergeSet`), any time a first predecessor is added or any time there are predecessors connected and the `delivery` state changes to or from `.disabled`. Combined with the fact that it is not possible to disconnect and re-add the same predecessor to a multi-input Signal (SignalMergeSet or SignalCombiner) this guarantees any messages from out-of-date but still in-flight deliveries are ignored.
///
/// While all actions are threadsafe, there are some points to keep in mind:
///	1. If a subsequent result is sent to a Signal while it is synchronously processing a previous result the subsequent result will be queued and handled on the previous thread once it completes processing. It is important to keep in mind that while synchronous processing *usually* occurs on the sending thread, it is not a guarantee. In this scenario, processing occurs on the previous thread which is now forced to do work for the subsequent thread.
///	2. For the disconnectable handler components (SignalMergeSet, SignalJunction, SignalCapture) it is possible to manipulate the graph from multiple threads at once in ways that might cause in-progress actions to be cancelled (since they are superceded by manipulation from other threads). In general, multi-threaded graph manipulation should be either avoided or considered carefully to ensure sensible results are delivered.
public class Signal<T> {
	public typealias ValueType = T
	
	// Protection for all mutable members on this class and any attached `signalHandler`.
	// NOTE: `Signal`s attached to preceeding `.sync` context `SignalProcessor`s often *share* the mutex of their preceeding `signalHandler` (for memory and performance efficiency).
	fileprivate final var mutex: PThreadMutex
	
	// The graph can be disconnected and reconnected and various actions may occur outside locks, it's helpful to determine which actions are no longer relevant. The `Signal` controls this through `delivery` and `activationCount`. The `delivery` controls the basic lifecycle of a simple connected graph through 4 phases: `.disabled` (pre-connection) -> `.sychronous` (connecting) -> `.normal` (connected) -> `.disabled` (disconnected).
	fileprivate final var delivery = SignalDelivery.disabled { didSet { itemContextNeedsRefresh = true } }
	
	// The graph can be disconnected and reconnected and various actions may occur outside locks, it's helpful to determine which actions are no longer relevant because they are associated with a phase of a previous connection.
	// When connected to a preceeding `SignalPredecessor`, `activationCount` is incremented on each connection and disconnection to ensure that actions associated with a previous phase of a previous connection are rejected. 
	// When connected to a preceeding `SignalInput`, `activationCount` is incremented solely when a new `SignalInput` is attached or the current input is invalidated (joined using an `SignalJunction`).
	fileprivate final var activationCount: Int = 0 { didSet { itemContextNeedsRefresh = true } }
	
	// Queue of values pending dispatch (NOTE: the current `item` is not stored in the queue)
	// Normally the queue is FIFO but when an `Signal` has multiple inputs, the "activation" from each input will be considered before any post-activation inputs.
	fileprivate final var queue = Deque<Result<T>>()
	
	// The queue may be blocked for one of three reasons:
	// 1. a `SignalNext` is retained outside its handler function for asynchronous processing of an item
	// 1. a `SignalCapture` handler has captured the activation but a `Signal` to receive the remainder is not currently connected
	// Accordingly, the `holdCount` should only have a value in the range [0, 2]
	fileprivate final var holdCount: UInt8 = 0
	fileprivate final var itemProcessing: Bool = false
	
	// Notifications for the inverse of `delivery == .disabled`. Accessed only through the `generate` constructor. Can be used for lazy construction/commencement, resetting to initial state on graph disconnect and reconnect or cleanup after graph deletion.
	fileprivate final var newInputSignal: Signal<SignalInput<T>?>? = nil
	
	// If there is a preceeding `Signal` in the graph, its `SignalProcessor` is stored in this variable.
	fileprivate final var preceeding: Set<OrderedSignalPredecessor>
	
	// A count of total preceeding ever added
	fileprivate final var preceedingCount: Int = 0
	
	// The destination of this `Signal`. This value is `nil` on construction and may be set only once.
	// NOTE: `SignalMulti` will never actually set a `signalHandler`. When the `attach` method is invoked, a new `Signal` is generated, attached to the `preceeding` `SignalMultiProcessor` and the `signalHandler` value on the new `Signal` is used for attachment.
	fileprivate final weak var signalHandler: SignalHandler<T>? = nil { didSet { itemContextNeedsRefresh = true } }
	
	// This is a cache of values that can be read outside the lock by the current owner of the `holdCount`.
	fileprivate final var itemContext = ItemContext<T>(activationCount: 0)
	fileprivate final var itemContextNeedsRefresh = true
	
	/// Create a manual input/output pair where values sent to the `SignalInput` are passed through the `Signal` output. The `SignalInput` will remain valid until it is replaced or the graph is deactivated.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func create() -> (input: SignalInput<T>, signal: Signal<T>) {
		let s = Signal<T>()
		var dw = DeferredWork()
		s.mutex.sync { s.updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw) }
		dw.runWork()
		return (SignalInput(signal: s, activationCount: s.activationCount), s)
	}
	
	/// Like `create` but also provides a trailing closure to transform the `Signal` normally returned from `create` and in its place, return the result of the transformation.
	///
	/// - parameter compose: a trailing closure which receices the `Signal` as a parameter and any result is returned as the second tuple parameter from this function
	///
	/// - throws: rethrows any error from the closure
	/// - returns: the `SignalInput` and compose result pair
	public static func create<U>(compose: (Signal<T>) throws -> U) rethrows -> (input: SignalInput<T>, composed: U) {
		let (i, s) = create()
		return (i, try compose(s))
	}
	
	/// Similar to `create`, in that it creates a "head" for the graph but rather than immediately providing a `SignalInput`, this function calls the `activationChange` function when the signal graph is activated and provides the newly created `SignalInput` at that time. When the graph deactivates, `nil` is sent to the `activationChange` function. If a subsequent reactivation occurs, the new `SignalInput` for the re-activation is provided.
	///
	/// NOTE: even when `context` is a concurrent context, it is guaranteed that calls to `activationChange` will be serialized.
	///
	/// - parameter context:          the `activationChange` will be invoked in this context
	/// - parameter activationChange: receives inputs on activation and nil on each deactivation
	///
	/// - returns: the constructed `Signal`
	public static func generate(context: Exec = .direct, activationChange: @escaping (_ input: SignalInput<T>?)-> Void) -> Signal<T> {
		let s = Signal<T>()
		s.newInputSignal = Signal<SignalInput<T>?>()
		s.newInputSignal?.subscribe(context: context) { r in
			switch r {
			case .success(let v): activationChange(v)
			default: break
			}
		}.keepAlive()
		return s
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func mergeSetAndSignal<S: Sequence>(_ initialInputs: S, closesOutput: Bool = false, removeOnDeactivate: Bool = false) -> (mergeSet: SignalMergeSet<T>, signal: Signal<T>) where S.Iterator.Element: Signal<T> {
		let (mergeSet, signal) = Signal<T>.mergeSetAndSignal()
		for i in initialInputs {
			mergeSet.add(i, closesOutput: closesOutput, removeOnDeactivate: removeOnDeactivate)
		}
		return (mergeSet, signal)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func mergeSetAndSignal<S: Sequence, U>(_ initialInputs: S, closesOutput: Bool = false, removeOnDeactivate: Bool = false, compose: (Signal<T>) throws -> U) rethrows -> (mergeSet: SignalMergeSet<T>, composed: U) where S.Iterator.Element: Signal<T> {
		let (mergeSet, signal) = try Signal<T>.mergeSetAndSignal(compose: compose)
		for i in initialInputs {
			mergeSet.add(i, closesOutput: closesOutput, removeOnDeactivate: removeOnDeactivate)
		}
		return (mergeSet, signal)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func mergeSetAndSignal() -> (mergeSet: SignalMergeSet<T>, signal: Signal<T>) {
		let s = Signal<T>()
		var dw = DeferredWork()
		s.mutex.sync { s.updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw) }
		dw.runWork()
		return (SignalMergeSet(signal: s), s)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func mergeSetAndSignal<U>(compose: (Signal<T>) throws -> U) rethrows -> (mergeSet: SignalMergeSet<T>, composed: U) {
		let (m, s) = mergeSetAndSignal()
		return (m, try compose(s))
	}
	
	/// Appends a `SignalEndpoint` listener to the value emitted from this `Signal`. The endpoint will "activate" this `Signal` and all direct antecedents in the graph (which may start lazy operations deferred until activation).
	///
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: the function invoked for each received `Result`
	///
	/// - returns: the created `SignalEndpoint`
	public final func subscribe(context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> SignalEndpoint<T> {
		return attach { (s, dw) in
			SignalEndpoint<T>(signal: s, dw: &dw, context: context, handler: handler)
		}
	}
	
	// Internal implementation for join(toInput:) and join(toInput:onError:)
	//
	// - parameter toInput:              an input that identifies a destination `Signal`
	// - parameter optionalErrorHandler: if nil, errors from self will be passed through to `toInput`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalJunction` and the input created by calling `disconnect` on it.
	//
	/// - returns: if `toInput` is still the current input for its `Signal`, then a `SignalJunction<T>` that allows the join to be later broken, otherwise `nil`.
	private final func join(toInput: SignalInput<T>, optionalErrorHandler: ((SignalJunction<T>, Error, SignalInput<T>) -> ())?) throws -> SignalJunction<T> {
		let disconnector = attach { (s, dw) -> SignalJunction<T> in
			return SignalJunction<T>(signal: s, dw: &dw)
		}
		if let onError = optionalErrorHandler {
			try disconnector.join(toInput: toInput, onError: onError)
		} else {
			try disconnector.join(toInput: toInput)
		}
		return disconnector
	}
	
	/// Fuses the output of this `Signal` to a manual `SignalInput<T>` so that values sent to this `Signal` are immediately sent through the `SignalInput<T>`'s `Signal`.
	///
	/// - parameter toInput: an input that identifies a destination `Signal`
	///
	/// - returns: if `toInput` is still the current input for its `Signal`, then a `SignalJunction<T>` that allows the join to be later broken, otherwise `nil`.
	@discardableResult
	public final func join(toInput: SignalInput<T>) throws -> SignalJunction<T> {
		return try join(toInput: toInput, optionalErrorHandler: nil)
	}
	
	/// Fuses the output of this `Signal` to a manual `SignalInput<T>` so that values sent to this `Signal` are immediately sent through the `SignalInput<T>`'s `Signal`.
	///
	/// - parameter toInput: an input that identifies a destination `Signal`
	/// - parameter onError: if nil, errors from self will be passed through to `toInput`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalJunction` and the input created by calling `disconnect` on it.
	///
	/// - returns: if `toInput` is still the current input for its `Signal`, then a `SignalJunction<T>` that allows the join to be later broken, otherwise `nil`.
	@discardableResult
	public final func join(toInput: SignalInput<T>, onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) throws -> SignalJunction<T> {
		return try join(toInput: toInput, optionalErrorHandler: onError)
	}
	
	/// Appends a disconnected `SignalJunction` to this `Signal` so outputs can be repeatedly joined and disconnected from this graph in the future.
	///
	/// - returns: the `SignalJunction<T>`
	@discardableResult
	public final func junction() -> SignalJunction<T> {
		return attach { (s, dw) -> SignalJunction<T> in
			return SignalJunction<T>(signal: s, dw: &dw)
		}
	}
	
	/// Appends a connected `SignalJunction` to this `Signal` so the graph can be disconnected in the future.
	///
	/// - returns: the `SignalJunction<T>` and the connected `Signal` as a pair
	@discardableResult
	public final func junctionSignal() -> (SignalJunction<T>, Signal<T>) {
		let (input, signal) = Signal<T>.create()
		let j = try! self.join(toInput: input)
		return (j, signal)
	}
	
	/// Appends a connected `SignalJunction` to this `Signal` so the graph can be disconnected in the future.
	///
	/// - returns: the `SignalJunction<T>` and the connected `Signal` as a pair
	@discardableResult
	public final func junctionSignal(onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) -> (SignalJunction<T>, Signal<T>) {
		let (input, signal) = Signal<T>.create()
		let j = try! self.join(toInput: input, onError: onError)
		return (j, signal)
	}
	
	/// Appends a handler function that transforms the value emitted from this `Signal` into a new `Signal`.
	///
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: the function invoked for each received `Result`
	///
	/// - returns: the created `Signal`
	public final func transform<U>(context: Exec = .direct, handler: @escaping (Result<T>, SignalNext<U>) -> Void) -> Signal<U> {
		return Signal<U>(processor: attach { (s, dw) in
			SignalTransformer<T, U>(signal: s, dw: &dw, context: context, handler: handler)
		})
	}
	
	/// Appends a handler function that transforms the value emitted from this `Signal` into a new `Signal`.
	///
	/// - parameter withState: the initial value for a state value associated with the handler. This value is retained and if the signal graph is deactivated, the state value is reset to this value.
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: the function invoked for each received `Result`
	///
	/// - returns: the created `Signal`
	public final func transform<S, U>(withState: S, context: Exec = .direct, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) -> Signal<U> {
		return Signal<U>(processor: attach { (s, dw) in
			SignalTransformerWithState<T, U, S>(signal: s, initialState: withState, dw: &dw, context: context, handler: handler)
		})
	}
	
	// Internal wrapper used by the `combine` functions to ignore error `Results` (which would only be due to graph changes between internal nodes) and process the values with the user handler.
	//
	// - parameter handler: the user handler
	@discardableResult
	private static func successHandler<U, V>(_ handler: @escaping (U, SignalNext<V>) -> Void) -> (Result<U>, SignalNext<V>) -> Void {
		return { (r: Result<U>, n: SignalNext<V>) in
			switch r {
			case .success(let v): handler(v, n)
			case .failure(let e): n.send(error: e)
			}
		}
	}
	
	/// Appends a handler function that receives inputs from this and another `Signal<U>`. The `handler` function applies any transformation it wishes an emits a (potentially) third `Signal` type.
	///
	/// - parameter second:  the other `Signal` that is, along with `self` used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self` or `second` as `EitherResult2<T, U>` (an enum which may contain either `.result1` or `.result2` corresponding to `self` or `second`) and sends results to an `SignalNext<V>`.
	///
	/// - returns: an `Signal<V>` which is the result stream from the `SignalNext<V>` passed to the `handler`.
	public final func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<T, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return Signal<EitherResult2<T, U>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult2<T, U>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult2<T, U>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult2<T, U>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult2<T, U>.result2)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and two other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fourth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second` or `third` as `EitherResult3<T, U, V>` (an enum which may contain either `.result1`, `.result2` or `.result3` corresponding to `self`, `second` or `third`) and sends results to an `SignalNext<W>`.
	///
	/// - returns: an `Signal<W>` which is the result stream from the `SignalNext<W>` passed to the `handler`.
	public final func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return Signal<EitherResult3<T, U, V>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result3)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and three other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fifth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter fourth:  the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second`, `third` or `fourth` as `EitherResult4<T, U, V, W>` (an enum which may contain either `.result1`, `.result2`, `.result3` or `.result4` corresponding to `self`, `second`, `third` or `fourth`) and sends results to an `SignalNext<X>`.
	///
	/// - returns: an `Signal<X>` which is the result stream from the `SignalNext<X>` passed to the `handler`.
	public final func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return Signal<EitherResult4<T, U, V, W>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result4)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and four other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) sixth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter fourth:  the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	/// - parameter fifth:   the fifth `Signal`, after `self`, `second`, `third` and `fourth`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second`, `third`, `fourth` or `fifth` as `EitherResult5<T, U, V, W, X>` (an enum which may contain either `.result1`, `.result2`, `.result3`, `.result4` or  `.result5` corresponding to `self`, `second`, `third`, `fourth` or `fifth`) and sends results to an `SignalNext<Y>`.
	///
	/// - returns: an `Signal<Y>` which is the result stream from the `SignalNext<Y>` passed to the `handler`.
	public final func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return Signal<EitherResult5<T, U, V, W, X>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result4)
		}).addPreceeding(processor: fifth.attach { (s5, dw) -> SignalCombiner<X, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s5, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result5)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	// Internal wrapper used by the `combine(withState:...)` functions to ignore error `Results` (which would only be due to graph changes between internal nodes) and process the values with the user handler.
	//
	// - parameter handler: the user handler
	@discardableResult
	private static func successHandlerWithState<S, U, V>(_ handler: @escaping (inout S, U, SignalNext<V>) -> Void) -> (inout S, Result<U>, SignalNext<V>) -> Void {
		return { (s: inout S, r: Result<U>, n: SignalNext<V>) in
			switch r {
			case .success(let v): handler(&s, v, n)
			case .failure(let e): n.send(error: e)
			}
		}
	}
	
	/// Appends a handler function that receives inputs from this and another `Signal<U>`. The `handler` function applies any transformation it wishes an emits a (potentially) third `Signal` type.
	///
	/// - parameter second:  the other `Signal` that is, along with `self` used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self` or `second` as `EitherResult2<T, U>` (an enum which may contain either `.result1` or `.result2` corresponding to `self` or `second`) and sends results to an `SignalNext<V>`.
	///
	/// - returns: an `Signal<V>` which is the result stream from the `SignalNext<V>` passed to the `handler`.
	public final func combine<S, U, V>(withState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<T, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return Signal<EitherResult2<T, U>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult2<T, U>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult2<T, U>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult2<T, U>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult2<T, U>.result2)
		}).transform(withState: withState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Appends a handler function that receives inputs from this and two other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fourth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second` or `third` as `EitherResult3<T, U, V>` (an enum which may contain either `.result1`, `.result2` or `.result3` corresponding to `self`, `second` or `third`) and sends results to an `SignalNext<W>`.
	///
	/// - returns: an `Signal<W>` which is the result stream from the `SignalNext<W>` passed to the `handler`.
	public final func combine<S, U, V, W>(withState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return Signal<EitherResult3<T, U, V>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult3<T, U, V>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult3<T, U, V>.result3)
		}).transform(withState: withState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Appends a handler function that receives inputs from this and three other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fifth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter fourth:  the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second`, `third` or `fourth` as `EitherResult4<T, U, V, W>` (an enum which may contain either `.result1`, `.result2`, `.result3` or `.result4` corresponding to `self`, `second`, `third` or `fourth`) and sends results to an `SignalNext<X>`.
	///
	/// - returns: an `Signal<X>` which is the result stream from the `SignalNext<X>` passed to the `handler`.
	public final func combine<S, U, V, W, X>(withState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return Signal<EitherResult4<T, U, V, W>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult4<T, U, V, W>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult4<T, U, V, W>.result4)
		}).transform(withState: withState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Appends a handler function that receives inputs from this and four other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) sixth `Signal` type.
	///
	/// - parameter second:  the second `Signal`, after `self` used as input to the `handler`
	/// - parameter third:   the third `Signal`, after `self` and `second`, used as input to the `handler`
	/// - parameter fourth:  the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	/// - parameter fifth:   the fifth `Signal`, after `self`, `second`, `third` and `fourth`, used as input to the `handler`
	/// - parameter context: the `Exec` context used to invoke the `handler`
	/// - parameter handler: processes inputs from either `self`, `second`, `third`, `fourth` or `fifth` as `EitherResult5<T, U, V, W, X>` (an enum which may contain either `.result1`, `.result2`, `.result3`, `.result4` or  `.result5` corresponding to `self`, `second`, `third`, `fourth` or `fifth`) and sends results to an `SignalNext<Y>`.
	///
	/// - returns: an `Signal<Y>` which is the result stream from the `SignalNext<Y>` passed to the `handler`.
	public final func combine<S, U, V, W, X, Y>(withState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return Signal<EitherResult5<T, U, V, W, X>>(processor: self.attach { (s1, dw) -> SignalCombiner<T, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result4)
		}).addPreceeding(processor: fifth.attach { (s5, dw) -> SignalCombiner<X, EitherResult5<T, U, V, W, X>> in
			SignalCombiner(signal: s5, dw: &dw, context: .direct, handler: EitherResult5<T, U, V, W, X>.result5)
		}).transform(withState: withState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and is "continuous" (multiple listeners can be attached to the `SignalMulti` and each new listener immediately receives the most recently sent value on "activation").
	///
	/// - parameter initial: the immediate value sent to any listeners that connect *before* the first value is sent through this `Signal`
	///
	/// - returns: a continuous `SignalMulti`
	public final func continuous(initial: T) -> SignalMulti<T> {
		return SignalMulti<T>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: ([initial], nil), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in
				switch r {
				case .success(let v): a = [v]
				case .failure(let e): a = []; p = e
				}
			})
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and is "continuous" (multiple listeners can be attached to the `SignalMulti` and each new listener immediately receives the most recently sent value on "activation"). Any listeners that connect before the first signal is received will receive no value on "activation".
	///
	/// - returns: a continuous `SignalMulti`
	public final func continuous() -> SignalMulti<T> {
		return SignalMulti<T>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: ([], nil), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in
				switch r {
				case .success(let v): a = [v]; p = nil
				case .failure(let e): a = []; p = e
				}
			})
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and offers full "playback" (multiple listeners can be attached to the `SignalMulti` and each new listener receives the entire history of values previously sent through this `Signal` upon "activation").
	///
	/// - returns: a playback `SignalMulti`
	public final func playback() -> SignalMulti<T> {
		return SignalMulti<T>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: ([], nil), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in
				switch r {
				case .success(let v): a.append(v)
				case .failure(let e): p = e
				}
			})
		})
	}
	
	/// Appends a new `Signal` to this `Signal`. The new `Signal` immediately activates its antecedents and caches any values it receives until this the new `Signal` itself is activated – at which point it sends all prior values upon "activation" and subsequently reverts to passthough.
	///
	/// - returns: a "cache until active" `Signal`.
	public final func cacheUntilActive() -> Signal<T> {
		return Signal<T>(processor: attach { (s, dw) in
			SignalCacheUntilActive(signal: s, dw: &dw)
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. While multiple listeners are permitted, there is no caching, activation signal or other changes inherent in this new `Signal`.
	///
	/// - returns: a "multicast" `SignalMulti`.
	public final func multicast() -> SignalMulti<T> {
		return SignalMulti<T>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: false, values: ([], nil), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in })
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents. Every time a value is received, it is passed to an "updater" which updates the array of activation values (multiple listeners can be attached to the `SignalMulti` and each new listener receives the array as a series of activation values).
	///
	/// - returns: a buffered `SignalMulti`
	public final func buffer(context: Exec = .direct, initials: Array<T> = [], updater: @escaping (_ activationValues: inout Array<T>, _ preclosed: inout Error?, _ result: Result<T>) -> Void) -> SignalMulti<T> {
		return SignalMulti<T>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: (initials, nil), isUserUpdated: true, dw: &dw, context: context, updater: updater)
		})
	}
	
	/// Constructs a `SignalMulti` with an array of "activation" values and a closing error.
	///
	/// - parameter values: an array of values
	/// - parameter error:  the closing error for the `Signal`
	///
	/// - returns: an `SignalMulti`
	public static func preclosed<S: Sequence>(values: S, error: Error = SignalError.closed) -> SignalMulti<T> where S.Iterator.Element == T {
		return SignalMulti<T>(processor: Signal<T>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: (Array(values), error), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in })
		})
	}
	
	/// Constructs a `SignalMulti` with an array of "activation" values and a closing error.
	///
	/// - parameter error:  the closing error for the `Signal`
	///
	/// - returns: an `SignalMulti`
	public static func preclosed(error: Error = SignalError.closed) -> SignalMulti<T> {
		return SignalMulti<T>(processor: Signal<T>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: ([], error), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in })
		})
	}
	
	/// Constructs a `SignalMulti` with an array of "activation" values and a closing error.
	///
	/// - parameter error:  the closing error for the `Signal`
	///
	/// - returns: an `SignalMulti`
	public static func preclosed(_ value: T, error: Error = SignalError.closed) -> SignalMulti<T> {
		return SignalMulti<T>(processor: Signal<T>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, alwaysActive: true, values: ([value], error), isUserUpdated: false, dw: &dw, context: .direct, updater: { a, p, r in })
		})
	}
	
	/// Appends an immediately activated handler that captures any activation values from this `Signal`. The captured values can be accessed from the `SignalCapture<T>` using the `activation()` function. The `SignalCapture<T>` can then be joined to further `Signal`s using the `join(toInput:)` function on the `SignalCapture<T>`.
	///
	/// - returns: the handler than can be used to obtain activation values and join to subsequent nodes.
	public final func capture() -> SignalCapture<T> {
		return attach { (s, dw) -> SignalCapture<T> in
			SignalCapture<T>(signal: s, dw: &dw)
		}
	}
	
	/// If this `Signal` can attach a new handler, this function runs the provided closure (which is expected to construct and set the new handler) and returns the handler. If this `Signal` can't attach a new handler, returns the result of running the closure inside the mutex of a separate preclosed `Signal`.
	///
	/// This method serves three purposes:
	///	1) It enforces the idea that the `signalHandler` should be constructed under this `Signal`'s mutex, providing the `DeferredWork` required by the `signalHandler` constructor interface.
	///	2) It enforces the rule that multiple listen attempts should be immediately closed with a `.duplicate` error
	///	3) It allows abstraction over the actual `Signal` used for attachment (self for single listener and a newly created `Signal` for multi listener).
	///
	/// - parameter constructor: the handler constructor function
	///
	/// - returns: the result from the constructor (typically an SignalHandler)
	fileprivate func attach<R>(constructor: (Signal<T>, inout DeferredWork) -> R) -> R where R: SignalHandler<T> {
		var dw = DeferredWork()
		
		#if false
			// This closure is causing aborts in Swift Snapshot Oct 27, 2016
			let result: R? = mutex.sync {
				signalHandler == nil ? constructor(self, &dw) : nil
			}
		#else
			mutex.unbalancedLock()
			let result: R? = signalHandler == nil ? constructor(self, &dw) : nil
			mutex.unbalancedUnlock()
		#endif
		
		
		dw.runWork()
		if let r = result {
			return r
		} else {
			return Signal<T>.preclosed(error: SignalError.duplicate).attach(constructor: constructor)
		}
	}
	
	/// Returns a copy of the preceeding set, sorted by "timestamp". This allows deterministic sending of results through the graph – older connections are prioritized over newer.
	fileprivate var sortedPreceeding: Array<OrderedSignalPredecessor> {
		return preceeding.sorted(by: { (a, b) -> Bool in
			return a.timestamp < b.timestamp
		})
	}
	
	/// Constructor for signal graph head. Called from `create`.
	///
	/// - returns: the manual `Signal`
	fileprivate init() {
		mutex = PThreadMutex()
		preceeding = []
	}
	
	/// Constructor for a subsequent `Signal`.
	///
	/// - parameter processor: input source for this `Signal`
	///
	/// - returns: the subsequent `Signal`
	fileprivate init<U>(processor: SignalProcessor<U, T>) {
		preceedingCount += 1
		preceeding = [processor.wrappedWithTimestamp(preceedingCount)]
		
		if processor.successorsShareMutex {
			mutex = processor.signal.mutex
		} else {
			mutex = PThreadMutex()
		}
		if !(self is SignalMulti<T>) {
			var dw = DeferredWork()
			mutex.sync {
				_ = processor.outputAddedSuccessorInternal(self, param: nil, activationCount: nil, dw: &dw)
			}
			dw.runWork()
		}
	}
	
	// Need to close the `newInputSignal` and detach from all predecessors on deinit.
	deinit {
		_ = newInputSignal?.send(result: .failure(SignalError.cancelled), predecessor: nil, activationCount: 0, activated: true)
		
		var dw = DeferredWork()
		mutex.sync {
			removeAllPreceedingInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	// Connects this `Signal` to a preceeding SignalPredecessor. Other connection functions must go through this.
	//
	// - parameter newPreceeding: the preceeding SignalPredecessor to add
	// - parameter param:         this function may invoke `outputAddedSuccessorInternal` internally. If it does this `param` will be passed as the `param` for that function.
	// - parameter dw:            required
	//
	// - returns: true if this `Signal` was connected to the predecessor, false otherwise
	fileprivate final func addPreceedingInternal(_ newPreceeding: SignalPredecessor, param: Any?, dw: inout DeferredWork) -> SignalAddResult {
		preceedingCount += 1
		let wrapped = newPreceeding.wrappedWithTimestamp(preceedingCount)
		preceeding.insert(wrapped)
		
		let result = newPreceeding.outputAddedSuccessorInternal(self, param: param, activationCount: (delivery.isDisabled || preceeding.count == 1) ? Optional<Int>.none : Optional<Int>(activationCount), dw: &dw)
		switch result {
		case .success:
			if !delivery.isDisabled, preceeding.count == 1 {
				updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw)
				if !delivery.isSynchronous {
					let ac = activationCount
					dw.append {
						var dw = DeferredWork()
						self.mutex.sync {
							if ac == self.activationCount {
								newPreceeding.outputCompletedActivationSuccessorInternal(self, dw: &dw)
							}
						}
						dw.runWork()
					}
				}
			}
			return result
		default:
			preceeding.remove(wrapped)
			return result
		}
	}
	
	/// A wrapper around addPreceedingInternal for use outside the mutex. Only used by the `combine` functions (which is why it returns `self` – it's a syntactic convenience in those methods).
	///
	// - parameter processor: the preceeding SignalPredecessor to add
	///
	/// - returns: self
	fileprivate final func addPreceeding(processor: SignalPredecessor) -> Signal<T> {
		var dw = DeferredWork()
		mutex.sync {
			_ = addPreceedingInternal(processor, param: nil, dw: &dw)
		}
		dw.runWork()
		return self
	}
	
	/// Removes a (potentially) non-unique predecessor. Used only from `SignalMergeSet` and `SignalMergeProcessor`.
	///
	/// This is one of two, independent, functions for removing preceeding. The other being `removeAllPreceedingInternal`.
	///
	/// - parameter oldPreceeding: the predecessor to remove
	/// - parameter dw:            required
	fileprivate final func removePreceedingWithoutInterruptionInternal(_ oldPreceeding: SignalPredecessor, dw: inout DeferredWork) {
		if preceeding.remove(oldPreceeding.wrappedWithTimestamp(0)) != nil {
			oldPreceeding.outputRemovedSuccessorInternal(self, dw: &dw)
		}
	}
	
	/// Removes all predecessors and invalidate all previous inputs.
	///
	/// This is one of two, independent, functions for removing preceeding. The other being `removePreceedingWithoutInterruptionInternal`.
	///
	/// - parameter oldPreceeding: the predecessor to remove
	/// - parameter dw:            required
	fileprivate final func removeAllPreceedingInternal(dw: inout DeferredWork) {
		if preceeding.count > 0 {
			dw.append { [preceeding] in withExtendedLifetime(preceeding) {} }
			
			// Careful to use *sorted* preceeding to propagate graph changes deterministically
			sortedPreceeding.forEach { $0.base.outputRemovedSuccessorInternal(self, dw: &dw) }
			preceeding = []
		}
		updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw)
	}
	
	/// Increment the input generation count.
	///
	/// WARNING: internal methods must be performed inside their respective mutex
	///
	/// NOTE: currently only called from `propagateNewNextInternal`
	///
	/// - returns: a new `SignalInput` object with this value
	fileprivate final func updateActivationInternal(andInvalidateAllPrevious: Bool, dw: inout DeferredWork) {
		assert(mutex.unbalancedTryLock() == false)
		
		activationCount = activationCount &+ 1
		
		if andInvalidateAllPrevious {
			let oldItems = Array<Result<T>>(queue)
			dw.append { withExtendedLifetime(oldItems) {} }
			queue.removeAll()
			holdCount = 0
		} else {
			assert(holdCount == 0)
		}
		
		switch delivery {
		case .synchronous:
			if andInvalidateAllPrevious, let h = signalHandler {
				// Any outstanding end activation won't resolve now so we need to apply it directly.
				h.endActivationInternal(dw: &dw)
				return
			}
			fallthrough
		case .normal:
			// Careful to use *sorted* preceeding to propagate graph changes deterministically
			for p in sortedPreceeding {
				p.base.outputActivatedSuccessorInternal(self, activationCount: activationCount, dw: &dw)
			}
		case .disabled:
			// Careful to use *sorted* preceeding to propagate graph changes deterministically
			for p in sortedPreceeding {
				p.base.outputDeactivatedSuccessorInternal(self, dw: &dw)
			}
		}
	}
	
	/// Invokes `replacePreceedingProcessorInternal` with an empty array if and only if the `ifOnlyPredecessorIs` matches the current `self.preceedingProcessors`
	///
	/// - parameter ifOnlyPredecessorIs: a predecessor to remove
	///
	/// - returns: if the predecessor matched, then a new `SignalInput<T>` for this `Signal`, otherwise `nil`.
	fileprivate final func newInput(forDisconnector: SignalProcessor<T, T>) -> SignalInput<T>? {
		var dw = DeferredWork()
		let result = mutex.sync { () -> SignalInput<T>? in
			if preceeding.count == 1, let p = preceeding.first?.base, p === forDisconnector {
				removeAllPreceedingInternal(dw: &dw)
				return SignalInput(signal: self, activationCount: activationCount)
			} else {
				return nil
			}
		}
		dw.runWork()
		return result
	}
	
	/// Tests whether a `Result` from a `predecessor` with `activationCount` should be accepted or rejected.
	///
	/// - parameter predecessor:     the source of the `Result`
	/// - parameter activationCount: the `activationCount` when the source was connected
	///
	/// - returns: true if `preceeding` contains `predecessor` and `self.activationCount` matches `activationCount`
	fileprivate final func isCurrent(_ predecessor: Unmanaged<AnyObject>?, _ activationCount: Int) -> Bool {
		if activationCount != self.activationCount {
			return false
		}
		if preceeding.count == 1, let expected = preceeding.first?.base {
			return predecessor?.takeUnretainedValue() === expected
		} else if preceeding.count == 0 {
			return predecessor == nil
		}
		
		guard let p = predecessor?.takeUnretainedValue() as? SignalPredecessor else { return false }
		return preceeding.contains(p.wrappedWithTimestamp(0))
	}
	
	/// The `itemContext` holds information uniquely used by the currently processing item so it can be read outside the mutex. This may only be called immediately before calling `blockInternal` to start a processing item (e.g. from `send` or `resume`.
	///
	/// - Returns: false if the `signalHandler` was `nil`, true otherwise.
	fileprivate final func refreshItemContextInternal() -> Bool {
		assert(mutex.unbalancedTryLock() == false)
		assert(holdCount == 0 && itemProcessing == false)
		if itemContextNeedsRefresh {
			if let h = signalHandler {
				itemContext = ItemContext(activationCount: activationCount, context: h.context, synchronous: delivery.isSynchronous, handler: h.handler)
				itemContextNeedsRefresh = false
			} else {
				return false
			}
		}
		return true
	}
	
	/// Sets the `itemContext` back to an "idle" state (releasing any handler closure and setting `activationCount` to zero.
	/// This function may be called only from `specializedSyncPop` or `pop`.
	fileprivate final func clearItemContextInternal() -> ItemContext<T> {
		assert(mutex.unbalancedTryLock() == false)
		let oldContext = itemContext
		itemContext = ItemContext(activationCount: 0)
		return oldContext
	}
	
	/// The primary `send` function. Sends `result`, assuming `fromInput` matches the current `self.input` and `self.delivery` is enabled
	///
	/// - parameter result:    the value or error to pass to any attached handler
	/// - parameter fromInput: must match the internal `input`
	///
	/// - returns: `SignalError.cancelled` if the `fromInput` fails to match, `SignalError.inactive` if the current `delivery` state is `.disabled`, otherwise `nil`.
	@discardableResult
	fileprivate final func send(result: Result<T>, predecessor: Unmanaged<AnyObject>?, activationCount: Int, activated: Bool) -> SignalError? {
		mutex.unbalancedLock()
		
		guard isCurrent(predecessor, activationCount) else {
			mutex.unbalancedUnlock()
			
			// Retain the result past the end of the lock
			withExtendedLifetime(result) {}
			return SignalError.cancelled
		}
		
		switch delivery {
		case .normal:
			if holdCount == 0 && itemProcessing == false {
				assert(queue.isEmpty)
				break
			} else {
				queue.append(result)
				mutex.unbalancedUnlock()
				return nil
			}
		case .synchronous(let count):
			if activated {
				queue.append(result)
				mutex.unbalancedUnlock()
				return nil
			} else if count == 0, holdCount == 0, itemProcessing == false {
				break
			} else {
				queue.insert(result, at: count)
				delivery = .synchronous(count + 1)
				mutex.unbalancedUnlock()
				return nil
			}
		case .disabled:
			mutex.unbalancedUnlock()
			
			// Retain the result past the end of the lock
			withExtendedLifetime(result) {}
			return SignalError.inactive
		}
		
		if !refreshItemContextInternal() {
			mutex.unbalancedUnlock()
			return SignalError.inactive
		}
		
		assert(holdCount == 0 && itemProcessing == false)
		itemProcessing = true
		
		mutex.unbalancedUnlock()
		
		// As an optimization/ARC-avoidance, the common path through the `dispatch` and `invokeHandler` functions is manually inlined here.
		// I'd love to express this two layer switch as `switch (itemContext.context, result)` but without specialization, it malloc's.
		switch itemContext.context {
		case .direct:
			switch result {
			case .success:
				itemContext.handler(result)
				specializedSyncPop()
				return nil
			case .failure: break
			}
			fallthrough
		default:
			dispatch(result)
		}
		
		return nil
	}
	
	/// A secondary send function used to push values for `activeSignal`. The pushed result is handled automatically during the `DeferredWork`. Since values are *always* queued, this is less efficient than `send` but it can safely be invoked inside mutexes of the `activeSignal`'s parent.
	///
	/// - parameter value: pushed onto this `Signal`'s queue
	/// - parameter dw:    used to dispatch the signal safely outside the parent's mutex
	fileprivate final func push(values: Array<T>, error: Error?, activationCount: Int, dw: inout DeferredWork) {
		mutex.sync {
			guard self.activationCount == activationCount else { return }
			pushInternal(values: values, error: error, dw: &dw)
		}
	}
	
	/// A secondary send function used to push activation values and activation errors. Since values are *always* queued, this is less efficient than `send` but it can safely be invoked inside mutexes of the successor's activation.
	///
	/// WARNING: internal methods must be performed inside their respective mutex
	///
	/// NOTE: currently only called from `push(valud:dw:)` and `outputActivatedInternal`
	///
	/// - parameter activation: activation values from the preceeding processor
	/// - parameter error:      activation error from the preceeding processor
	/// - parameter dw:         deferred work used to dispatch these pushed values after any surrounding mutex is exited.
	fileprivate final func pushInternal(values: Array<T>, error: Error?, dw: inout DeferredWork) {
		assert(mutex.unbalancedTryLock() == false)
		
		guard values.count > 0 || error != nil else {
			dw.append {
				withExtendedLifetime(values) {}
				withExtendedLifetime(error) {}
			}
			return
		}
		
		if case .synchronous(let count) = delivery {
			assert(count == 0)
			delivery = .synchronous(values.count + (error != nil ? 1 : 0))
		}
		
		for v in values {
			queue.append(.success(v))
		}
		if let e = error {
			queue.append(.failure(e))
		}
		
		resumeIfPossibleInternal(dw: &dw)
	}
	
	/// Used in SignalCapture.handleSynchronousToNormalInternal to handle a situation where a deactivation and reactivation occurs *while* it is `itemProcessing` so the next capture is queued instead of captured. This is used to grab synchronous values before transition to normal.
	///
	/// - Returns: the queued items under the synchronous count.
	fileprivate final func pullQueuedSynchronousInternal() -> (values: Array<T>, error: Error?) {
		if case .synchronous(let count) = delivery, count > 0 {
			var values = Array<T>()
			var error: Error? = nil
			for _ in 0..<count {
				switch queue.removeFirst() {
				case .success(let v): values.append(v)
				case .failure(let e): error = e
				}
			}
			delivery = .synchronous(0)
			return (values, error)
		}
		return ([], nil)
	}
	
	/// Invoke the user handler and deactivates the `Signal` if `result` is a `failure`.
	///
	/// - parameter result: passed to the `item.handler`
	/// - parameter item:   contains the handler
	private final func invokeHandler(_ result: Result<T>) {
		// This is very subtle but it is more efficient to *repeat* the handler invocation in each case, since Swift can handover ownership, rather than retaining.
		switch result {
		case .success:
			itemContext.handler(result)
		case .failure:
			itemContext.handler(result)
			var dw = DeferredWork()
			mutex.sync {
				if itemContext.activationCount == activationCount, !delivery.isDisabled {
					signalHandler?.deactivateInternal(dw: &dw)
				}
			}
			dw.runWork()
		}
	}
	
	/// Dispatches the `result` to the current handler in the appropriate context then pops the next `result` and attempts to invoke the handler with the next result (if any)
	///
	/// - parameter result: for sending to the handler
	/// - parameter item:   required information copied from under this `Signal`'s mutex
	fileprivate final func dispatch(_ result: Result<T>) {
		switch itemContext.context {
		case .direct:
			invokeHandler(result)
			specializedSyncPop()
		case let c where c.type.isImmediate || itemContext.synchronous:
			// Other synchronous contexts should be invoked serially in a while loop (recursive invocation could overburden the stack).
			c.invokeAndWait {
				self.invokeHandler(result)
			}
			while let r = pop() {
				if c.type.isImmediate || itemContext.synchronous {
					c.invokeAndWait {
						self.invokeHandler(r)
					}
				} else {
					dispatch(r)
					break
				}
			}
		case let c:
			c.invoke {
				self.invokeHandler(result)
				if let r = self.pop() {
					self.dispatch(r)
				}
			}
		}
	}
	
	/// Gets the next item from the queue for processing and updates the `ItemContext`.
	///
	/// - parameter item: context that needs to be updated under the mutex
	///
	/// - returns: the next result for processing, if any
	fileprivate final func pop() -> Result<T>? {
		mutex.unbalancedLock()
		assert(itemProcessing == true)
		
		guard itemContext.activationCount == activationCount else {
			let oldContext = clearItemContextInternal()
			itemProcessing = false
			var dw = DeferredWork()
			resumeIfPossibleInternal(dw: &dw)
			mutex.unbalancedUnlock()
			withExtendedLifetime(oldContext) {}
			dw.runWork()
			return nil
		}
		
		if !queue.isEmpty, holdCount == 0 {
			switch delivery {
			case .synchronous(let count) where count == 0: break
			case .synchronous(let count):
				delivery = .synchronous(count - 1)
				fallthrough
			default:
				let result = queue.removeFirst()
				mutex.unbalancedUnlock()
				return result
			}
		}
		
		itemProcessing = false
		if itemContextNeedsRefresh {
			let oldContext = clearItemContextInternal()
			mutex.unbalancedUnlock()
			withExtendedLifetime(oldContext) {}
		} else {
			mutex.unbalancedUnlock()
		}
		return nil
	}
	
	/// An optimized version of `pop(_:)` used when context is .direct. The semantics are slightly different: this doesn't pop a result off the queue... rather, it looks to see if there's anything in the queue and handles it internally if there is. This allows optimization for the expected case where there's nothing in the queue.
	///
	/// - parameter item: context that needs to be updated under the mutex
	private final func specializedSyncPop() {
		mutex.unbalancedLock()
		assert(itemProcessing == true)
		
		if itemContext.activationCount != activationCount || !queue.isEmpty {
			mutex.unbalancedUnlock()
			while let r = pop() {
				invokeHandler(r)
			}
		} else {
			itemProcessing = false
			if itemContextNeedsRefresh {
				let oldContext = clearItemContextInternal()
				mutex.unbalancedUnlock()
				withExtendedLifetime(oldContext) {}
			} else {
				mutex.unbalancedUnlock()
			}
		}
	}
	
	// Increment the `holdCount`
	fileprivate final func blockInternal() {
		assert(mutex.unbalancedTryLock() == false)
		assert(holdCount <= 1)
		holdCount += 1
	}
	
	// Increment the `holdCount`, if the `activationCount` provided matches `self.activationCount`
	fileprivate final func block(activationCount: Int) {
		mutex.sync {
			guard self.activationCount == activationCount else { return }
			blockInternal()
		}
	}
	
	// Decrement the `holdCount`, if the `activationCountAtBlock` provided matches `self.activationCount`
	//
	// NOTE: the caller must resume processing if holdCount reaches zero and there are queued items.
	fileprivate final func unblockInternal(activationCountAtBlock: Int) {
		guard self.activationCount == activationCountAtBlock else { return }
		assert(mutex.unbalancedTryLock() == false)
		assert(holdCount >= 1 && holdCount <= 2)
		holdCount -= 1
	}
	
	// If the holdCount is zero and there are queued items, increments the hold count immediately and starts processing in the deferred work.
	fileprivate final func resumeIfPossibleInternal(dw: inout DeferredWork) {
		if holdCount == 0, itemProcessing == false, !queue.isEmpty {
			if !refreshItemContextInternal() {
				preconditionFailure("Handler should not be nil if queue is not empty")
			}
			itemProcessing = true
			dw.append {
				if let r = self.pop() {
					self.dispatch(r)
				}
			}
		}
	}
	
	// Decrement the `holdCount`, if the `activationCount` provided matches `self.activationCount` and resume processing if the `holdCount` reaches zero and there are items in the queue.
	fileprivate final func unblock(activationCount: Int) {
		var dw = DeferredWork()
		mutex.sync {
			unblockInternal(activationCountAtBlock: activationCount)
			resumeIfPossibleInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	// Changes the value of the `self.delivery` instance variable and handles associated lifecycle updates (like incrementing the activation count).
	//
	// - parameter newDelivery: new value for `self.delivery`
	// - parameter dw:          required
	fileprivate final func changeDeliveryInternal(newDelivery: SignalDelivery, dw: inout DeferredWork) {
		assert(mutex.unbalancedTryLock() == false)
		assert(newDelivery.isDisabled != delivery.isDisabled || newDelivery.isSynchronous != delivery.isSynchronous)
		
		let oldDelivery = delivery
		delivery = newDelivery
		switch delivery {
		case .normal:
			if oldDelivery.isSynchronous {
				// Careful to use *sorted* preceeding to propagate graph changes deterministically
				for p in sortedPreceeding {
					p.base.outputCompletedActivationSuccessorInternal(self, dw: &dw)
				}
			}
			resumeIfPossibleInternal(dw: &dw)
			newInputSignal?.push(values: [SignalInput(signal: self, activationCount: activationCount)], error: nil, activationCount: 0, dw: &dw)
		case .synchronous:
			if preceeding.count > 0 {
				updateActivationInternal(andInvalidateAllPrevious: false, dw: &dw)
			}
		case .disabled:
			updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw)
			_ = newInputSignal?.push(values: [Optional<SignalInput<T>>.none], error: nil, activationCount: 0, dw: &dw)
		}
	}
}

/// Used to provide a light abstraction over the `SignalInput` and `SignalNext` types
public protocol SignalSender {
	associatedtype ValueType
	@discardableResult func send(result: Result<ValueType>) -> SignalError?
}

/// An `SignalInput` is used to send values to the "head" `Signal`s in a signal graph. It is created using the `Signal<T>.create()` function.
public final class SignalInput<T>: SignalSender, Cancellable {
	public typealias ValueType = T
	
	fileprivate weak var signal: Signal<T>?
	fileprivate let activationCount: Int
	
	fileprivate init(signal: Signal<T>, activationCount: Int) {
		self.signal = signal
		self.activationCount = activationCount
	}
	
	/// Primary value sending method
	///
	/// - parameter result: value or error to send
	///
	/// - returns: nil on success, `SignalError.cancelled` if this input has been replaced, `SignalError.inactive` if the `Signal` has no active listeners.
	@discardableResult public func send(result: Result<T>) -> SignalError? {
		guard let s = signal else { return SignalError.cancelled }
		return s.send(result: result, predecessor: nil, activationCount: activationCount, activated: true)
	}
	
	public func cancel() {
		_ = send(result: .failure(SignalError.cancelled))
	}
	
	deinit {
		send(result: .failure(SignalError.cancelled))
	}
}

/// An `Signal<T>` that permits attaching multiple listeners (a normal `Signal<T>` will immediately close subsequent listeners with a `SignalError.duplicate` error).
/// Instances of this class are created from one of the `SignalMulti<T>` returning functions on `Signal<T>`, including `playback() -> SignalMulti<T>`, `multicast() -> SignalMulti<T>` and `continuous(initial: T) -> SignalMulti<T>`.
public final class SignalMulti<T>: Signal<T> {
	fileprivate init(processor: SignalMultiProcessor<T>) {
		super.init(processor: processor)
	}
	
	fileprivate override func attach<R>(constructor: (Signal<T>, inout DeferredWork) -> R) -> R where R: SignalHandler<T> {
		if let s = (preceeding.first?.base as? SignalMultiProcessor<T>).map({ Signal<T>(processor: $0) }) {
			return s.attach(constructor: constructor)
		} else {
			return Signal<T>.preclosed(error: SignalError.duplicate).attach(constructor: constructor)
		}
	}
}

// A fileprivate struct that stores data associated with the item currently being handled. Under the `Signal` mutex, if the `running` semaphore is acquired, the fields of this struct are filled in using `Signal` and `SignalHandler` data and the contents of the struct are then used by the current thread *outside* the mutex.
private struct ItemContext<T> {
	let context: Exec
	let synchronous: Bool
	let handler: (Result<T>) -> Void
	let activationCount: Int
	
	// Create a blank ItemContext
	init(activationCount: Int) {
		self.context = .direct
		self.synchronous = false
		self.handler = { r in }
		self.activationCount = activationCount
	}
	
	// Create a filled-in ItemContext
	init(activationCount: Int, context: Exec, synchronous: Bool, handler: @escaping (Result<T>) -> Void) {
		self.activationCount = activationCount
		self.context = context
		self.synchronous = synchronous
		self.handler = handler
	}
}

/// If `Signal<T>` is a delivery channel, then `SignalHandler` is the destination to which it delivers.
/// `SignalHandler<T>` is never directly created – it is implicitly created when one of the listening or transformation methods on `Signal<T>` are invoked.
/// The base `SignalHandler<T>` is never directly instantiated. While it's not "abstract" in any technical sense, it doesn't do anything by default.
/// Subclasses include `SignalEndpoint` (the user "exit" point for signal results), `SignalProcessor` (used for transforming signals between instances of `Signal<T>`), `SignalJunction` (for enabling dynamic graph connection and disconnections).
fileprivate class SignalHandler<T> {
	final let signal: Signal<T>
	final let context: Exec
	final var handler: (Result<T>) -> Void { didSet { signal.itemContextNeedsRefresh = true } }
	
	/// Base constructor sets the `signal`, `context` and `handler` and implicitly activates if required.
	///
	/// - parameter signal:  a `SignalHandler` is always, immutably, attached to its `Signal`
	/// - parameter dw:      used for performing activation outside any enclosing mutex, if necessary
	/// - parameter context: where the `handler` function should be invoked
	/// - parameter handler: performs the "user" work for the handler
	///
	/// - returns: constructed `SignalHandler<T>`
	init(signal: Signal<T>, dw: inout DeferredWork, context: Exec) {
		// Must be passed a `Signal` that does not already have a `signalHandler`
		assert(signal.signalHandler == nil && signal.mutex.unbalancedTryLock() == false)
		
		self.signal = signal
		self.context = context
		self.handler = { r in }
		
		// Connect to the `Signal`
		signal.signalHandler = self
		
		// Set the initial handler
		self.handler = initialHandlerInternal()
		
		// Propagate immediately
		if alwaysActiveInternal {
			if activateInternal(dw: &dw) {
				let count = self.signal.activationCount
				dw.append { self.endActivation(activationCount: count) }
			}
		}
	}
	
	// Default behavior does nothing prior to activation
	fileprivate func initialHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { r in }
	}
	
	/// Convenience wrapper around the mutex from the `Signal` which is used to protect the handler
	///
	/// - parameter execute: the work to perform inside the mutex
	///
	/// - throws: basic rethrow from the `execute` closure
	///
	/// - returns: the result from the `execute closure
	final func sync<T>(execute: () throws -> T) rethrows -> T {
		signal.mutex.unbalancedLock()
		defer { signal.mutex.unbalancedUnlock() }
		return try execute()
	}
	
	/// True if this node activates predecessors even when it has no active successors
	fileprivate var alwaysActiveInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return false
	}
	
	/// Immediately deactivate and prevent reactivation.
	///
	/// NOTE: currently only called from `SignalEndpoint` which also *overrides* the function.
	deinit {
		var dw = DeferredWork()
		sync {
			if !signal.delivery.isDisabled {
				signal.changeDeliveryInternal(newDelivery: .disabled, dw: &dw)
			}
			signal.signalHandler = nil
		}
		dw.runWork()
	}
	
	/// As an optimization, successive `Signal`s are placed under the *same* mutex as any preceeding `.sync` `SignalHandler`s
	/// `SignalJunction` returns `false` in an override in all cases since any successor it attaches will have been created independently under a different mutex.
	fileprivate var successorsShareMutex: Bool {
		if case .direct = context {
			return true
		} else {
			return false
		}
	}
	
	// Activation changes the delivery, based on whether there are preceeding `Signal`s.
	// If delivery is changed to synchronous, `endActivation` must be called in the deferred work.
	fileprivate final func activateInternal(dw: inout DeferredWork) -> Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		if signal.delivery.isDisabled {
			signal.changeDeliveryInternal(newDelivery: .synchronous(0), dw: &dw)
			return true
		}
		return false
	}
	
	fileprivate final func endActivationInternal(dw: inout DeferredWork) {
		if signal.delivery.isSynchronous {
			handleSynchronousToNormalInternal(dw: &dw)
			signal.changeDeliveryInternal(newDelivery: .normal, dw: &dw)
		}
	}
	
	// Changes delivery to normal.
	fileprivate final func endActivation(activationCount: Int) {
		var dw = DeferredWork()
		sync {
			guard signal.activationCount == activationCount else { return }
			endActivationInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	fileprivate func handleSynchronousToNormalInternal(dw: inout DeferredWork) {
	}
	
	fileprivate func handleDeactivationInternal(dw: inout DeferredWork) {
	}
	
	// Changes delivery to disabled *and* resets the handler to the initial handler.
	fileprivate final func deactivateInternal(dw: inout DeferredWork) {
		assert(signal.mutex.unbalancedTryLock() == false)
		handleDeactivationInternal(dw: &dw)
		if !alwaysActiveInternal {
			signal.changeDeliveryInternal(newDelivery: .disabled, dw: &dw)
			dw.append { [handler] in withExtendedLifetime(handler) {} }
			handler = initialHandlerInternal()
		}
	}
}

/// A hashable wrapper around an SignalPredecessor existential that also embeds a timestamp to allow ordering
/// NOTE: the timestamp is *not* part of the equality or hashValue so a wrapper can be created with an arbitrary timestamp to test for the presence of a given SignalPredecessor.
fileprivate struct OrderedSignalPredecessor: Hashable {
	let base: SignalPredecessor
	let timestamp: Int
	init(base: SignalPredecessor, timestamp: Int) {
		self.base = base
		self.timestamp = timestamp
	}
	
	var hashValue: Int { return Int(bitPattern: Unmanaged<AnyObject>.passUnretained(base).toOpaque()) }
	static func ==(lhs: OrderedSignalPredecessor, rhs: OrderedSignalPredecessor) -> Bool {
		return lhs.base === rhs.base
	}
}

/// A protocol used for communicating from successor `Signal`s to predecessor processors in the signal graph. Used for connectivity and activation.
fileprivate protocol SignalPredecessor: class {
	func outputActivatedSuccessorInternal(_ successor: AnyObject, activationCount: Int, dw: inout DeferredWork)
	func outputCompletedActivationSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func outputDeactivatedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func outputAddedSuccessorInternal(_ successor: AnyObject, param: Any?, activationCount: Int?, dw: inout DeferredWork) -> SignalAddResult
	func outputRemovedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func precessorsSuccessorInternal(contains: SignalPredecessor) -> Bool
	func wrappedWithTimestamp(_ timestamp: Int) -> OrderedSignalPredecessor
}

/// Easy construction of a hashable wrapper around an SignalPredecessor existential
extension SignalPredecessor {
	func wrappedWithTimestamp(_ timestamp: Int) -> OrderedSignalPredecessor {
		return OrderedSignalPredecessor(base: self, timestamp: timestamp)
	}
}

/// All `Signal`s, except those with endpoint handlers, are fed to another `Signal`. A `SignalProcessor` is how this is done. This is the abstract base for all handlers that connect to another `Signal`. The default implementation can only connect to a single output (concrete subclass `SignalMultiprocessor` is used for multiple outputs) but a majority of the architecture for any number of outputs is contained in this class.
/// This class allows its outputs to have a different value type compared to the Signal for this class, although only SignalTransformer, SignalTransformerWithState and SignalCombiner take advantage – all other subclasses derive from SignalProcessor<T, T>.
fileprivate class SignalProcessor<T, U>: SignalHandler<T>, SignalPredecessor {
	var outputs = Array<(destination: Weak<Signal<U>>, activationCount: Int?)>()
	
	/// Common implementation for a nextHandlerInternal. Currently used only from SignalCacheUntilActive and SignalCombiner
	fileprivate static func simpleNext(processor: SignalProcessor<T, U>, transform: @escaping (Result<T>) -> Result<U>) -> (Result<T>) -> Void {
		assert(processor.signal.mutex.unbalancedTryLock() == false)
		guard let output = processor.outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return processor.initialHandlerInternal() }
		let activated = processor.signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(processor)
		return { [weak outputSignal] (r: Result<T>) -> Void in _ = outputSignal?.send(result: transform(r), predecessor: predecessor, activationCount: ac, activated: activated) }
	}
	
	/// If this property returns false, attempts to connect more than one output will be rejected. The rejection is used primarily by SignalJunction which performs disconnect and join as two separate steps so it needs the rejection to ensure two threads haven't tried to join simultaneously.
	fileprivate var multipleOutputsPermitted: Bool {
		return false
	}
	
	/// Determines if a `Signal` is one of the current outputs.
	///
	/// - parameter signal: possible output
	///
	/// - returns: true if `signal` is contained in the outputs
	fileprivate final func isOutputInternal(_ signal: Signal<U>) -> Int? {
		assert(signal.mutex.unbalancedTryLock() == false)
		for (i, o) in outputs.enumerated() {
			if let d = o.destination.value, d === signal {
				return i
			}
		}
		return nil
	}
	
	/// Gets the set of all predecessors. Used by junctions (`SignalJunction` and `SignalCapture`) to prevent loops in the graph.
	func precessorsSuccessorInternal(contains: SignalPredecessor) -> Bool {
		if contains === self {
			return true
		}
		var result = false
		runSuccesorAction {
			// Don't need to traverse sortedPreceeding (unsorted is fine for an ancestor check)
			for p in signal.preceeding {
				if p.base.precessorsSuccessorInternal(contains: contains) {
					result = true
					return
				}
			}
		}
		return result
	}
	
	/// Pushes activation values to newly joined outputs. By default, there is no activation so this function is intended to be overridden.
	///
	/// - parameter index: identifies the output
	/// - parameter dw:    required by pushInternal
	fileprivate func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
	}
	
	/// When an output changes activation, this function is called.
	///
	/// - parameter index:           index of the activation changed output
	/// - parameter activationCount: new count received
	/// - parameter dw:              required
	fileprivate final func updateOutputInternal(index: Int, activationCount: Int?, dw: inout DeferredWork) -> Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		assert(outputs[index].activationCount != activationCount)
		
		let previous = anyActiveOutputsInternal
		
		outputs[index].activationCount = activationCount
		dw.append { [handler] in withExtendedLifetime(handler) {} }
		handler = nextHandlerInternal()
		
		var result = false
		if activationCount != nil {
			sendActivationToOutputInternal(index: index, dw: &dw)
			result = activateInternal(dw: &dw)
		} else if activationCount == nil && !signal.delivery.isDisabled && !alwaysActiveInternal {
			var anyStillActive = false
			for o in outputs {
				if o.activationCount != nil {
					anyStillActive = true
					break
				}
			}
			if !anyStillActive {
				deactivateInternal(dw: &dw)
			}
		}
		
		if activationCount != nil, !previous {
			firstOutputActivatedInternal(dw: &dw)
		} else if activationCount == nil, !anyActiveOutputsInternal {
			lastOutputDeactivatedInternal(dw: &dw)
		}
		return result
	}
	
	/// Helper function that applies the mutex around the supplied function, if needed.
	///
	/// - parameter action: function to be run inside the mutex
	private final func runSuccesorAction(action: () -> Void) {
		if successorsShareMutex {
			action()
		} else {
			sync { action() }
		}
	}
	
	/// Helper function used before and after activation to determine if this handler should activate or deactivated.
	private final var anyActiveOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		for o in outputs {
			if o.destination.value != nil && o.activationCount != nil {
				return true
			}
		}
		return false
	}
	
	/// Overrideable function to attach behaviors to activation by an output
	///
	/// - parameter dw: required
	fileprivate func firstOutputActivatedInternal(dw: inout DeferredWork) {
	}
	
	/// Overrideable function to attach behaviors to deactivation by an output
	///
	/// - parameter dw: required
	fileprivate func lastOutputDeactivatedInternal(dw: inout DeferredWork) {
	}
	
	/// Overrideable function to attach behaviors to output removal
	///
	/// - parameter dw: required
	fileprivate func lastOutputRemovedInternal(dw: inout DeferredWork) {
	}
	
	/// Invoked from successor `Signal`s when they activate
	///
	/// - parameter successor:       a `Signal` (if not Signal<U>, will be ignored)
	/// - parameter activationCount: new activation count value for the `Signal`
	/// - parameter dw:              required
	fileprivate final func outputActivatedSuccessorInternal(_ successor: AnyObject, activationCount: Int, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { return }
			if let i = isOutputInternal(sccr) {
				_ = updateOutputInternal(index: i, activationCount: activationCount, dw: &dw)
			}
		}
	}
	
	func outputCompletedActivationSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { return }
			if let _ = isOutputInternal(sccr), case .synchronous = signal.delivery {
				endActivationInternal(dw: &dw)
			}
		}
	}
	
	/// Invoked from successor `Signal`s when they deactivate
	///
	/// - parameter successor:       a `Signal` (if not Signal<U>, will be ignored)
	/// - parameter dw:              required
	fileprivate final func outputDeactivatedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { return }
			if let i = self.isOutputInternal(sccr) {
				_ = updateOutputInternal(index: i, activationCount: nil, dw: &dw)
			}
		}
	}
	
	/// Overrideable function to receive additional information when a successor attaches. Used by SignalJunction and SignalCapture to pass "onError" closures via the successor into the mutex.
	///
	/// - parameter param: usually a closure.
	fileprivate func handleParamFromSuccessor(param: Any) {
		preconditionFailure()
	}
	
	/// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate var needsPredecessorCheck: Bool {
		return false
	}
	
	/// A successor connected
	///
	/// - parameter successor:       must be an Signal<U>
	/// - parameter param:           see `handleParamFromSuccessor`
	/// - parameter activationCount: initial activation count to use
	/// - parameter dw:              required
	///
	/// - returns: true if this output was accepted, false otherwise
	fileprivate final func outputAddedSuccessorInternal(_ successor: AnyObject, param: Any?, activationCount: Int?, dw: inout DeferredWork) -> SignalAddResult {
		var result: SignalAddResult = .success
		runSuccesorAction {
			guard outputs.isEmpty || multipleOutputsPermitted else {
				result = .replaced
				return
			}
			guard let sccr = successor as? Signal<U> else {
				result = .cancelled
				return
			}
			
			if needsPredecessorCheck, let predecessor = sccr.signalHandler as? SignalPredecessor {
				// Don't need to traverse sortedPreceeding (unsorted is fine for an ancestor check)
				for p in signal.preceeding {
					if p.base.precessorsSuccessorInternal(contains: predecessor) {
						result = .loop
						return
					}
				}
			}
			
			outputs.append((destination: Weak(sccr), activationCount: nil))
			if let p = param {
				handleParamFromSuccessor(param: p)
			}
			
			if let ac = activationCount {
				if updateOutputInternal(index: outputs.count - 1, activationCount: ac, dw: &dw) {
					let count = self.signal.activationCount
					dw.append { self.endActivation(activationCount: count) }
				}
			}
		}
		return result
	}
	
	/// Called when a successor is removed
	///
	/// - parameter successor: must be an Signal<U>
	/// - parameter dw:        required
	fileprivate final func outputRemovedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { return }
			for i in outputs.indices.reversed() {
				let match: Bool
				if let d = outputs[i].destination.value, d === sccr {
					match = true
				} else {
					match = false
				}
				if match || outputs[i].destination.value == nil {
					if outputs[i].activationCount != nil {
						_ = updateOutputInternal(index: i, activationCount: nil, dw: &dw)
					}
					outputs.remove(at: i)
					
					if outputs.isEmpty {
						lastOutputRemovedInternal(dw: &dw)
					}
				}
			}
		}
	}
	
	/// Default handler should not be used
	fileprivate func nextHandlerInternal() -> (Result<T>) -> Void {
		preconditionFailure()
	}
}

/// Implementation of a processor that can output to multiple `Signal`s. Used by `continuous`, `continuous`, `playback`, `multicast`, `buffer` and `preclosed`.
fileprivate class SignalMultiProcessor<T>: SignalProcessor<T, T> {
	let updater: (_ activationValues: inout Array<T>, _ preclosed: inout Error?, _ result: Result<T>) -> Void
	var activationValues: Array<T>
	var preclosed: Error?
	var alwaysActive: Bool
	let isUserUpdated: Bool
	
	/// Rather than using different subclasses for each of the "multi" `Signal`s, this one subclass is used for all. However, that requires a few different parameters to enable different behaviors.
	init(signal: Signal<T>, alwaysActive: Bool, values: (Array<T>, Error?), isUserUpdated: Bool, dw: inout DeferredWork, context: Exec, updater: @escaping (_ activationValues: inout Array<T>, _ preclosed: inout Error?, _ result: Result<T>) -> Void) {
		self.updater = updater
		self.activationValues = values.0
		self.preclosed = values.1
		self.alwaysActive = alwaysActive
		self.isUserUpdated = isUserUpdated
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Multicast is not preactivated but all other types are
	fileprivate override var alwaysActiveInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return alwaysActive
	}
	
	/// Multiprocessor can handle multiple outputs
	fileprivate override var multipleOutputsPermitted: Bool {
		return true
	}
	
	/// Any values or errors are sent on activation.
	fileprivate final override func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
		outputs[index].destination.value?.pushInternal(values: activationValues, error: preclosed, dw: &dw)
	}
	
	/// Multiprocessors are (usually – not multicast) preactivated and may cache the values or errors
	override func initialHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [weak self] r in
			if let s = self {
				s.updater(&s.activationValues, &s.preclosed, r)
			}
		}
	}
	
	/// On result, update any activation values.
	fileprivate override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		let os = outputs
		let activated = signal.delivery.isNormal
		return { [weak self] r in
			if let s = self {
				if s.isUserUpdated {
					// The user-supplied function for updating "buffer" `Signal`s is run outside the mutex for safety reasons but this requires copying the array.
					var values = [T]()
					var error: Error?
					s.sync {
						values = s.activationValues
						error = s.preclosed
					}
					s.updater(&values, &error, r)
					s.sync {
						s.activationValues = values
						s.preclosed = error
					}
				} else {
					s.sync {
						// Other closures are run inside the mutex
						s.updater(&s.activationValues, &s.preclosed, r)
					}
				}
				
				// Iteration is over the *cached* version of the outputs, since we don't want multicast (which isn't pre-activated) to send out-of-date values to outputs that connect after they are sent.
				let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(s)
				for o in os {
					if let d = o.destination.value, let ac = o.activationCount {
						d.send(result: r, predecessor: predecessor, activationCount: ac, activated: activated)
					}
				}
			}
		}
	}
}

/// A handler which starts receiving `Signal`s immediately and caches them until an output connects
fileprivate class SignalCacheUntilActive<T>: SignalProcessor<T, T> {
	var cachedValues: Array<T> = []
	var cachedError: Error? = nil
	
	init(signal: Signal<T>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	/// Is always active
	fileprivate override var alwaysActiveInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return true
	}
	
	/// Sends the cached values when an output connects
	fileprivate final override func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
		outputs[index].destination.value?.pushInternal(values: cachedValues, error: cachedError, dw: &dw)
	}
	
	/// Caches values prior to an output connecting
	override func initialHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [weak self] r in
			switch r {
			case .success(let v): self?.cachedValues.append(v)
			case .failure(let e): self?.cachedError = e
			}
		}
	}
	
	/// Clears the cache immediately after an output connects
	fileprivate override func firstOutputActivatedInternal(dw: inout DeferredWork) {
		let tuple = (self.cachedValues, self.cachedError)
		self.cachedValues = []
		self.cachedError = nil
		dw.append { withExtendedLifetime(tuple) {} }
	}
	
	/// Once an output is connected, the handler function is a basic passthrough
	override func nextHandlerInternal() -> (Result<T>) -> Void {
		return SignalProcessor.simpleNext(processor: self) { r in r }
	}
}

/// An SignalNext will block the preceeding SignalTransformer if it is held beyond the scope of the handler function. This allows out-of-context work to be performed.
fileprivate protocol SignalBlockable: class {
	func unblock(activationCount: Int)
	func sync<T>(execute: () throws -> T) rethrows -> T
}

/// An interface used to send signals from the inside of a transformer handler function to the next signal in the graph. Similar to an `SignalInput` but differing on what effects retaining and releasing have.
///	1. Releasing an `SignalInput` will automatically send a `SignalError.cancelled` – that doesn't happend with `SignalNext`.
///	2. Holding onto the `SignalNext` outside the scope of the handler function will block the transformer queue, allowing processing to continue out-of-line until the `SignalNext` is released.
public final class SignalNext<T>: SignalSender {
	public typealias ValueType = T
	
	fileprivate weak var signal: Signal<T>?
	fileprivate weak var blockable: SignalBlockable?
	fileprivate let activationCount: Int
	fileprivate let predecessor: Unmanaged<AnyObject>?
	
	fileprivate let activated: Bool
	fileprivate var needUnblock = false
	
	/// Constructs with the details of the next `Signal` and the `blockable` (the `SignalTransformer` or `SignalTransformerWithState` to which this belongs). NOTE: predecessor and blockable are typically the same instance, just stored differently, for efficiency.
	fileprivate init(signal: Signal<T>, predecessor: SignalPredecessor, activationCount: Int, activated: Bool, blockable: SignalBlockable) {
		self.signal = signal
		self.blockable = blockable
		self.activationCount = activationCount
		self.activated = activated
		self.predecessor = Unmanaged.passUnretained(predecessor)
	}
	
	/// Send simply combines the activation and predecessor information
	@discardableResult public func send(result: Result<T>) -> SignalError? {
		guard let s = signal else { return SignalError.cancelled }
		return s.send(result: result, predecessor: predecessor, activationCount: activationCount, activated: activated)
	}
	
	/// When released, if we `needUnblock` (because we've been retained outside the scope of the transformer handler) then unblock the transformer.
	deinit {
		if let nb = blockable?.sync(execute: { return self.needUnblock }), nb == true {
			blockable?.unblock(activationCount: activationCount)
		}
	}
}

/// A transformer applies a user transformation to any signal. It's the typical "between two `Signal`s" handler.
fileprivate final class SignalTransformer<T, U>: SignalProcessor<T, U>, SignalBlockable {
	typealias UserHandlerType = (Result<T>, SignalNext<U>) -> Void
	let userHandler: UserHandlerType
	init(signal: Signal<T>, dw: inout DeferredWork, context: Exec, handler: @escaping UserHandlerType) {
		self.userHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Implementation of `SignalBlockable`
	fileprivate func unblock(activationCount: Int) {
		signal.unblock(activationCount: activationCount)
	}
	
	/// Invoke the user handler and block if the `next` gains an additional reference count in the process.
	override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		var next = SignalNext<U>(signal: outputSignal, predecessor: self, activationCount: ac, activated: activated, blockable: self)
		return { [userHandler] r in
			userHandler(r, next)
			
			if !isKnownUniquelyReferenced(&next), let s = next.blockable as? SignalTransformer<T, U> {
				s.signal.block(activationCount: next.activationCount)
				
				var previous: ((Result<T>) -> Void)? = nil
				s.sync {
					next.needUnblock = true
					previous = s.handler
					s.handler = s.nextHandlerInternal()
				}
				withExtendedLifetime(previous) {}
			}
		}
	}
}

/// Same as `SignalTransformer` plus a `state` value that is passed `inout` to the handler each time so state can be safely retained between invocations. This `state` value is reset to its `initialState` if the signal graph is deactivated.
fileprivate final class SignalTransformerWithState<T, U, S>: SignalProcessor<T, U>, SignalBlockable {
	typealias UserHandlerType = (inout S, Result<T>, SignalNext<U>) -> Void
	let userHandler: (inout S, Result<T>, SignalNext<U>) -> Void
	let initialState: S
	init(signal: Signal<T>, initialState: S, dw: inout DeferredWork, context: Exec, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) {
		self.userHandler = handler
		self.initialState = initialState
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Implementation of `SignalBlockable`
	fileprivate func unblock(activationCount: Int) {
		signal.unblock(activationCount: activationCount)
	}
	
	/// Invoke the user handler and block if the `next` gains an additional reference count in the process.
	override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		var next = SignalNext<U>(signal: outputSignal, predecessor: self, activationCount: ac, activated: activated, blockable: self)
		
		/// Every time the handler is recreated, the `state` value is initialized from the `initialState`.
		var state = initialState
		
		return { [userHandler] r in
			userHandler(&state, r, next)
			
			if !isKnownUniquelyReferenced(&next), let s = next.blockable as? SignalTransformerWithState<T, U, S> {
				s.signal.block(activationCount: next.activationCount)
				
				// Unlike SignalTransformer without state, we don't use `nextHandlerInternal` to create a new `SignalNext` since we don't want to reset the `state` to `initialState`. Instead, just recreate the `next` object.
				let n = next
				s.sync {
					n.needUnblock = true
					next = SignalNext<U>(signal: outputSignal, predecessor: s, activationCount: ac, activated: activated, blockable: s)
					s.signal.itemContextNeedsRefresh = true
				}
				withExtendedLifetime(n) {}
			}
		}
	}
}

/// An `SignalEndpoint` can keep itself alive by deliberately referencing itself. This loop is broken on receipt of a `failure` signal.
/// - noLoop: endpoint is non-closed, non-keep-alive
/// - loop: endpoint is non-closed, keep-alive
/// - closed: endpoint is closed
fileprivate enum SignalEndpointReferenceLoop {
	case noLoop
	case loop(AnyObject)
	case closed
}

/// The primary "exit point" for a signal graph. `SignalEndpoint` provides two important functions:
///	1. a `handler` function which receives signal values and errors
///	2. upon connecting to the graph, `SignalEndpoint` "activates" the signal graph (which allows sending through the graph to occur and may trigger some "on activation" behavior).
/// This class is instantiated by calling `subscribe` on any `Signal`.
public final class SignalEndpoint<T>: SignalHandler<T>, Cancellable {
	private let userHandler: (Result<T>) -> Void
	fileprivate var referenceLoop = SignalEndpointReferenceLoop.noLoop
	
	/// Constructor called from `subscribe`
	fileprivate init(signal: Signal<T>, dw: inout DeferredWork, context: Exec, handler: @escaping (Result<T>) -> Void) {
		userHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Can't have an `output` so this intial handler is the *only* handler
	fileprivate override func initialHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [userHandler] r in userHandler(r) }
	}
	
	/// A `SignalEndpoint` is active until closed (receives a `failure` signal)
	fileprivate override var alwaysActiveInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		if case .closed = self.referenceLoop {
			return false
		} else {
			return true
		}
	}
	
	/// Deactivation closes the endpoint
	fileprivate override func handleDeactivationInternal(dw: inout DeferredWork) {
		self.referenceLoop = .closed
		dw.append { withExtendedLifetime(self) {} }
	}
	
	/// A simple test for whether this endpoint has received an error, yet. Not generally needed (responding to state changes is best done through the handler function itself).
	public var isClosed: Bool {
		var result = true
		sync {
			if case .closed = self.referenceLoop {
			} else {
				result = false
			}
		}
		return result
	}
	
	public func cancel() {
		var dw = DeferredWork()
		sync {
			if case .closed = self.referenceLoop {
			} else {
				deactivateInternal(dw: &dw)
			}
		}
		dw.runWork()
	}
	
	/// Creates a reference counted loop from this `SignalEndpoint` to itself so it will not be released until the signal closes.
	///
	/// WARNING: AVOID this in most cases, it is for special cases where you *know* the signal will be closed at the other end and you *can't* otherwise maintain the lifetime at the listener end. if the signal graph does not send a `Result.failure`, THIS WILL BE A MEMORY LEAK.
	public func keepAlive() {
		sync {
			if case .noLoop = self.referenceLoop {
				self.referenceLoop = .loop(self)
			}
		}
	}
}

/// A processor used by `combine(...)` to transform incoming `Signal`s into the "combine" type. The handler function is typically just a wrap of the preceeding `Result` in a `EitherResultX.resultY`.
fileprivate final class SignalCombiner<T, U>: SignalProcessor<T, U> {
	let combineHandler: (Result<T>) -> U
	init(signal: Signal<T>, dw: inout DeferredWork, context: Exec, handler: @escaping (Result<T>) -> U) {
		self.combineHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Only one predecessor in a multi-predecessor scenario can share its mutex.
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	/// Simple application of the handler
	fileprivate override func nextHandlerInternal() -> (Result<T>) -> Void {
		return SignalProcessor.simpleNext(processor: self) { [combineHandler] r in Result<U>.success(combineHandler(r)) }
	}
}

private enum SignalAddResult {
	case cancelled
	case success
	case replaced
	case loop
}

/// Attempts to join a `SignalInput` to a joinable handler (either `SignalJunction` or `SignalCapture`) can fail two different ways or it can succeed.
/// - cancelled: The `SignalInput` wasn't the active input for its `Signal` so joining failed
/// - replaced(`SignalInput<T>`): the joinable handler was found to already have a successor connected - must have occurred on another thread between the separate "disconnect" and "join" steps performed on this thread (the old `SignalInput` was invalidated during this process so this case contains the new `SignalInput)
/// - loop(SignalInput<T>): the `SignalInput` was a predecessor of the joinable handler so joining would have formed a loop in the graph (the old `SignalInput` was invalidated during this process so this case contains the new `SignalInput)
/// - succeeded: The join succeeded
public enum SignalJoinError<T>: Error {
	case cancelled
	case duplicate(SignalInput<T>)
	case loop(SignalInput<T>)
}

/// Common implementation of join behavior used by `SignalJunction` and `SignalCapture`.
fileprivate func joinFunction<T>(processor: SignalProcessor<T, T>, disconnect: () -> SignalInput<T>?, toInput: SignalInput<T>, optionalErrorHandler: Any?) throws {
	var dw = DeferredWork()
	defer { dw.runWork() }
	if let nextSignal = toInput.signal {
		try nextSignal.mutex.sync { () throws in
			guard toInput.activationCount == nextSignal.activationCount else {
				throw SignalJoinError<T>.cancelled
			}
			nextSignal.removeAllPreceedingInternal(dw: &dw)
			let result = nextSignal.addPreceedingInternal(processor, param: optionalErrorHandler, dw: &dw)
			switch result {
			case .success: return
			case .loop: throw SignalJoinError.loop(SignalInput<T>(signal: nextSignal, activationCount: nextSignal.activationCount))
			case .replaced: throw SignalJoinError.duplicate(SignalInput<T>(signal: nextSignal, activationCount: nextSignal.activationCount))
			case .cancelled: throw SignalJoinError<T>.cancelled
			}
		}
	}
}

/// A junction is a point in the signal graph that can be disconnected and reconnected at any time. Constructed by calling `join(toInput:...)` or `junction()` on an `Signal`.
public class SignalJunction<T>: SignalProcessor<T, T> {
	private var disconnectOnError: ((SignalJunction<T>, Error, SignalInput<T>) -> ())? = nil
	
	/// Basic `.sync` processor
	init(signal: Signal<T>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	/// Can't share mutex since successor may swap between different graphs
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	/// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate override var needsPredecessorCheck: Bool {
		return true
	}
	
	/// If a `disconnectOnError` handler is configured, then `failure` signals are not sent through the junction. Instead, the junction is disconnected and the `disconnectOnError` function is given an opportunity to handle the `SignalJunction` (`self`) and `SignalInput` (from the `disconnect`).
	fileprivate override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let disconnectAction = disconnectOnError
		return { [weak outputSignal, weak self] (r: Result<T>) -> Void in
			if let d = disconnectAction, case .failure(let e) = r, let s = self, let input = s.disconnect() {
				d(s, e, input)
			} else {
				_ = outputSignal?.send(result: r, predecessor: predecessor, activationCount: ac, activated: activated)
			}
		}
	}
	
	/// Disconnects the succeeding `Signal` (if any).
	///
	/// - returns: the new `SignalInput` for the succeeding `Signal` (if any `Signal` was connected) otherwise nil. If the `SignalInput` value is non-nil and is released, the succeeding `Signal` will be closed.
	public func disconnect() -> SignalInput<T>? {
		var previous: ((SignalJunction<T>, Error, SignalInput<T>) -> ())? = nil
		let result = sync { () -> Signal<T>? in
			previous = disconnectOnError
			return outputs.first?.destination.value
		}?.newInput(forDisconnector: self)
		withExtendedLifetime(previous) {}
		return result
	}
	
	/// The `disconnectOnError` needs to be set inside the mutex, if-and-only-if a successor connects successfully. To allow this to work, the desired `disconnectOnError` function is passed into this function via the `outputAddedSuccessorInternal` called from `addPreceedingInternal` in the `joinFunction`.
	fileprivate override func handleParamFromSuccessor(param: Any) {
		if let p = param as? ((SignalJunction<T>, Error, SignalInput<T>) -> ()) {
			disconnectOnError = p
		}
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - parameter toInput: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	///
	/// - returns: a tuple where the first element is the `SignalInput` result from calling `disconnect` on self. The second element will be:
	///	* .cancelled – if the `SignalInput` wasn't the active input for its `Signal`
	///	* .failed(`SignalError`, `SignalInput<T>`): The connection attempted failed for one of two reasons:
	///		1. SignalError.duplicate (the joinable handler was found to already have a successor connected - must have occurred on another thread between the separate "disconnect" and "join" steps performed on this thread)
	///		2. SignalError.loop (the `SignalInput` was a predecessor of the joinable handler so joining would have formed a loop in the graph)
	///	The error is the first element of the tuple and the new `SignalInput` is the second (the old `SignalInput` was invalidated during this process).
	///	* .succeeded – the join succeeded
	@discardableResult
	public func join(toInput: SignalInput<T>) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, toInput: toInput, optionalErrorHandler: nil)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - parameter toInput: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	/// - parameter onError: if nil, errors from self will be passed through to `toInput`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalJunction` and the input created by calling `disconnect` on it.
	///
	/// - returns: a tuple where the first element is the `SignalInput` result from calling `disconnect` on self. The second element will be:
	///	* .cancelled – if the `SignalInput` wasn't the active input for its `Signal`
	///	* .replaced(SignalInput<T>) - Upon attempting to connect the successor to self, self was found to already have a successor connected (must have occurred on another thread between the separate "disconnect" and "join" steps performed during this function). The `toInput` parameter has been invalidated and the new input is contained in this case value.
	///	* .succeeded – the join succeeded
	@discardableResult
	public func join(toInput: SignalInput<T>, onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, toInput: toInput, optionalErrorHandler: onError)
	}
	
	/// Disconnect and reconnect to the same input, to deliberately deactivate and reactivate. If `disconnect` returns `nil`, no further action will be taken. Any error attempting to reconnect will be sent to the input.
	public func rejoin() {
		if let input = disconnect() {
			do {
				try join(toInput: input)
			} catch {
				input.send(error: error)
			}
		}
	}
	
	/// Disconnect and reconnect to the same input, to deliberately deactivate and reactivate. If `disconnect` returns `nil`, no further action will be taken. Any error attempting to reconnect will be sent to the input.
	/// - parameter onError: passed through to `join`
	public func rejoin(onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) {
		if let input = disconnect() {
			do {
				try join(toInput: input, onError: onError)
			} catch {
				input.send(error: error)
			}
		}
	}
}

struct SignalCaptureParam<T> {
	let sendAsNormal: Bool
	let disconnectOnError: ((SignalCapture<T>, Error, SignalInput<T>) -> ())?
}

/// A "capture" handler separates activation signals (those sent immediately on connection) from normal signals. This allows activation signals to be handled separately or removed from the stream entirely.
/// NOTE: this handler *blocks* delivery between capture and connecting to the output. Signals sent in the meantime are queued.
public final class SignalCapture<T>: SignalProcessor<T, T> {
	private var sendAsNormal: Bool = false
	private var capturedError: Error? = nil
	private var capturedValues: [T] = []
	private var blockActivationCount: Int = 0
	private var disconnectOnError: ((SignalCapture<T>, Error, SignalInput<T>) -> ())? = nil
	
	fileprivate init(signal: Signal<T>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	/// Once an output is connected, `SignalCapture` becomes a no-special-behaviors passthrough handler.
	fileprivate override var alwaysActiveInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return outputs.count > 0 ? false : true
	}
	
	/// Any activation signals captured can be accessed through this property between construction and activating an output (after that point, capture signals are cleared).
	public func activation() -> ([T], Error?) {
		return sync {
			return (capturedValues, capturedError)
		}
	}
	
	/// Since this node operates as a junction, it cannot share mutex
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	/// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate override var needsPredecessorCheck: Bool {
		return true
	}
	
	/// The initial behavior is to capture
	fileprivate override func initialHandlerInternal() -> (Result<T>) -> Void {
		guard outputs.isEmpty else { return { r in } }
		
		assert(signal.mutex.unbalancedTryLock() == false)
		capturedError = nil
		capturedValues = []
		return { [weak self] r in
			guard let s = self else { return }
			switch r {
			case .success(let v): s.capturedValues.append(v)
			case .failure(let e): s.capturedError = e
			}
		}
	}
	
	/// After the initial "capture" phase, the queue is blocked, causing any non-activation signals to queue.
	fileprivate override func handleSynchronousToNormalInternal(dw: inout DeferredWork) {
		if outputs.isEmpty {
			let (vs, err) = signal.pullQueuedSynchronousInternal()
			capturedValues.append(contentsOf: vs)
			if let e = err {
				capturedError = e
			}
			signal.blockInternal()
			blockActivationCount = signal.activationCount
		}
	}
	
	/// If this handler disconnected, then it reactivates and reverts to being a "capture".
	fileprivate override func lastOutputRemovedInternal(dw: inout DeferredWork) {
		guard signal.delivery.isDisabled else { return }
		
		// While a capture has an output connected – even an inactive output – it doesn't self-activate. When the last output is removed, we need to re-activate.
		dw.append { [handler] in withExtendedLifetime(handler) {} }
		handler = initialHandlerInternal()
		if activateInternal(dw: &dw) {
			let count = self.signal.activationCount
			dw.append { self.endActivation(activationCount: count) }
		}
	}
	
	/// When an output activates, if `sendAsNormal` is true, the new output is sent any captured values. In all cases, the captured values are cleared at this point and the queue is unblocked.
	fileprivate override func firstOutputActivatedInternal(dw: inout DeferredWork) {
		if sendAsNormal, let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount {
			// Don't deliver errors if `disconnectOnError` is set
			if let d = disconnectOnError, let e = capturedError {
				// NOTE: we use the successors "internal" functon here since this is always called from successor's `updateActivationInternal` function
				outputSignal.pushInternal(values: capturedValues, error: nil, dw: &dw)
				dw.append {
					// We need to use a specialized version of disconnect that ensures another disconnect hasn't happened in the meantime. Since it's theoretically possible that this handler could be disconnected and reconnected in the meantime (or deactivated and reactivated) we need to check the output and activationCount to ensure everything's still the same.
					var previous: ((SignalCapture<T>, Error, SignalInput<T>) -> ())? = nil
					let input = self.sync { () -> Signal<T>? in
						if let o = self.outputs.first, let os = o.destination.value, os === outputSignal, ac == o.activationCount {
							previous = self.disconnectOnError
							return os
						} else {
							return nil
						}
					}?.newInput(forDisconnector: self)
					withExtendedLifetime(previous) {}
					if let i = input {
						d(self, e, i)
					}
				}
			} else {
				// NOTE: we use the successors "internal" functon here since this is always called from successor's `updateActivationInternal` function
				outputSignal.pushInternal(values: capturedValues, error: capturedError, dw: &dw)
			}
		}
		signal.unblockInternal(activationCountAtBlock: blockActivationCount)
		signal.resumeIfPossibleInternal(dw: &dw)
		let tuple = (self.capturedValues, self.capturedError)
		self.capturedValues = []
		self.capturedError = nil
		dw.append { withExtendedLifetime(tuple) {} }
	}
	
	/// Like a `SignalJunction`, a capture can respond to an error by disconnecting instead of delivering.
	fileprivate override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let disconnectAction = disconnectOnError
		return { [weak outputSignal, weak self] (r: Result<T>) -> Void in
			if let d = disconnectAction, case .failure(let e) = r, let s = self, let input = s.disconnect() {
				d(s, e, input)
			} else {
				_ = outputSignal?.send(result: r, predecessor: predecessor, activationCount: ac, activated: activated)
			}
		}
	}
	
	/// Disconnects the succeeding `Signal` (if any).
	///
	/// - returns: the new `SignalInput` for the succeeding `Signal` (if any `Signal` was connected) otherwise nil. If the `SignalInput` value is non-nil and is released, the succeeding `Signal` will be closed.
	public func disconnect() -> SignalInput<T>? {
		var previous: ((SignalCapture<T>, Error, SignalInput<T>) -> ())? = nil
		let result = sync { () -> Signal<T>? in
			previous = disconnectOnError
			return outputs.first?.destination.value
		}?.newInput(forDisconnector: self)
		withExtendedLifetime(previous) {}
		return result
	}
	
	/// The `disconnectOnError` needs to be set inside the mutex, if-and-only-if a successor connects successfully. To allow this to work, the desired `disconnectOnError` function is passed into this function via the `outputAddedSuccessorInternal` called from `addPreceedingInternal` in the `joinFunction`.
	fileprivate override func handleParamFromSuccessor(param: Any) {
		if let p = param as? SignalCaptureParam<T> {
			disconnectOnError = p.disconnectOnError
			sendAsNormal = p.sendAsNormal
		}
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - parameter toInput: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	/// - parameter resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///
	/// - returns: a tuple where the first element is the `SignalInput` result from calling `disconnect` on self. The second element will be:
	///	* .cancelled – if the `SignalInput` wasn't the active input for its `Signal`
	///	* .replaced(SignalInput<T>) - Upon attempting to connect the successor to self, self was found to already have a successor connected (must have occurred on another thread between the separate "disconnect" and "join" steps performed during this function). The `toInput` parameter has been invalidated and the new input is contained in this case value.
	///	* .succeeded – the join succeeded
	public func join(toInput: SignalInput<T>, resend: Bool = false) throws {
		let param = SignalCaptureParam<T>(sendAsNormal: resend, disconnectOnError: nil)
		try joinFunction(processor: self, disconnect: self.disconnect, toInput: toInput, optionalErrorHandler: param)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - parameter toInput: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	/// - parameter resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	/// - parameter onError: if nil, errors from self will be passed through to `toInput`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalCapture` and the input created by calling `disconnect` on it.
	///
	/// - returns: a tuple where the first element is the `SignalInput` result from calling `disconnect` on self. The second element will be:
	///	* .cancelled – if the `SignalInput` wasn't the active input for its `Signal`
	///	* .replaced(SignalInput<T>) - Upon attempting to connect the successor to self, self was found to already have a successor connected (must have occurred on another thread between the separate "disconnect" and "join" steps performed during this function). The `toInput` parameter has been invalidated and the new input is contained in this case value.
	///	* .succeeded – the join succeeded
	public func join(toInput: SignalInput<T>, resend: Bool = false, onError: @escaping (SignalCapture<T>, Error, SignalInput<T>) -> ()) throws {
		let param = SignalCaptureParam<T>(sendAsNormal: resend, disconnectOnError: onError)
		try joinFunction(processor: self, disconnect: self.disconnect, toInput: toInput, optionalErrorHandler: param)
	}
	
	public func subscribe(resend: Bool = false, context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(toInput: input, resend: resend)
		return output.subscribe(context: context, handler: handler)
	}
	
	public func subscribe(resend: Bool = false, onError: @escaping (SignalCapture<T>, Error, SignalInput<T>) -> (), context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(toInput: input, resend: resend, onError: onError)
		return output.subscribe(context: context, handler: handler)
	}
	
	public func subscribeValues(resend: Bool = false, context: Exec = .direct, handler: @escaping (T) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(toInput: input, resend: resend)
		return output.subscribeValues(context: context, handler: handler)
	}
	
	public func subscribeValues(resend: Bool = false, onError: @escaping (SignalCapture<T>, Error, SignalInput<T>) -> (), context: Exec = .direct, handler: @escaping (T) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(toInput: input, resend: resend, onError: onError)
		return output.subscribeValues(context: context, handler: handler)
	}
}

/// A handler applies different rules to the incoming `Signal`s as part of a merge set.
fileprivate class SignalMergeProcessor<T>: SignalProcessor<T, T> {
	let sourceClosesOutput: Bool
	let removeOnDeactivate: Bool
	let mergeSet: SignalMergeSet<T>
	
	init(signal: Signal<T>, sourceClosesOutput: Bool, removeOnDeactivate: Bool, mergeSet: SignalMergeSet<T>, dw: inout DeferredWork) {
		self.sourceClosesOutput = sourceClosesOutput
		self.removeOnDeactivate = removeOnDeactivate
		self.mergeSet = mergeSet
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	/// Can't share mutex since predecessor may swap between different graphs
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	/// If `removeOnDeactivate` is true, then deactivating this `Signal` removes it from the set
	fileprivate override func lastOutputDeactivatedInternal(dw: inout DeferredWork) {
		if removeOnDeactivate {
			guard let output = outputs.first, let os = output.destination.value, let ac = output.activationCount else { return }
			os.mutex.sync {
				guard os.activationCount == ac else { return }
				os.removePreceedingWithoutInterruptionInternal(self, dw: &dw)
			}
		}
	}
	
	/// The handler is largely a passthrough but allso applies `sourceClosesOutput` logic – removing error sending signals that don't close the output.
	fileprivate override func nextHandlerInternal() -> (Result<T>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let closesOutput = sourceClosesOutput
		return { [weak outputSignal, weak self] (r: Result<T>) -> Void in
			if !closesOutput, case .failure = r, let os = outputSignal, let s = self {
				var dw = DeferredWork()
				os.mutex.sync {
					guard os.activationCount == ac else { return }
					os.removePreceedingWithoutInterruptionInternal(s, dw: &dw)
				}
				dw.runWork()
			} else {
				_ = outputSignal?.send(result: r, predecessor: predecessor, activationCount: ac, activated: activated)
			}
		}
	}
}

/// A merge set allows multiple `Signal`s of the same type to dynamically connect to a single output `Signal`. A merge set is analagous to a `SignalInput` in that it controls the input to a `Signal` but instead of controlling it by sending signals, it controls by connecting predecessors.
public class SignalMergeSet<T> {
	fileprivate weak var signal: Signal<T>?
	fileprivate init(signal: Signal<T>) {
		self.signal = signal
	}
	
	/// Connect a new predecessor to the `Signal`
	///
	/// - parameter source:             the predecessor
	/// - parameter sourceClosesOutput: if true, then errors sent via this `Signal` will pass through to the output, closing the output. If false, then if this source sends an error, it will be removed from the merge set without the error being sent through to the output.
	/// - parameter removeOnDeactivate: if true, then when the output is deactivated, this source will be removed from the merge set. If false, then the source will remain connected through deactivation.
	public func add(_ source: Signal<T>, closesOutput: Bool = false, removeOnDeactivate: Bool = false) {
		guard let sig = signal else { return }
		let processor = source.attach { (s, dw) -> SignalMergeProcessor<T> in
			SignalMergeProcessor<T>(signal: s, sourceClosesOutput: closesOutput, removeOnDeactivate: removeOnDeactivate, mergeSet: self, dw: &dw)
		}
		var dw = DeferredWork()
		sig.mutex.sync {
			_ = sig.addPreceedingInternal(processor, param: nil, dw: &dw)
		}
		dw.runWork()
	}
	
	/// Removes a predecessor from the merge set
	///
	/// - parameter source: the predecessor to remove
	public func remove(_ source: Signal<T>) {
		guard let sig = signal else { return }
		var dw = DeferredWork()
		var mergeProcessor: SignalMergeProcessor<T>? = nil
		source.mutex.sync {
			mergeProcessor = source.signalHandler as? SignalMergeProcessor<T>
		}
		
		if let mp = mergeProcessor {
			sig.mutex.sync {
				sig.removePreceedingWithoutInterruptionInternal(mp, dw: &dw)
			}
		}
		dw.runWork()
	}
	
	deinit {
		guard let sig = signal else { return }
		_ = sig.send(result: .failure(SignalError.cancelled), predecessor: nil, activationCount: sig.activationCount, activated: true)
	}
}

/// Reflects the activation state of a `Signal`
/// - normal: Signal will deliver results according to the default behavior of the processing context
/// - disabled: Signal is closed or otherwise inactive. Attempts to send new sseiignals will have no effect. context
/// - synchronous: Signal will attempt to deliver the first `Int` results in the queue synchronously. Results received from synchronous predecessors prior to the completion of activation will be inserted in the queue at the `Int` index and the `Int` value increased. Results received from predecessors with other states will be appended at the end of the queue. context
fileprivate enum SignalDelivery {
	case normal
	case disabled
	case synchronous(Int)
	
	var isDisabled: Bool { if case .disabled = self { return true } else { return false } }
	var isSynchronous: Bool { if case .synchronous = self { return true } else { return false } }
	var isNormal: Bool { if case .normal = self { return true } else { return false } }
}

/// A special set of errors that may be sent through the stream (or returned from `send` functions) to indicate specific close conditions
///
/// - closed:    indicates the end-of-stream was reached normally
/// - inactive:  the signal graph is not activated and the signal was not sent (connect endpoints to activate)
/// - duplicate: when attempts to add multiple listeners to non-multi `Signals` occurs, the subsequent attempts are instead connected to a separate, pre-closed `Signal` that sends this error.
/// - cancelled: returned from `send` functions when the sender is no longer the "active" sender for the destination `Signal`. Sent through a graph when an active `SignalInput` is released.
/// - timeout:   used by some utility functions to indicate a time limit has expired
public enum SignalError: Error {
	case closed
	case inactive
	case duplicate
	case cancelled
	case timeout
}

/// Used by the Signal<T>.combine(second:context:processor:) method
public enum EitherResult2<U, V> {
	case result1(Result<U>)
	case result2(Result<V>)
}

/// Used by the Signal<T>.combine(second:third:context:processor:) method
public enum EitherResult3<U, V, W> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
}

/// Used by the Signal<T>.combine(second:third:fourth:context:processor:) method
public enum EitherResult4<U, V, W, X> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
	case result4(Result<X>)
}

/// Used by the Signal<T>.combine(second:third:fourth:fifth:context:processor:) method
public enum EitherResult5<U, V, W, X, Y> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
	case result4(Result<X>)
	case result5(Result<Y>)
}
