//
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

#if SWIFT_PACKAGE
	import Foundation
	import CwlUtils
#endif

/// A composable one-way communication channel that delivers a sequence of `Result<Value>` items to a `handler` function running in a potentially different execution context. Delivery is serial (FIFO) queuing as required.
///
/// The intended use case is as a serialized asynchronous change propagation framework.
///
/// The word "signal" may be used in a number of ways, so keep in mind:
///	- `Signal`: this class
///	- signal graph: one or more `Signal` instances connected together via handlers (instances of the private class `SignalHandler`)
///	- signal: the sequence of `Result` instances, or individual instances of `Result` that pass through instances of `Signal`
///	- `signal`: when used as a parameter label, refers to an instance of `Signal` (invidivual `Result` instances are identified as `result`, `value` or `error` in parameter labels).
///
/// # INTERNAL DESIGN
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
/// The first of these points is ensured through the use of `itemProcessing`, `holdCount` and `DeferredWork`. The `itemProcessing` and `holdCount` block a queue while out-of-mutex work is performed. The `DeferredWork` defers work to be performed later, once the stack has unwound and no mutexes are held.
/// This ensures that no problematic work is performed inside a mutex but it means that we often have "in-flight" work occurring outside a mutex that might no longer be valid. So we need to combine this work identifiers that allow us to reject out-of-date work. That's where the second point becomes important.
/// The "activationCount" for an `Signal` changes any time a manual input control is generated (`SignalInput`/`SignalMergedInput`), any time a first predecessor is added or any time there are predecessors connected and the `delivery` state changes to or from `.disabled`. Combined with the fact that it is not possible to disconnect and re-add the same predecessor to a multi-input Signal (SignalMergedInput or SignalCombiner) this guarantees any messages from out-of-date but still in-flight deliveries are ignored.
///
/// # LIMITS TO THREADSAFETY
///
/// While all actions on `Signal` are threadsafe, there are some points to keep in mind:
///   1. Threadsafe means that the internal members of the `Signal` class will remain threadsafe and your own closures will always be invoked correctly on the provided `Exec` context. However, this doesn't mean that work you perform in processing closures is always threadsafe; shared references or mutable captures in your closures will still require mutual exclusion. The easiest way to do this involves specifying an `Exec` context on your signal processing stages that apply mutual exclusion automatically when invoking the processor.
///   2. Related to the previous point... synchronous pipelines are processed in nested fashion. More specifically, when `send` is invoked on a `SignalNext`, the next stage in the signal graph is invoked while the previous stage is still on the call-stack. If you use a mutex on a synchronous stage, do not attempt to re-enter the mutex on subsequent stages or you risk deadlock. If you want to apply a mutex to your processing stages, you should either ensure the stages are invoked *asynchronously* (choose an async `Exec` context) or you should apply the mutex to the first stage and use `.direct` for subsquent stages (knowing that they'll be protected by the mutex from the *first* stage).
///   3. Delivery of signal values is guaranteed to be in-order but other guarantees are conditional. Specifically, synchronous delivery through signal processing closures is only guaranteed when signals are sent from a single thread. If a subsequent result is sent to a `Signal` on a second thread while the `Signal` is processing a previous result from a first thread the subsequent result will be *queued* and handled on the *first* thread once it completes processing the earlier values.
///   4. Handlers, captured values and state values will be released *outside* all contexts or mutexes. If you capture an object with `deinit` behavior in a processing closure, you must apply any synchronization context yourself.
public class Signal<Value> {
	public typealias ValueType = Value
	
	// Protection for all mutable members on this class and any attached `signalHandler`.
	// NOTE 1: This mutex may be shared between synchronous serially connected `Signal`s (for memory and performance efficiency).
	// NOTE 2: It is noted that a `DispatchQueue` mutex would be preferrable since it respects libdispatch's QoS, however, it is not possible (as of Swift 4) to use `DispatchQueue` as a mutex without incurring a heap allocated closure capture so `PThreadMutex` is used instead to avoid a factor of 10 performance loss.
	fileprivate final var mutex: PThreadMutex
	
	// The graph can be disconnected and reconnected and various actions may occur outside locks, it's helpful to determine which actions are no longer relevant. The `Signal` controls this through `delivery` and `activationCount`. The `delivery` controls the basic lifecycle of a simple connected graph through 4 phases: `.disabled` (pre-connection) -> `.sychronous` (connecting) -> `.normal` (connected) -> `.disabled` (disconnected).
	fileprivate final var delivery = SignalDelivery.disabled { didSet { itemContextNeedsRefresh = true } }
	
	// The graph can be disconnected and reconnected and various actions may occur outside locks, it's helpful to determine which actions are no longer relevant because they are associated with a phase of a previous connection.
	// When connected to a preceeding `SignalPredecessor`, `activationCount` is incremented on each connection and disconnection to ensure that actions associated with a previous phase of a previous connection are rejected. 
	// When connected to a preceeding `SignalInput`, `activationCount` is incremented solely when a new `SignalInput` is attached or the current input is invalidated (joined using an `SignalJunction`).
	fileprivate final var activationCount: Int = 0 { didSet { itemContextNeedsRefresh = true } }
	
	// Queue of values pending dispatch (NOTE: the current `item` is not stored in the queue)
	// Normally the queue is FIFO but when an `Signal` has multiple inputs, the "activation" from each input will be considered before any post-activation inputs.
	fileprivate final var queue = Deque<Result<Value>>()
	
	// A `holdCount` may indefinitely block the queue for one of two reasons:
	// 1. a `SignalNext` is retained outside its handler function for asynchronous processing of an item
	// 2. a `SignalCapture` handler has captured the activation but a `Signal` to receive the remainder is not currently connected
	// Accordingly, the `holdCount` should only have a value in the range [0, 2]
	fileprivate final var holdCount: UInt8 = 0
	
	// When the handler for a given `Result` is being involed, the `itemProcessing` is set to `true`. The effect is equivalent to `holdCount`.
	fileprivate final var itemProcessing: Bool = false
	
	// Notifications for the inverse of `delivery == .disabled`, accessed exclusively through the `generate` constructor. Can be used for lazy construction/commencement, resetting to initial state on graph disconnect and reconnect or cleanup after graph deletion.
	// A signal is used here instead of a simple function callback since re-entrancy-safe queueing and context delivery are needed.
	// WARNING: this is actually a (Signal<SignalInput<Value>?>, SignalEndpont<SignalInput<Value>?>)? but we use `Any` to avoid huge optimization overheads.
	fileprivate final var newInputSignal: (Signal<Any?>, SignalEndpoint<Any?>)? = nil
	
	// If there is a preceeding `Signal` in the graph, its `SignalProcessor` is stored in this variable. Note that `SignalPredecessor` is always an instance of `SignalProcessor`.
	/// If Swift gains an `OrderedSet` type, it should be used here in place of this `Set` and the `sortedPreceeding` accessor, below.
	fileprivate final var preceeding: Set<OrderedSignalPredecessor>
	
	// A total of all preceeding ever added (this value is used to reject predecessors that are not up-to-date with the latest graph structure)
	fileprivate final var preceedingCount: Int = 0
	
	// The destination of this `Signal`. This value is `nil` on construction and may be set non-nil once only.
	fileprivate final weak var signalHandler: SignalHandler<Value>? = nil { didSet { itemContextNeedsRefresh = true } }
	
	// This is a cache of values that can be read outside the lock by the current owner of the `itemProcessing` flag.
	fileprivate final var itemContext = ItemContext<Value>(activationCount: 0)
	fileprivate final var itemContextNeedsRefresh = true
	
	/// Create a manual input/output pair where values sent to the `SignalInput` are passed through the `Signal` output.
	///
	/// - returns: a (`SignalInput`, `Signal`) tuple being the input and output for this stage in the signal pipeline.
	public static func create() -> (input: SignalInput<Value>, signal: Signal<Value>) {
		let s = Signal<Value>()
		s.activationCount = 1
		return (SignalInput(signal: s, activationCount: s.activationCount), s)
	}
	
	/// A version of created that creates a `SignalMultiInput` instead of a `SignalInput`.
	///
	/// - Returns: the (input, signal)
	public static func createMultiInput() -> (input: SignalMultiInput<Value>, signal: Signal<Value>) {
		let s = Signal<Value>()
		var dw = DeferredWork()
		s.mutex.sync { s.updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw) }
		dw.runWork()
		return (SignalMultiInput(signal: s), s)
	}
	
	/// A version of created that creates a `SignalMergedInput` instead of a `SignalInput`.
	///
	/// - Returns: the (input, signal)
	public static func createMergedInput() -> (input: SignalMergedInput<Value>, signal: Signal<Value>) {
		let s = Signal<Value>()
		var dw = DeferredWork()
		s.mutex.sync { s.updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw) }
		dw.runWork()
		return (SignalMergedInput(signal: s), s)
	}
	
	/// Similar to `create`, in that it creates a "head" for the graph but rather than immediately providing a `SignalInput`, this function calls the `activationChange` function when the signal graph is activated and provides the newly created `SignalInput` at that time. When the graph deactivates, `nil` is sent to the `activationChange` function. If a subsequent reactivation occurs, the new `SignalInput` for the re-activation is provided.
	///
	/// - Parameters:
	///   - context: the `activationChange` will be invoked in this context
	///   - activationChange: receives inputs on activation and nil on each deactivation
	/// - Returns: the constructed `Signal`
	public static func generate(context: Exec = .direct, activationChange: @escaping (_ input: SignalInput<Value>?) -> Void) -> Signal<Value> {
		let s = Signal<Value>()
		let nis = Signal<Any?>()
		s.newInputSignal = (nis, nis.subscribe(context: context) { r in
			if case .success(let v) = r {
				activationChange(v as? SignalInput<Value>)
			}
		})
		return s
	}
	
	/// Appends a `SignalEndpoint` listener to the value emitted from this `Signal`. The endpoint will "activate" this `Signal` and all direct antecedents in the graph (which may start lazy operations deferred until activation).
	///
	/// - Parameters:
	///   - context: context: the `Exec` context used to invoke the `handler`
	///   - handler: the function invoked for each received `Result`
	/// - Returns: the created `SignalEndpoint` (if released, the subscription will be cancelled).
	public final func subscribe(context: Exec = .direct, handler: @escaping (Result<Value>) -> Void) -> SignalEndpoint<Value> {
		return attach { (s, dw) in
			SignalEndpoint<Value>(signal: s, dw: &dw, context: context, handler: handler)
		}
	}
	
	/// A version of `subscribe` that retains the `SignalEndpoint` internally, keeping the signal graph alive. The `SignalEndpoint` is cancelled and released if the signal closes or if the handler returns `false` after any signal.
	///
	/// NOTE: this subscriber deliberately creates a reference counted loop. If the signal is never closed and the handler never returns false, it will result in a memory leak. This function should be used only when `self` is guaranteed to close or the handler `false` condition is guaranteed.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public final func subscribeWhile(context: Exec = .direct, handler: @escaping (Result<Value>) -> Bool) {
		_ = attach { (s, dw) in
			var handlerRetainedEndpoint: SignalEndpoint<Value>? = nil
			let endpoint = SignalEndpoint<Value>(signal: s, dw: &dw, context: context, handler: { r in
				withExtendedLifetime(handlerRetainedEndpoint) {}
				if !handler(r) || r.isError {
					handlerRetainedEndpoint?.cancel()
					handlerRetainedEndpoint = nil
				}
			})
			handlerRetainedEndpoint = endpoint
			return endpoint
		}
	}
	
	/// Appends a disconnected `SignalJunction` to this `Signal` so outputs can be repeatedly joined and disconnected from this graph in the future.
	///
	/// - Returns: the `SignalJunction<Value>`
	public final func junction() -> SignalJunction<Value> {
		return attach { (s, dw) -> SignalJunction<Value> in
			return SignalJunction<Value>(signal: s, dw: &dw)
		}
	}
	
	/// Appends a handler function that transforms the value emitted from this `Signal` into a new `Signal`.
	///
	/// - Parameters:
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: the function invoked for each received `Result`
	/// - Returns: the created `Signal`
	public final func transform<U>(context: Exec = .direct, handler: @escaping (Result<Value>, SignalNext<U>) -> Void) -> Signal<U> {
		return Signal<U>(processor: attach { (s, dw) in
			SignalTransformer<Value, U>(signal: s, dw: &dw, context: context, handler: handler)
		})
	}
	
	/// Appends a handler function that transforms the value emitted from this `Signal` into a new `Signal`.
	///
	/// - Parameters:
	///   - initialState: the initial value for a state value associated with the handler. This value is retained and if the signal graph is deactivated, the state value is reset to this value.
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: the function invoked for each received `Result`
	/// - Returns: the transformed output `Signal`
	public final func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<Value>, SignalNext<U>) -> Void) -> Signal<U> {
		return Signal<U>(processor: attach { (s, dw) in
			SignalTransformerWithState<Value, U, S>(signal: s, initialState: initialState, dw: &dw, context: context, handler: handler)
		})
	}
	
	// Internal wrapper used by the `combine` functions to ignore error `Results` (which would only be due to graph changes between internal nodes) and process the values with the user handler.
	//
	// - Parameter handler: the user handler
	@discardableResult private static func successHandler<U, V>(_ handler: @escaping (U, SignalNext<V>) -> Void) -> (Result<U>, SignalNext<V>) -> Void {
		return { (r: Result<U>, n: SignalNext<V>) in
			switch r {
			case .success(let v): handler(v, n)
			case .failure(let e): n.send(result: .failure(e))
			}
		}
	}
	
	/// Appends a handler function that receives inputs from this and another `Signal<U>`. The `handler` function applies any transformation it wishes an emits a (potentially) third `Signal` type.
	///
	/// - Parameters:
	///   - second:   the other `Signal` that is, along with `self` used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self` or `second` as `EitherResult2<Value, U>` (an enum which may contain either `.result1` or `.result2` corresponding to `self` or `second`) and sends results to an `SignalNext<V>`.
	/// - Returns: an `Signal<V>` which is the result stream from the `SignalNext<V>` passed to the `handler`.
	public final func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<Value, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return Signal<EitherResult2<Value, U>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult2<Value, U>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult2<Value, U>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult2<Value, U>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult2<Value, U>.result2)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and two other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fourth `Signal` type.
	///
	/// - Parameters:
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second` or `third` as `EitherResult3<Value, U, V>` (an enum which may contain either `.result1`, `.result2` or `.result3` corresponding to `self`, `second` or `third`) and sends results to an `SignalNext<W>`.
	/// - Returns: an `Signal<W>` which is the result stream from the `SignalNext<W>` passed to the `handler`.
	public final func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<Value, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return Signal<EitherResult3<Value, U, V>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result3)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and three other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) fifth `Signal` type.
	///
	/// - Parameters:
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - fourth: the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second`, `third` or `fourth` as `EitherResult4<Value, U, V, W>` (an enum which may contain either `.result1`, `.result2`, `.result3` or `.result4` corresponding to `self`, `second`, `third` or `fourth`) and sends results to an `SignalNext<X>`.
	/// - Returns: an `Signal<X>` which is the result stream from the `SignalNext<X>` passed to the `handler`.
	public final func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<Value, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return Signal<EitherResult4<Value, U, V, W>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result4)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	/// Appends a handler function that receives inputs from this and four other `Signal`s. The `handler` function applies any transformation it wishes an emits a (potentially) sixth `Signal` type.
	///
	/// - Parameters:
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - fourth: the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	///   - fifth: the fifth `Signal`, after `self`, `second`, `third` and `fourth`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second`, `third`, `fourth` or `fifth` as `EitherResult5<Value, U, V, W, X>` (an enum which may contain either `.result1`, `.result2`, `.result3`, `.result4` or  `.result5` corresponding to `self`, `second`, `third`, `fourth` or `fifth`) and sends results to an `SignalNext<Y>`.
	/// - Returns: an `Signal<Y>` which is the result stream from the `SignalNext<Y>` passed to the `handler`.
	public final func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<Value, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return Signal<EitherResult5<Value, U, V, W, X>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result4)
		}).addPreceeding(processor: fifth.attach { (s5, dw) -> SignalCombiner<X, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s5, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result5)
		}).transform(context: context, handler: Signal.successHandler(handler))
	}
	
	// Internal wrapper used by the `combine(initialState:...)` functions to ignore error `Results` (which would only be due to graph changes between internal nodes) and process the values with the user handler.
	//
	// - Parameter handler: the user handler
	@discardableResult private static func successHandlerWithState<S, U, V>(_ handler: @escaping (inout S, U, SignalNext<V>) -> Void) -> (inout S, Result<U>, SignalNext<V>) -> Void {
		return { (s: inout S, r: Result<U>, n: SignalNext<V>) in
			switch r {
			case .success(let v): handler(&s, v, n)
			case .failure(let e): n.send(result: .failure(e))
			}
		}
	}
	
	/// Similar to `combine(second:context:handler:)` with an additional "state" value.
	///
	/// - Parameters:
	///   - initialState: the initial value of a "state" value passed into the closure on each invocation. The "state" will be reset to this value if the `Signal` deactivates.
	///   - second:   the other `Signal` that is, along with `self` used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self` or `second` as `EitherResult2<Value, U>` (an enum which may contain either `.result1` or `.result2` corresponding to `self` or `second`) and sends results to an `SignalNext<V>`.
	/// - Returns: an `Signal<V>` which is the result stream from the `SignalNext<V>` passed to the `handler`.
	public final func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<Value, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return Signal<EitherResult2<Value, U>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult2<Value, U>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult2<Value, U>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult2<Value, U>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult2<Value, U>.result2)
		}).transform(initialState: initialState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Similar to `combine(second:third:context:handler:)` with an additional "state" value.
	///
	/// - Parameters:
	///   - initialState: the initial value of a "state" value passed into the closure on each invocation. The "state" will be reset to this value if the `Signal` deactivates.
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second` or `third` as `EitherResult3<Value, U, V>` (an enum which may contain either `.result1`, `.result2` or `.result3` corresponding to `self`, `second` or `third`) and sends results to an `SignalNext<W>`.
	/// - Returns: an `Signal<W>` which is the result stream from the `SignalNext<W>` passed to the `handler`.
	public final func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<Value, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return Signal<EitherResult3<Value, U, V>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult3<Value, U, V>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult3<Value, U, V>.result3)
		}).transform(initialState: initialState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Similar to `combine(second:third:fourth:context:handler:)` with an additional "state" value.
	///
	/// - Parameters:
	///   - initialState: the initial value of a "state" value passed into the closure on each invocation. The "state" will be reset to this value if the `Signal` deactivates.
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - fourth: the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second`, `third` or `fourth` as `EitherResult4<Value, U, V, W>` (an enum which may contain either `.result1`, `.result2`, `.result3` or `.result4` corresponding to `self`, `second`, `third` or `fourth`) and sends results to an `SignalNext<X>`.
	/// - Returns: an `Signal<X>` which is the result stream from the `SignalNext<X>` passed to the `handler`.
	public final func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<Value, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return Signal<EitherResult4<Value, U, V, W>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult4<Value, U, V, W>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult4<Value, U, V, W>.result4)
		}).transform(initialState: initialState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Similar to `combine(second:third:fourth:fifthcontext:handler:)` with an additional "state" value.
	///
	/// - Parameters:
	///   - initialState: the initial value of a "state" value passed into the closure on each invocation. The "state" will be reset to this value if the `Signal` deactivates.
	///   - second: the second `Signal`, after `self` used as input to the `handler`
	///   - third: the third `Signal`, after `self` and `second`, used as input to the `handler`
	///   - fourth: the fourth `Signal`, after `self`, `second` and `third`, used as input to the `handler`
	///   - fifth: the fifth `Signal`, after `self`, `second`, `third` and `fourth`, used as input to the `handler`
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: processes inputs from either `self`, `second`, `third`, `fourth` or `fifth` as `EitherResult5<Value, U, V, W, X>` (an enum which may contain either `.result1`, `.result2`, `.result3`, `.result4` or  `.result5` corresponding to `self`, `second`, `third`, `fourth` or `fifth`) and sends results to an `SignalNext<Y>`.
	/// - Returns: an `Signal<Y>` which is the result stream from the `SignalNext<Y>` passed to the `handler`.
	public final func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<Value, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return Signal<EitherResult5<Value, U, V, W, X>>(processor: self.attach { (s1, dw) -> SignalCombiner<Value, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s1, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result1)
		}).addPreceeding(processor: second.attach { (s2, dw) -> SignalCombiner<U, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s2, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result2)
		}).addPreceeding(processor: third.attach { (s3, dw) -> SignalCombiner<V, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s3, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result3)
		}).addPreceeding(processor: fourth.attach { (s4, dw) -> SignalCombiner<W, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s4, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result4)
		}).addPreceeding(processor: fifth.attach { (s5, dw) -> SignalCombiner<X, EitherResult5<Value, U, V, W, X>> in
			SignalCombiner(signal: s5, dw: &dw, context: .direct, handler: EitherResult5<Value, U, V, W, X>.result5)
		}).transform(initialState: initialState, context: context, handler: Signal.successHandlerWithState(handler))
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and is "continuous" (multiple listeners can be attached to the `SignalMulti` and each new listener immediately receives the most recently sent value on "activation").
	///
	/// - parameter initialValues: the immediate value sent to any listeners that connect *before* the first value is sent through this `Signal`
	///
	/// - returns: a continuous `SignalMulti`
	public final func continuous(initialValue: Value) -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([initialValue], nil), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r -> (Array<Value>, Error?) in
				let previous: (Array<Value>, Error?) = (a, p)
				switch r {
				case .success(let v): a = [v]
				case .failure(let e): a = []; p = e
				}
				return previous
			})
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and is "continuous" (multiple listeners can be attached to the `SignalMulti` and each new listener immediately receives the most recently sent value on "activation"). Any listeners that connect before the first signal is received will receive no value on "activation".
	///
	/// - returns: a continuous `SignalMulti`
	public final func continuous() -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([], nil), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r -> (Array<Value>, Error?) in
				let previous: (Array<Value>, Error?) = (a, p)
				switch r {
				case .success(let v): a = [v]; p = nil
				case .failure(let e): a = []; p = e
				}
				return previous
			})
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` does not immediately activate (it waits until an endpoint activates it normally). The first activator receives no cached values but subsequent activators will receive the most recent value. Upon deactivation, the cached value is discarded and deactivation is propagated normally to antecedents.
	///
	/// - returns: a continuous `SignalMulti`
	public final func continuousWhileActive() -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([], nil), userUpdated: false, activeWithoutOutputs: false, dw: &dw, context: .direct, updater: { a, p, r -> (Array<Value>, Error?) in
				let previous: (Array<Value>, Error?) = (a, p)
				switch r {
				case .success(let v): a = [v]; p = nil
				case .failure(let e): a = []; p = e
				}
				return previous
			})
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents and offers full "playback" (multiple listeners can be attached to the `SignalMulti` and each new listener receives the entire history of values previously sent through this `Signal` upon "activation").
	///
	/// - returns: a playback `SignalMulti`
	public final func playback() -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([], nil), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r -> (Array<Value>, Error?) in
				switch r {
				case .success(let v): a.append(v)
				case .failure(let e): p = e
				}
				return ([], nil)
			})
		})
	}
	
	/// Appends a new `Signal` to this `Signal`. The new `Signal` immediately activates its antecedents and caches any values it receives until this the new `Signal` itself is activated – at which point it sends all prior values upon "activation" and subsequently reverts to passthough.
	///
	/// - returns: a "cache until active" `Signal`.
	public final func cacheUntilActive() -> Signal<Value> {
		return Signal<Value>(processor: attach { (s, dw) in
			SignalCacheUntilActive(signal: s, dw: &dw)
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. While multiple listeners are permitted, there is no caching, activation signal or other changes inherent in this new `Signal` – newly connected listeners will receive only those values sent after they connect.
	///
	/// - returns: a "multicast" `SignalMulti`.
	public final func multicast() -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([], nil), userUpdated: false, activeWithoutOutputs: false, dw: &dw, context: .direct, updater: nil)
		})
	}
	
	/// Appends a new `SignalMulti` to this `Signal`. The new `SignalMulti` immediately activates its antecedents. Every time a value is received, it is passed to an "updater" which creates an array of activation values and an error that will be used for any new listeners.
	/// Consider this as an operator that allows the creation of a custom "bring-up-to-speed" value for new listeners.
	///
	/// - Parameters:
	///   - initialValues: activation values used when *before* any incoming value is received (if you wan't to specify closed as well, use `preclosed` instead)
	///   - context: the execution context where the `updater` will run
	///   - updater: run for each incoming `Result<Value>` to update the buffered activation values
	/// - Returns: a `SignalMulti` with custom activation
	public final func customActivation(initialValues: Array<Value> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<Value>, _ cachedError: inout Error?, _ incoming: Result<Value>) -> Void) -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: (initialValues, nil), userUpdated: true, activeWithoutOutputs: true, dw: &dw, context: context) { (bufferedValues: inout Array<Value>, bufferedError: inout Error?, incoming: Result<Value>) -> (Array<Value>, Error?) in
				let oldActivationValues = bufferedValues
				let oldError = bufferedError
				updater(&bufferedValues, &bufferedError, incoming)
				return (oldActivationValues, oldError)
			}
		})
	}
	
	/// This operator is a reducer, reducing the stream of incoming values down to a single, internal `State` value. A value of the same `State` type is emitted on each iteration (it may be the internal state or another value as appropriate).
	///
	/// This operator combines aspects of `transform` and `customActivation` into a single operation. The incoming values are transformed to the internal state type and it is possible to maintain a separate cached value and emitted value.
	///
	/// The interal `State` is used as the activation value. If new listeners attach to the `SignalMulti`, midstream, they will receive the internal `State` as an activation value. It should be kept in a form suitable for this purpose.
	///
	/// - Parameters:
	///   - initialState: initial activation value for the stream and internal state for the reducer
	///   - context: execution context where `reducer` will run
	///   - reducer: the function that combines the state with incoming values and emits differential updates
	/// - Returns: a `SignalMulti<State>`
	public final func reduce<State>(initialState: State, context: Exec = .direct, reducer: @escaping (_ state: inout State, _ message: Value) throws -> State) -> SignalMulti<State> {
		return SignalMulti<State>(processor: attach { (s, dw) in
            return SignalReducer<Value, State>(signal: s, state: Result<State>.success(initialState), dw: &dw, context: context) { (state: inout Result<State>, message: Result<Value>) -> Result<State> in
				switch (state, message) {
                    state =  Result<State> { try reducer(&s, m) }
                    return state
                case (.failure, _):
                    return state
				case (_, .failure(let e)):
					state = .failure(e)
                    return state
				}
			}
		})
	}
	
	/// Constructs a `SignalMulti` with an array of "activation" values and a closing error.
	///
	/// - Parameters:
	///   - values: an array of values
	///   - error: the closing error for the `Signal`
	/// - Returns: a `SignalMulti`
	public static func preclosed<S: Sequence>(values: S, error: Error = SignalError.closed) -> SignalMulti<Value> where S.Iterator.Element == Value {
		return SignalMulti<Value>(processor: Signal<Value>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: (Array(values), error), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r in ([], nil) })
		})
	}
	
	/// Constructs a `SignalMulti` with a single activation value and a closing error.
	///
	/// - Parameters:
	///   - value: a single value
	///   - error: the closing error for the `Signal`
	/// - Returns: a `SignalMulti`
	public static func preclosed(_ value: Value, error: Error = SignalError.closed) -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: Signal<Value>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([value], error), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r in ([], nil) })
		})
	}
	
	/// Constructs a `SignalMulti` that is already closed with an error.
	///
	/// - Parameter error: the closing error for the `Signal`
	/// - Returns: a `SignalMulti`
	public static func preclosed(error: Error = SignalError.closed) -> SignalMulti<Value> {
		return SignalMulti<Value>(processor: Signal<Value>().attach { (s, dw) in
			SignalMultiProcessor(signal: s, values: ([], error), userUpdated: false, activeWithoutOutputs: true, dw: &dw, context: .direct, updater: { a, p, r in ([], nil) })
		})
	}
	
	/// Appends an immediately activated handler that captures any activation values from this `Signal`. The captured values can be accessed from the `SignalCapture<Value>` using the `activation()` function. The `SignalCapture<Value>` can then be joined to further `Signal`s using the `join(to:)` function on the `SignalCapture<Value>`.
	///
	/// - Returns: the handler than can be used to obtain activation values and join to subsequent nodes.
	public final func capture() -> SignalCapture<Value> {
		return attach { (s, dw) -> SignalCapture<Value> in
			SignalCapture<Value>(signal: s, dw: &dw)
		}
	}
	
	/// If this `Signal` can attach a new handler, this function runs the provided closure (which is expected to construct and set the new handler) and returns the handler. If this `Signal` can't attach a new handler, returns the result of running the closure inside the mutex of a separate preclosed `Signal`.
	///
	/// This method serves three purposes:
	///	1) It enforces the idea that the `signalHandler` should be constructed under this `Signal`'s mutex, providing the `DeferredWork` required by the `signalHandler` constructor interface.
	///	2) It enforces the rule that multiple listen attempts should be immediately closed with a `.duplicate` error
	///	3) It allows abstraction over the actual `Signal` used for attachment (self for single listener and a newly created `Signal` for multi listener).
	///
	/// - Parameter constructor: the handler constructor function
	/// - Returns: the result from the constructor (typically an SignalHandler)
	fileprivate func attach<R>(constructor: (Signal<Value>, inout DeferredWork) -> R) -> R where R: SignalHandler<Value> {
		var dw = DeferredWork()
		let result: R? = mutex.sync {
			signalHandler == nil ? constructor(self, &dw) : nil
		}
		dw.runWork()
		if let r = result {
			return r
		} else {
			preconditionFailure("Multiple outputs added to single listener Signal.")
		}
	}
	
	/// Returns a copy of the preceeding set, sorted by "order". This allows deterministic sending of results through the graph – older connections are prioritized over newer.
	fileprivate var sortedPreceeding: Array<OrderedSignalPredecessor> {
		return preceeding.sorted(by: { (a, b) -> Bool in
			return a.order < b.order
		})
	}
	
	/// Constructor for signal graph head. Called from `create`.
	fileprivate init() {
		mutex = PThreadMutex()
		preceeding = []
	}
	
	/// Constructor for a `Signal` that is the output for a `SignalProcessor`.
	///
	/// - Parameter processor: input source for this `Signal`
	fileprivate init<U>(processor: SignalProcessor<U, Value>) {
		preceedingCount += 1
		preceeding = [processor.wrappedWithOrder(preceedingCount)]
		
		if processor.successorsShareMutex {
			mutex = processor.signal.mutex
		} else {
			mutex = PThreadMutex()
		}
		if !(self is SignalMulti<Value>) {
			var dw = DeferredWork()
			mutex.sync {
				// Since this function must be used only in cases where the processor is *also* new, this can't be `duplicate` or `loop`
				try! processor.outputAddedSuccessorInternal(self, param: nil, activationCount: nil, dw: &dw)
			}
			dw.runWork()
		}
	}
	
	// Need to close the `newInputSignal` and detach from all predecessors on deinit.
	deinit {
		_ = newInputSignal?.0.send(result: .failure(SignalError.cancelled), predecessor: nil, activationCount: 0, activated: true)
		
		var dw = DeferredWork()
		mutex.sync {
			removeAllPreceedingInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	// Connects this `Signal` to a preceeding SignalPredecessor. Other connection functions must go through this.
	//
	// - Parameters:
	//   - newPreceeding: the preceeding SignalPredecessor to add
	//   - param: this function may invoke `outputAddedSuccessorInternal` internally. If it does this `param` will be passed as the `param` for that function.
	//   - dw: required
	// - Throws: any error from `outputAddedSuccessorInternal` invoked on `newPreceeding`
	fileprivate final func addPreceedingInternal(_ newPreceeding: SignalPredecessor, param: Any?, dw: inout DeferredWork) throws {
		preceedingCount += 1
		let wrapped = newPreceeding.wrappedWithOrder(preceedingCount)
		preceeding.insert(wrapped)
		
		do {
			try newPreceeding.outputAddedSuccessorInternal(self, param: param, activationCount: (delivery.isDisabled || preceeding.count == 1) ? Optional<Int>.none : Optional<Int>(activationCount), dw: &dw)
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
		} catch {
			preceeding.remove(wrapped)
			throw error
		}
	}
	
	// A wrapper around addPreceedingInternal for use outside the mutex. Only used by the `combine` functions (which is why it returns `self` – it's a syntactic convenience in those methods).
	//
	// - Parameter processor: the preceeding SignalPredecessor to add
	// - Returns: self (for syntactic convenience in the `combine` methods)
	fileprivate final func addPreceeding(processor: SignalPredecessor) -> Signal<Value> {
		var dw = DeferredWork()
		mutex.sync {
			// Since this is for use only by the `combine` functions, it cann't be `duplicate` or `loop`
			try! addPreceedingInternal(processor, param: nil, dw: &dw)
		}
		dw.runWork()
		return self
	}
	
	// Removes a (potentially) non-unique predecessor. Used only from `SignalMergeSet` and `SignalMergeProcessor`. This is one of two, independent, functions for removing preceeding. The other being `removeAllPreceedingInternal`.
	//
	// - Parameters:
	//   - oldPreceeding: the predecessor to remove
	//   - dw: required
	fileprivate final func removePreceedingWithoutInterruptionInternal(_ oldPreceeding: SignalPredecessor, dw: inout DeferredWork) {
		if preceeding.remove(oldPreceeding.wrappedWithOrder(0)) != nil {
			oldPreceeding.outputRemovedSuccessorInternal(self, dw: &dw)
		}
	}
	
	// Removes all predecessors and invalidate all previous inputs. This is one of two, independent, functions for removing preceeding. The other being `removePreceedingWithoutInterruptionInternal`.
	//
	// - Parameters:
	//   - oldPreceeding: the predecessor to remove
	//   - dw: required
	fileprivate final func removeAllPreceedingInternal(dw: inout DeferredWork) {
		if preceeding.count > 0 {
			dw.append { [preceeding] in withExtendedLifetime(preceeding) {} }
			
			// Careful to use *sorted* preceeding to propagate graph changes deterministically
			sortedPreceeding.forEach { $0.base.outputRemovedSuccessorInternal(self, dw: &dw) }
			preceeding = []
		}
		updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw)
	}
	
	// Increment the activation count.
	//
	// - Parameters:
	//   - andInvalidateAllPrevious: if true, removes all items from the queue (should be false only when transitioning from synchronous to normal).
	//   - dw: required
	fileprivate final func updateActivationInternal(andInvalidateAllPrevious: Bool, dw: inout DeferredWork) {
		assert(mutex.unbalancedTryLock() == false)
		
		activationCount = activationCount &+ 1
		
		if andInvalidateAllPrevious {
			let oldItems = Array<Result<Value>>(queue)
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
	
	// Invokes `removeAllPreceedingInternal` if and only if the `forDisconnector` matches the current `preceeding.first`
	//
	// - Parameter forDisconnector: the disconnector requesting this change
	// - Returns: if the predecessor matched, then a new `SignalInput<Value>` for this `Signal`, otherwise `nil`.
	fileprivate final func newInput(forDisconnector: SignalProcessor<Value, Value>) -> SignalInput<Value>? {
		var dw = DeferredWork()
		let result = mutex.sync { () -> SignalInput<Value>? in
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
	
	// Tests whether a `Result` from a `predecessor` with `activationCount` should be accepted or rejected.
	//
	// - Parameters:
	//   - predecessor: the source of the `Result`
	//   - activationCount: the `activationCount` when the source was connected
	// - Returns: true if `preceeding` contains `predecessor` and `self.activationCount` matches `activationCount`
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
		return preceeding.contains(p.wrappedWithOrder(0))
	}
	
	// The `itemContext` holds information uniquely used by the currently processing item so it can be read outside the mutex. This may only be called immediately before calling `blockInternal` to start a processing item (e.g. from `send` or `resume`.
	//
	// - Parameter dw: required
	// - Returns: false if the `signalHandler` was `nil`, true otherwise.
	fileprivate final func refreshItemContextInternal(_ dw: inout DeferredWork) -> Bool {
		assert(mutex.unbalancedTryLock() == false)
		assert(holdCount == 0 && itemProcessing == false)
		if itemContextNeedsRefresh {
			if let h = signalHandler {
				dw.append { [itemContext] in withExtendedLifetime(itemContext) {} }
				itemContext = ItemContext(activationCount: activationCount, context: h.context, synchronous: delivery.isSynchronous, handler: h.handler)
				itemContextNeedsRefresh = false
			} else {
				return false
			}
		}
		return true
	}
	
	// Sets the `itemContext` back to an "idle" state (releasing any handler closure and setting `activationCount` to zero.
	// This function may be called only from `specializedSyncPop` or `pop`.
	///
	/// - Returns: an empty/idle `ItemContext`
	fileprivate final func clearItemContextInternal() -> ItemContext<Value> {
		assert(mutex.unbalancedTryLock() == false)
		let oldContext = itemContext
		itemContext = ItemContext(activationCount: 0)
		return oldContext
	}
	
	// The primary `send` function (although the `push` functions do also send).
	// Sends `result`, assuming `fromInput` matches the current `self.input` and `self.delivery` is enabled
	//
	// - Parameters:
	//   - result: the value or error to pass to any attached handler
	//   - predecessor: the `SignalInput` or `SignalNext` delivering the handler
	//   - activationCount: the activation count from the predecessor to match against internal value
	//   - activated: whether the predecessor is already in `normal` delivery mode
	// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult fileprivate final func send(result: Result<Value>, predecessor: Unmanaged<AnyObject>?, activationCount: Int, activated: Bool) -> SignalError? {
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
		
		assert(holdCount == 0 && itemProcessing == false)
		
		if itemContextNeedsRefresh {
			var dw = DeferredWork()
			let hasHandler = refreshItemContextInternal(&dw)
			if hasHandler {
				itemProcessing = true
			}
			mutex.unbalancedUnlock()
			
			// We need to be extremely careful that any previous handlers, replaced in the `refreshItemContextInternal` function are released *here* if we're going to re-enter the lock and that we've *already* acquired the `itemProcessing` Bool. There's a little bit of dancing around in this `if itemContextNeedsRefresh` block to ensure these two things are true.
			dw.runWork()
			
			if !hasHandler {
				return SignalError.inactive
			}
			mutex.unbalancedLock()
		} else {
			itemProcessing = true
		}
		
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
	
	// A secondary send function used to push values and possibly and end-of-stream error onto the `newInputSignal`. The push is not handled immediately but is deferred until the `DeferredWork` runs. Since values are *always* queued, this is less efficient than `send` but it avoids re-entrancy into self if the `newInputSignal` immediately tries to send values back to us.
	//
	// - Parameters:
	//   - values: pushed onto this `Signal`'s queue
	//   - error: pushed onto this `Signal`'s queue
	//   - activationCount: activationCount of the sender (must match the internal value)
	//   - dw: used to dispatch the signal safely outside the parent's mutex
	fileprivate final func push(values: Array<Value>, error: Error?, activationCount: Int, activated: Bool, dw: inout DeferredWork) {
		mutex.sync {
			guard self.activationCount == activationCount else { return }
			pushInternal(values: values, error: error, activated: activated, dw: &dw)
		}
	}
	
	// A secondary send function used to push activation values and activation errors. Since values are *always* queued, this is less efficient than `send` but it can safely be invoked inside mutexes.
	//
	// - Parameters:
	//   - values: pushed onto this `Signal`'s queue
	//   - error: pushed onto this `Signal`'s queue
	//   - dw: used to dispatch the signal safely outside the parent's mutex
	fileprivate final func pushInternal(values: Array<Value>, error: Error?, activated: Bool, dw: inout DeferredWork) {
		assert(mutex.unbalancedTryLock() == false)
		
		guard values.count > 0 || error != nil else {
			dw.append {
				withExtendedLifetime(values) {}
				withExtendedLifetime(error) {}
			}
			return
		}
		
		if !activated, case .synchronous(let count) = delivery {
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
	
	// Used in SignalCapture.handleSynchronousToNormalInternal to handle a situation where a deactivation and reactivation occurs *while* `itemProcessing` so the next capture is in the queue instead of being captured. This function extracts the queued value for capture before transition to normal.
	//
	// - Returns: the queued items under the synchronous count.
	fileprivate final func pullQueuedSynchronousInternal() -> (values: Array<Value>, error: Error?) {
		if case .synchronous(let count) = delivery, count > 0 {
			var values = Array<Value>()
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
	
	// Invoke the user handler and deactivates the `Signal` if `result` is a `failure`.
	//
	// - Parameter result: passed to the `itemContext.handler`
	private final func invokeHandler(_ result: Result<Value>) {
		// It is subtle but it is more efficient to *repeat* the handler invocation for each case (rather than using a fallthrough or hoisting out of the `switch`), since Swift can handover ownership, rather than retaining.
		switch result {
		case .success:
			itemContext.handler(result)
		case .failure:
			itemContext.handler(result)
			var dw = DeferredWork()
			mutex.sync {
				if itemContext.activationCount == activationCount, !delivery.isDisabled {
					signalHandler?.deactivateInternal(dueToLackOfOutputs: false, dw: &dw)
				}
			}
			dw.runWork()
		}
	}
	
	// Dispatches the `result` to the current handler in the appropriate context then pops the next `result` and attempts to invoke the handler with the next result (if any)
	//
	// - Parameter result: for sending to the handler
	fileprivate final func dispatch(_ result: Result<Value>) {
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
	/// - Returns: the next result for processing, if any
	fileprivate final func pop() -> Result<Value>? {
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
	
	// Increment the `holdCount`.
	///
	/// - Parameter activationCount: must match the internal value or the block request will be ignored
	fileprivate final func block(activationCount: Int) {
		mutex.sync {
			guard self.activationCount == activationCount else { return }
			blockInternal()
		}
	}
	
	// Decrement the `holdCount`, if the `activationCountAtBlock` provided matches `self.activationCount`
	//
	// NOTE: the caller must resume processing if holdCount reaches zero and there are queued items.
	///
	/// - Parameter activationCountAtBlock: must match the internal value or the block request will be ignored
	fileprivate final func unblockInternal(activationCountAtBlock: Int) {
		guard self.activationCount == activationCountAtBlock else { return }
		assert(mutex.unbalancedTryLock() == false)
		assert(holdCount >= 1 && holdCount <= 2)
		holdCount -= 1
	}
	
	// If the holdCount is zero and there are queued items, increments the hold count immediately and starts processing in the deferred work.
	///
	/// - Parameter dw: required
	fileprivate final func resumeIfPossibleInternal(dw: inout DeferredWork) {
		if holdCount == 0, itemProcessing == false, !queue.isEmpty {
			if !refreshItemContextInternal(&dw) {
				// The weakly held handler has asynchronously released.
				return
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
	///
	/// - Parameter activationCount: must match the internal value or the block request will be ignored
	fileprivate final func unblock(activationCountAtBlock: Int) {
		var dw = DeferredWork()
		mutex.sync {
			unblockInternal(activationCountAtBlock: activationCountAtBlock)
			resumeIfPossibleInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	// Changes the value of the `self.delivery` instance variable and handles associated lifecycle updates (like incrementing the activation count).
	//
	/// - Parameters:
	///   - newDelivery: new value for `self.delivery`
	///   - dw: required
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
			newInputSignal?.0.push(values: [SignalInput(signal: self, activationCount: activationCount)], error: nil, activationCount: 0, activated: true, dw: &dw)
		case .synchronous:
			if preceeding.count > 0 {
				updateActivationInternal(andInvalidateAllPrevious: false, dw: &dw)
			}
		case .disabled:
			updateActivationInternal(andInvalidateAllPrevious: true, dw: &dw)
			_ = newInputSignal?.0.push(values: [Optional<SignalInput<Value>>.none], error: nil, activationCount: 0, activated: true, dw: &dw)
		}
	}
}

/// `SignalMulti<Value>` is the only subclass of `Signal<Value>`. It represents a `Signal<Value>` that allows attaching multiple listeners (a normal `Signal<Value>` is "single owner" and will immediately close any subsequent listeners after the first with a `SignalError.duplicate` error).
/// This class is not constructed directly but is instead created from one of the `SignalMulti<Value>` returning functions on `Signal<Value>`, including `playback()`, `multicast()` and `continuous()`.
public final class SignalMulti<Value>: Signal<Value> {
	fileprivate let spawnSingle: (SignalPredecessor) -> Signal<Value>
	
	fileprivate override init<U>(processor: SignalProcessor<U, Value>) {
		assert(processor.multipleOutputsPermitted, "Construction of SignalMulti from a single output processor is illegal.")
		spawnSingle = { (p: SignalPredecessor) in
			return Signal<Value>(processor: p as! SignalProcessor<U, Value>)
		}
		super.init(processor: processor)
	}
	
	// Technically listeners are never attached to the `SignalMulti` itself. Instead, it creates a new `Signal` branching off the preceeding `SignalMultiProcessor<Value>` and the attach is applied to that new `Signal<Value>`.
	fileprivate override func attach<R>(constructor: (Signal<Value>, inout DeferredWork) -> R) -> R where R: SignalHandler<Value> {
		return spawnSingle(preceeding.first!.base).attach(constructor: constructor)
	}
}

/// Used to provide a light abstraction over the `SignalInput` and `SignalNext` types.
/// In general, the only real purpose of this protocol is to enable the `send(value:)`, `send(error:)`, `close()` extensions in "SignalExternsions.swift"
public protocol SignalSender {
	associatedtype Value
	
	/// The primary signal sending function
	///
	/// - Parameter result: the value or error to send, composed as a `Result`
	/// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult func send(result: Result<Value>) -> SignalError?
}

/// An `SignalInput` is used to send values to the "head" `Signal`s in a signal graph. It is created using the `Signal<Value>.create()` function.
public class SignalInput<Value>: SignalSender, Cancellable {
	public typealias ValueType = Value
	
	fileprivate final weak var signal: Signal<Value>?
	fileprivate final let activationCount: Int
	
	// Create a new `SignalInput` (usually created by the `Signal<Value>.create` function)
	//
	// - Parameters:
	//   - signal: the destination signal
	//   - activationCount: to be sent with each send to the signal
	fileprivate init(signal: Signal<Value>, activationCount: Int) {
		self.signal = signal
		self.activationCount = activationCount
	}
	
	/// The primary signal sending function
	///
	/// - Parameter result: the value or error to send, composed as a `Result`
	/// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult public func send(result: Result<Value>) -> SignalError? {
		guard let s = signal else { return SignalError.cancelled }
		return s.send(result: result, predecessor: nil, activationCount: activationCount, activated: true)
	}
	
	/// The purpose for this method is to obtain a true `SignalInput` (instead of a `SignalMultiInput` or `SignalMergedInput`. A true `SignalInput` is faster for multiple send operations and is needed internally by the `join` methods.
	/// The base `SignalInput` implementation returns `self`.
	public func singleInput() -> SignalInput<Value> {
		return self
	}
	
	/// Implementation of `Cancellable` that sends a `SignalError.cancelled`. You wouldn't generally invoke this yourself; it's intended to be invoked if the `SignalInput` owner is released and the `SignalInput` is no longer retained.
	public func cancel() {
		_ = send(result: .failure(SignalError.cancelled))
	}
	
	deinit {
		cancel()
	}
}

// A struct that stores data associated with the item currently being handled. Under the `Signal` mutex, if the `itemProcessing` flag is acquired, the fields of this struct are filled in using `Signal` and `SignalHandler` data and the contents of the struct can be used by the current thread *outside* the mutex.
private struct ItemContext<Value> {
	let context: Exec
	let synchronous: Bool
	let handler: (Result<Value>) -> Void
	let activationCount: Int
	
	// Create a blank ItemContext
	init(activationCount: Int) {
		self.context = .direct
		self.synchronous = false
		self.handler = { r in }
		self.activationCount = activationCount
	}
	
	// Create a filled-in ItemContext
	init(activationCount: Int, context: Exec, synchronous: Bool, handler: @escaping (Result<Value>) -> Void) {
		self.activationCount = activationCount
		self.context = context
		self.synchronous = synchronous
		self.handler = handler
	}
}

// If `Signal<Value>` is a delivery channel, then `SignalHandler` is the destination to which it delivers.
// While the base `SignalHandler<Value>` is not "abstract" in any technical sense, it doesn't do anything by default. Subclasses include `SignalEndpoint` (the user "exit" point for signal results), `SignalProcessor` (used for transforming signals between instances of `Signal<Value>`), `SignalJunction` (for enabling dynamic graph connection and disconnections).
// `SignalHandler<Value>` is never directly created or held by users of the CwlSignal library. It is implicitly created when one of the listening or transformation methods on `Signal<Value>` are invoked.
fileprivate class SignalHandler<Value> {
	final let signal: Signal<Value>
	final let context: Exec
	final var handler: (Result<Value>) -> Void { didSet { signal.itemContextNeedsRefresh = true } }
	
	// Base constructor sets the `signal`, `context` and `handler` and implicitly activates if required.
	//
	// - Parameters:
	//   - signal: a `SignalHandler` is attached to its predecessor `Signal` for its lifetime
	//   - dw: used for performing activation outside any enclosing mutex, if necessary
	//   - context: where the `handler` function should be invoked
	init(signal: Signal<Value>, dw: inout DeferredWork, context: Exec) {
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
		if activeWithoutOutputsInternal {
			if activateInternal(dw: &dw) {
				let count = self.signal.activationCount
				dw.append { self.endActivation(activationCount: count) }
			}
		}
	}
	
	// Default behavior does nothing prior to activation
	fileprivate func initialHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { r in }
	}
	
	// Convenience wrapper around the mutex from the `Signal` which is used to protect the handler
	//
	// - Parameter execute: the work to perform inside the mutex
	// - Returns: the result from the `execute closure
	// - Throws: basic rethrow from the `execute` closure
	final func sync<Value>(execute: () throws -> Value) rethrows -> Value {
		signal.mutex.unbalancedLock()
		defer { signal.mutex.unbalancedUnlock() }
		return try execute()
	}
	
	// True if this node activates predecessors even when it has no active successors
	fileprivate var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return false
	}
	
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
	
	// As an optimization, successive `Signal`s are placed under the *same* mutex as any preceeding `.sync` `SignalHandler`s
	// `SignalJunction`, `SignalCombiner`, `SignalCapture` and `SignalMultiInputProcessor` all returns `false` since they involve either changing connectivity or multiple connectivity.
	fileprivate var successorsShareMutex: Bool {
		if case .direct = context {
			return true
		} else {
			return false
		}
	}
	
	// Activation changes the delivery, based on whether there are preceeding `Signal`s.
	// If delivery is changed to synchronous, `endActivation` must be called in the deferred work.
	///
	/// - Parameter dw: required
	/// - Returns: true if a transition to `.synchronous` occurred
	fileprivate final func activateInternal(dw: inout DeferredWork) -> Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		if signal.delivery.isDisabled {
			signal.changeDeliveryInternal(newDelivery: .synchronous(0), dw: &dw)
			return true
		}
		return false
	}
	
	// Completes the transition to `.normal` delivery at the end of the `.synchronous` stage.
	///
	/// - Parameter dw: required
	fileprivate final func endActivationInternal(dw: inout DeferredWork) {
		if signal.delivery.isSynchronous {
			handleSynchronousToNormalInternal(dw: &dw)
			signal.changeDeliveryInternal(newDelivery: .normal, dw: &dw)
		}
	}
	
	// Completes the transition to `.normal` delivery at the end of the `.synchronous` stage.
	///
	/// - Parameter activationCount: must match the internal value or the attempt will be rejected
	fileprivate final func endActivation(activationCount: Int) {
		var dw = DeferredWork()
		sync {
			guard signal.activationCount == activationCount else { return }
			endActivationInternal(dw: &dw)
		}
		dw.runWork()
	}
	
	// If this property returns false, attempts to connect more than one output will be rejected. The rejection information is used primarily by SignalJunction which performs disconnect and join as two separate steps so it needs the rejection to ensure two threads haven't tried to join simultaneously.
	fileprivate var multipleOutputsPermitted: Bool {
		return false
	}
	
	// Override point invoked from `endActivationInternal` used in `SignalCapture`
	// - Parameter dw: required
	fileprivate func handleSynchronousToNormalInternal(dw: inout DeferredWork) {
	}
	
	// Changes delivery to disabled *and* resets the handler to the initial handler.
	// - Parameter dw: required
	fileprivate final func deactivateInternal(dueToLackOfOutputs: Bool, dw: inout DeferredWork) {
		assert(signal.mutex.unbalancedTryLock() == false)
		if !activeWithoutOutputsInternal || !dueToLackOfOutputs {
			signal.changeDeliveryInternal(newDelivery: .disabled, dw: &dw)
			dw.append { [handler] in
				withExtendedLifetime(handler) {}
				
				// Endpoints may release themselves on deactivation so we need to keep ourselves alive until outside the lock
				withExtendedLifetime(self) {}
			}
			if !activeWithoutOutputsInternal {
				handler = initialHandlerInternal()
			} else {
				handler = { r in }
			}
		}
	}
}

// A hashable wrapper around an SignalPredecessor existential that also embeds an order value to allow ordering
// NOTE 1: the order is *not* part of the equality or hashValue so a wrapper can be created with an arbitrary order to test for the presence of a given SignalPredecessor.
// NOTE 2: if Swift gains an OrderedSet, it might be possible to replace this with `Hashable` conformance on `SignalPredecessor`.
fileprivate struct OrderedSignalPredecessor: Hashable {
	let base: SignalPredecessor
	let order: Int
	init(base: SignalPredecessor, order: Int) {
		self.base = base
		self.order = order
	}
	
	var hashValue: Int { return Int(bitPattern: Unmanaged<AnyObject>.passUnretained(base).toOpaque()) }
	static func ==(lhs: OrderedSignalPredecessor, rhs: OrderedSignalPredecessor) -> Bool {
		return lhs.base === rhs.base
	}
}

// A protocol used for communicating from successor `Signal`s to predecessor `SignalProcessor`s in the signal graph.
// Used for connectivity and activation.
fileprivate protocol SignalPredecessor: class {
	func outputActivatedSuccessorInternal(_ successor: AnyObject, activationCount: Int, dw: inout DeferredWork)
	func outputCompletedActivationSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func outputDeactivatedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func outputAddedSuccessorInternal(_ successor: AnyObject, param: Any?, activationCount: Int?, dw: inout DeferredWork) throws
	func outputRemovedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork)
	func predecessorsSuccessorInternal(loopCheck: AnyObject) -> Bool
	var loopCheckValue: AnyObject { get }
	func wrappedWithOrder(_ order: Int) -> OrderedSignalPredecessor
}

// Easy construction of a hashable wrapper around an SignalPredecessor existential
extension SignalPredecessor {
	func wrappedWithOrder(_ order: Int) -> OrderedSignalPredecessor {
		return OrderedSignalPredecessor(base: self, order: order)
	}
}

// All `Signal`s, except those with endpoint handlers, are fed to another `Signal`. A `SignalProcessor` is how this is done. This is the abstract base for all handlers that connect to another `Signal`. The default implementation can only connect to a single output (concrete subclass `SignalMultiprocessor` is used for multiple outputs) but a majority of the architecture for any number of outputs is contained in this class.
// This class allows its outputs to have a different value type compared to the Signal for this class, although only SignalTransformer, SignalTransformerWithState and SignalCombiner take advantage – all other subclasses derive from SignalProcessor<Value, Value>.
fileprivate class SignalProcessor<Value, U>: SignalHandler<Value>, SignalPredecessor {
	typealias OutputsArray = Array<(destination: Weak<Signal<U>>, activationCount: Int?)>
	var outputs = OutputsArray()
	
	// Common implementation for a nextHandlerInternal. Currently used only from SignalCacheUntilActive and SignalCombiner
	//
	// - Parameters:
	//   - processor: the `SignalProcessor` instance
	//   - transform: the transformation applied from input to output
	// - Returns: a function usable as the return value to `nextHandlerInternal`
	fileprivate static func simpleNext(processor: SignalProcessor<Value, U>, transform: @escaping (Result<Value>) -> Result<U>) -> (Result<Value>) -> Void {
		assert(processor.signal.mutex.unbalancedTryLock() == false)
		guard let output = processor.outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return processor.initialHandlerInternal() }
		let activated = processor.signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(processor)
		return { [weak outputSignal] (r: Result<Value>) -> Void in _ = outputSignal?.send(result: transform(r), predecessor: predecessor, activationCount: ac, activated: activated) }
	}
	
	// Determines if a `Signal` is one of the current outputs.
	//
	// - Parameter signal: possible output
	// - Returns: true if `signal` is contained in the outputs
	fileprivate final func isOutputInternal(_ signal: Signal<U>) -> Int? {
		assert(signal.mutex.unbalancedTryLock() == false)
		for (i, o) in outputs.enumerated() {
			if let d = o.destination.value, d === signal {
				return i
			}
		}
		return nil
	}
	
	/// Identity used for checking loops (needs to be the mutex since the mutex is shared vertically through the graph, any traversal looking for potential loops could deadlock before noticing a loop with any other value)
	fileprivate final var loopCheckValue: AnyObject { return signal.mutex }
	
	// Performs a depth-first graph traversal looking for the specified `SignalPredecessor`
	//
	// - Parameter contains: the search value
	// - Returns: true if `contains` was found, false otherwise
	func predecessorsSuccessorInternal(loopCheck: AnyObject) -> Bool {
		// Only check the value when successors don't share the mutex (i.e. when we have a boundary of some kind).
		if !successorsShareMutex && loopCheck === self.loopCheckValue {
			return true
		}
		var result = false
		runSuccesorAction {
			// Don't need to traverse sortedPreceeding (unsorted is fine for an ancestor check)
			for p in signal.preceeding {
				if p.base.predecessorsSuccessorInternal(loopCheck: loopCheck) {
					result = true
					return
				}
			}
		}
		return result
	}
	
	// Pushes activation values to newly joined outputs. By default, there is no activation so this function is intended to be overridden. Currently overridden by `SignalMultiProcessor` and `SignalCacheUntilActive`.
	//
	// - Parameters:
	//   - index: identifies the output
	//   - dw: required by pushInternal
	fileprivate func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
	}
	
	// When an output changes activation, this function is called.
	//
	// - Parameters:
	//   - index: index of the activation changed output
	//   - activationCount: new count received
	//   - dw: required
	// - Returns: any response from `activateInternal` (true if started activating)
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
		} else if activationCount == nil && !signal.delivery.isDisabled && !activeWithoutOutputsInternal {
			var anyStillActive = false
			for o in outputs {
				if o.activationCount != nil {
					anyStillActive = true
					break
				}
			}
			if !anyStillActive {
				deactivateInternal(dueToLackOfOutputs: true, dw: &dw)
			}
		}
		
		if activationCount != nil, !previous {
			firstOutputActivatedInternal(dw: &dw)
		} else if activationCount == nil, !anyActiveOutputsInternal {
			lastOutputDeactivatedInternal(dw: &dw)
		}
		return result
	}
	
	// Helper function that applies the mutex around the supplied function, if needed.
	//
	// - parameter action: function to be run inside the mutex
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
	
	// Invoked from successor `Signal`s when they activate
	//
	// - Parameters:
	//   - successor: a `Signal` (must be a Signal<U>)
	//   - activationCount: new activation count value for the `Signal`
	//   - dw: required
	fileprivate final func outputActivatedSuccessorInternal(_ successor: AnyObject, activationCount: Int, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { fatalError() }
			if let i = isOutputInternal(sccr) {
				_ = updateOutputInternal(index: i, activationCount: activationCount, dw: &dw)
			}
		}
	}
	
	// Invoked from successor when it completes activation and transitions to `.normal` delivery
	//
	// - Parameters:
	//   - successor: the successor whose activation status has changed (must be a Signal<U>)
	//   - dw: required
	func outputCompletedActivationSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { fatalError() }
			if let _ = isOutputInternal(sccr), case .synchronous = signal.delivery {
				endActivationInternal(dw: &dw)
			}
		}
	}
	
	// Invoked from successor `Signal`s when they deactivate
	//
	// - Parameters:
	//   - successor: must be a Signal<U>
	//   - dw: required
	fileprivate final func outputDeactivatedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { fatalError() }
			if let i = self.isOutputInternal(sccr) {
				_ = updateOutputInternal(index: i, activationCount: nil, dw: &dw)
			}
		}
	}
	
	// Overrideable function to receive additional information when a successor attaches. Used by SignalJunction and SignalCapture to pass "onError" closures via the successor into the mutex. It shouldn't be possible to pass a parameter unless one is expected, so the default implementation is a `fatalError`.
	//
	// - parameter param: usually a closure.
	fileprivate func handleParamFromSuccessor(param: Any) {
		fatalError()
	}
	
	// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate var needsPredecessorCheck: Bool {
		return false
	}
	
	// A successor connected
	//
	// - Parameters:
	//   - successor: must be a Signal<U>
	//   - param: see `handleParamFromSuccessor`
	//   - activationCount: initial activation count to use
	//   - dw: required
	// - Throws: a possible SignalJoinError if there's a connection failure.
	fileprivate final func outputAddedSuccessorInternal(_ successor: AnyObject, param: Any?, activationCount: Int?, dw: inout DeferredWork) throws {
		var error: SignalJoinError<Value>? = nil
		runSuccesorAction {
			guard outputs.isEmpty || multipleOutputsPermitted else {
				error = SignalJoinError<Value>.duplicate(nil)
				return
			}
			guard let sccr = successor as? Signal<U> else { fatalError() }
			
			if needsPredecessorCheck, let predecessor = sccr.signalHandler as? SignalPredecessor {
				// Don't need to traverse sortedPreceeding (unsorted is fine for an ancestor check)
				for p in signal.preceeding {
					if p.base.predecessorsSuccessorInternal(loopCheck: predecessor.loopCheckValue) {
						// Throw an error here and trigger the preconditionFailure outside the lock (otherwise precondition catching tests may deadlock).
						error = SignalJoinError<Value>.loop
						dw.append { preconditionFailure("Signals must not be joined in a loop.") }
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
		if let e = error {
			throw e
		}
	}
	
	// Called when a successor is removed
	//
	// - Parameters:
	//   - successor: must be a Signal<U>
	//   - dw: required
	fileprivate final func outputRemovedSuccessorInternal(_ successor: AnyObject, dw: inout DeferredWork) {
		runSuccesorAction {
			guard let sccr = successor as? Signal<U> else { fatalError() }
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
	fileprivate func nextHandlerInternal() -> (Result<Value>) -> Void {
		preconditionFailure()
	}
}

// Implementation of a processor that can output to multiple `Signal`s. Used by `continuous`, `continuous`, `playback`, `multicast`, `customActivation` and `preclosed`.
fileprivate final class SignalMultiProcessor<Value>: SignalProcessor<Value, Value> {
	typealias Updater = (_ activationValues: inout Array<Value>, _ preclosed: inout Error?, _ result: Result<Value>) -> (Array<Value>, Error?)
	let updater: Updater?
	var activationValues: Array<Value>
	var preclosed: Error?
	let userUpdated: Bool
	let activeWithoutOutputs: Bool
	
	// Rather than using different subclasses for each of the "multi" `Signal`s, this one subclass is used for all. However, that requires a few different parameters to enable different behaviors.
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - values: the initial activation values and error
	//   - userUpdated: whether the `updater` is user-supplied and needs value-copying to ensure thread-safety
	//   - activeWithoutOutputs: whether the handler should immediately activate
	//   - dw: required
	//   - context: where the `updater` will be run
	//   - updater: when a new signal is received, updates the cached activation values and error
	init(signal: Signal<Value>, values: (Array<Value>, Error?), userUpdated: Bool, activeWithoutOutputs: Bool, dw: inout DeferredWork, context: Exec, updater: Updater?) {
		precondition((values.1 == nil && values.0.isEmpty) || updater != nil, "Non empty activation values requires always active.")
		self.updater = updater
		self.activationValues = values.0
		self.preclosed = values.1
		self.userUpdated = userUpdated
		self.activeWithoutOutputs = activeWithoutOutputs
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	// Multicast and continuousWhileActive are not preactivated but all others are not.
	fileprivate override var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return activeWithoutOutputs && preclosed == nil
	}
	
	// Multiprocessor can handle multiple outputs
	fileprivate override var multipleOutputsPermitted: Bool {
		return true
	}
	
	// Any values or errors are sent on activation.
	//
	// - Parameters:
	//   - index: identifies the output
	//   - dw: required
	fileprivate final override func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
		// Push as *not* activated (i.e. this is the activation)
		outputs[index].destination.value?.pushInternal(values: activationValues, error: preclosed, activated: false, dw: &dw)
	}
	
	// Multiprocessors are (usually – not multicast) preactivated and may cache the values or errors
	// - Returns: a function to use as the handler prior to activation
	override func initialHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [weak self] r in
			if let s = self {
				_ = s.updater?(&s.activationValues, &s.preclosed, r)
			}
		}
	}
	
	// On result, update any activation values.
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		
		// There's a tricky point here: for multicast, we only want to send to outputs that were connected *before* we started sending this value; otherwise values could be sent to the wrong outputs following asychronous graph manipulations.
		// HOWEVER, when activation values exist, we must ensure that any output that was sent the *old* activation values will receive this new value *regardless* of when it connects.
		// To balance these needs, the outputs array is copied here for "multicast" but isn't copied until immediately after updating the `activationValues` in all other cases
		// There's an additional assumption: (updater == nil) is only possible for "multicast"
		var outs: OutputsArray? = updater != nil ? nil : outputs
		
		let activated = signal.delivery.isNormal
		return { [weak self] r in
			if let s = self {
				if let u = s.updater {
					if s.userUpdated {
						var values = [Value]()
						var error: Error?
						
						// Mutably copy the activation values and error
						s.sync {
							values = s.activationValues
							error = s.preclosed
						}
						
						// Perform the update on the copies
						let expired = u(&values, &error, r)
						
						// Change the authoritative activation values and error
						s.sync {
							s.activationValues = values
							s.preclosed = error
							
							if outs == nil {
								outs = s.outputs
							}
						}
						
						// Make sure any reference to the originals is released *outside* the mutex
						withExtendedLifetime(expired) {}
					} else {
						var expired: (Array<Value>, Error?)? = nil
						
						// Perform the update on the copies
						s.sync {
							expired = u(&s.activationValues, &s.preclosed, r)
							
							if outs == nil {
								outs = s.outputs
							}
						}
						
						// Make sure any expired content is released *outside* the mutex
						withExtendedLifetime(expired) {}
					}
				}
				
				// Send the result *before* changing the authoritative activation values and error
				if let os = outs {
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
}

// Implementation of a processor that can output to multiple `Signal`s. Used by `continuous`, `continuous`, `playback`, `multicast`, `customActivation` and `preclosed`.
fileprivate final class SignalReducer<Value, State>: SignalProcessor<Value, State>, SignalBlockable {
    typealias Reducer = (_ state: inout Result<State>, _ message: Result<Value>) -> Result<State>
	let reducer: Reducer
	var state: Result<State>
	
	init(signal: Signal<Value>, state: Result<State>, dw: inout DeferredWork, context: Exec, reducer: @escaping Reducer) {
		self.reducer = reducer
		self.state = state
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	fileprivate override var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return state.error != nil
	}
	
	fileprivate override var multipleOutputsPermitted: Bool {
		return true
	}
	
	fileprivate func unblock(activationCount: Int) {
		signal.unblock(activationCountAtBlock: activationCount)
	}

	fileprivate final override func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
		// Push as *not* activated (i.e. this is the activation)
		outputs[index].destination.value?.pushInternal(values: state.value.map { [$0] } ?? [], error: state.error, activated: false, dw: &dw)
	}
	
	// Multiprocessors are (usually – not multicast) preactivated and may cache the values or errors
	// - Returns: a function to use as the handler prior to activation
	override func initialHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [weak self] r in
			if let s = self {
				var state = Result<State>.failure(SignalError.closed)

				// Copy the state under the mutex
				s.sync {
					state = s.state
				}
				
				// Perform the update on the copy
				let previous = state
                _ = s.reducer(&state, r)

				// Apply the change to the authoritative version under the mutex
				s.sync {
					s.state = state
				}
				
				// Ensure any old references are released outside the mutex
				withExtendedLifetime(previous) {}
			}
		}
	}
	
	// On result, update any activation values.
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		
		let activated = signal.delivery.isNormal
		return { [weak self] r in
			if let s = self {
				var state = Result<State>.failure(SignalError.closed)
				
				// Copy the state under the mutex
				s.sync {
					state = s.state
				}
				
				// Perform the update on the copy
				let previous = state
                let result = s.reducer(&state, r)

				// Apply the change to the authoritative version under the mutex
				var outputs: OutputsArray = []
				s.sync {
					swap(&state, &s.state)
					outputs = s.outputs
				}
				
				// Ensure any old references are released outside the mutex
				withExtendedLifetime(previous) {}

				let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(s)
				for o in outputs {
					if let d = o.destination.value, let ac = o.activationCount {
						d.send(result: result, predecessor: predecessor, activationCount: ac, activated: activated)
					}
				}
			}
		}
	}
}

// A handler which starts receiving `Signal`s immediately and caches them until an output connects
fileprivate final class SignalCacheUntilActive<Value>: SignalProcessor<Value, Value> {
	var cachedValues: Array<Value> = []
	var cachedError: Error? = nil
	
	// Construct a SignalCacheUntilActive handler
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - dw: required
	init(signal: Signal<Value>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	// Is always active
	fileprivate override var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return true
	}
	
	// Sends the cached values when an output connects
	//
	// - Parameters:
	//   - index: identifies the output
	//   - dw: required
	fileprivate final override func sendActivationToOutputInternal(index: Int, dw: inout DeferredWork) {
		// Push as *not* activated (i.e. this is the activation)
		outputs[index].destination.value?.pushInternal(values: cachedValues, error: cachedError, activated: false, dw: &dw)
	}
	
	/// Caches values prior to an output connecting
	// - Returns: a function to use as the handler prior to activation
	override func initialHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [weak self] r in
			switch r {
			case .success(let v): self?.cachedValues.append(v)
			case .failure(let e): self?.cachedError = e
			}
		}
	}
	
	// Clears the cache immediately after an output connects
	//
	// - Parameter dw: required
	fileprivate override func firstOutputActivatedInternal(dw: inout DeferredWork) {
		let tuple = (self.cachedValues, self.cachedError)
		self.cachedValues = []
		self.cachedError = nil
		dw.append { withExtendedLifetime(tuple) {} }
	}
	
	// Once an output is connected, the handler function is a basic passthrough
	// - Returns: a function to use as the handler after activation
	override func nextHandlerInternal() -> (Result<Value>) -> Void {
		return SignalProcessor.simpleNext(processor: self) { r in r }
	}
}

// An SignalNext will block the preceeding SignalTransformer if it is held beyond the scope of the handler function. This allows out-of-context work to be performed.
fileprivate protocol SignalBlockable: class {
	// When the `needUnblock` property is set to `true` on `SignalNext`, it must invoke this on its `blockable`.
	//
	// - Parameter activationCount: must match the internal value or the unblock will be ignored
	func unblock(activationCount: Int)
	
	// The `needUnblock` property is set by the handler under the handlers mutex, so this function is provided by the `blockable` to safely access `needUnblock`.
	//
	// - Parameter execute: the work to perform inside the mutex
	// - Returns: the result from the `execute closure
	// - Throws: basic rethrow from the `execute` closure
	func sync<Value>(execute: () throws -> Value) rethrows -> Value
}

// An interface used to send signals from the inside of a transformer handler function to the next signal in the graph. Similar to an `SignalInput` but differing on what effects retaining and releasing have.
//	1. Releasing an `SignalInput` will automatically send a `SignalError.cancelled` – that doesn't happend with `SignalNext`.
//	2. Holding onto the `SignalNext` outside the scope of the handler function will block the transformer queue, allowing processing to continue out-of-line until the `SignalNext` is released.
public final class SignalNext<Value>: SignalSender {
	fileprivate weak var signal: Signal<Value>?
	fileprivate weak var blockable: SignalBlockable?
	fileprivate let activationCount: Int
	fileprivate let predecessor: Unmanaged<AnyObject>?
	
	fileprivate let activated: Bool
	
	// NOTE: this property must be accessed under the `blockable`'s mutex
	fileprivate var needUnblock = false
	
	// Constructs with the details of the next `Signal` and the `blockable` (the `SignalTransformer` or `SignalTransformerWithState` to which this belongs). NOTE: predecessor and blockable are typically the same instance, just stored differently, for efficiency.
	//
	// - Parameters:
	//   - signal: the output signal
	//   - predecessor: the preceeding signal
	//   - activationCount: the latest activation count that we've recorded from the signal
	//   - activated: whether the signal is `.normal` (otherwise, it's assumed to be `.synchronous`)
	//   - blockable: same as predecessor but implementing a different protocol and retained a different way
	fileprivate init(signal: Signal<Value>, predecessor: SignalPredecessor, activationCount: Int, activated: Bool, blockable: SignalBlockable) {
		self.signal = signal
		self.blockable = blockable
		self.activationCount = activationCount
		self.activated = activated
		self.predecessor = Unmanaged.passUnretained(predecessor)
	}
	
	// Send simply combines the activation and predecessor information
	//
	// - Parameter result: signal to send
	// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult public func send(result: Result<Value>) -> SignalError? {
		guard let s = signal else { return SignalError.cancelled }
		return s.send(result: result, predecessor: predecessor, activationCount: activationCount, activated: activated)
	}
	
	// When released, if we `needUnblock` (because we've been retained outside the scope of the transformer handler) then unblock the transformer.
	deinit {
		if let nb = blockable?.sync(execute: { return self.needUnblock }), nb == true {
			blockable?.unblock(activationCount: activationCount)
		}
	}
}

// A transformer applies a user transformation to any signal. It's the typical "between two `Signal`s" handler.
fileprivate final class SignalTransformer<Value, U>: SignalProcessor<Value, U>, SignalBlockable {
	typealias UserHandlerType = (Result<Value>, SignalNext<U>) -> Void
	let userHandler: UserHandlerType
	
	// Constructs a `SignalTransformer`
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - dw: required
	//   - context: where the `handler` will be invoked
	//   - handler: the user supplied processing function
	init(signal: Signal<Value>, dw: inout DeferredWork, context: Exec, handler: @escaping UserHandlerType) {
		self.userHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	// Implementation of `SignalBlockable`.
	//
	// - Parameter activationCount: must match the internal value or the unblock will be ignored
	fileprivate func unblock(activationCount: Int) {
		signal.unblock(activationCountAtBlock: activationCount)
	}
	
	/// Invoke the user handler and block if the `next` gains an additional reference count in the process.
	// - Returns: a function to use as the handler after activation
	override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		var next = SignalNext<U>(signal: outputSignal, predecessor: self, activationCount: ac, activated: activated, blockable: self)
		return { [userHandler] r in
			userHandler(r, next)
			
			// This is the runtime overhead of the capturable `SignalNext`.
			if !isKnownUniquelyReferenced(&next), let s = next.blockable as? SignalTransformer<Value, U> {
				s.signal.block(activationCount: next.activationCount)
				
				var previous: ((Result<Value>) -> Void)? = nil
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
fileprivate final class SignalTransformerWithState<Value, U, S>: SignalProcessor<Value, U>, SignalBlockable {
	typealias UserHandlerType = (inout S, Result<Value>, SignalNext<U>) -> Void
	let userHandler: (inout S, Result<Value>, SignalNext<U>) -> Void
	let initialState: S
	
	// Constructs a `SignalTransformer`
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - initialState: initial value to use for the "state" passed to the processing handler on each iteration
	//   - dw: required
	//   - context: where the `handler` will be invoked
	//   - handler: the user supplied processing function
	init(signal: Signal<Value>, initialState: S, dw: inout DeferredWork, context: Exec, handler: @escaping (inout S, Result<Value>, SignalNext<U>) -> Void) {
		self.userHandler = handler
		self.initialState = initialState
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	// Implementation of `SignalBlockable`
	//
	// - Parameter activationCount: must match the internal value or the unblock will be ignored
	fileprivate func unblock(activationCount: Int) {
		signal.unblock(activationCountAtBlock: activationCount)
	}
	
	// Invoke the user handler and block if the `next` gains an additional reference count in the process.
	// - Returns: a function to use as the handler after activation
	override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		var next = SignalNext<U>(signal: outputSignal, predecessor: self, activationCount: ac, activated: activated, blockable: self)
		
		/// Every time the handler is recreated, the `state` value is initialized from the `initialState`.
		var state = initialState
		
		return { [userHandler, weak outputSignal] r in
			userHandler(&state, r, next)
			
			// This is the runtime overhead of the capturable `SignalNext`.
			if !isKnownUniquelyReferenced(&next), let s = next.blockable as? SignalTransformerWithState<Value, U, S> {
				s.signal.block(activationCount: next.activationCount)
				
				// Unlike SignalTransformer without state, we don't use `nextHandlerInternal` to create a new `SignalNext` since we don't want to reset the `state` to `initialState`. Instead, just recreate the `next` object.
				let n = next
				s.sync {
					n.needUnblock = true
					if let os = outputSignal {
						next = SignalNext<U>(signal: os, predecessor: s, activationCount: ac, activated: activated, blockable: s)
					}
					s.signal.itemContextNeedsRefresh = true
				}
				withExtendedLifetime(n) {}
			}
		}
	}
}

/// A processor used by `combine(...)` to transform incoming `Signal`s into the "combine" type. The handler function is typically just a wrap of the preceeding `Result` in a `EitherResultX.resultY`. Other than that, it's a basic passthrough transformer that returns `false` to `successorsShareMutex`.
fileprivate final class SignalCombiner<Value, U>: SignalProcessor<Value, U> {
	let combineHandler: (Result<Value>) -> U
	
	// Constructs a `SignalCombiner`
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - dw: required
	//   - context: where the `handler` will be invoked
	//   - handler: the user supplied processing function
	init(signal: Signal<Value>, dw: inout DeferredWork, context: Exec, handler: @escaping (Result<Value>) -> U) {
		self.combineHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	/// Only one predecessor in a multi-predecessor scenario can share its mutex.
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	/// Simple application of the handler
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		return SignalProcessor.simpleNext(processor: self) { [combineHandler] r in Result<U>.success(combineHandler(r)) }
	}
}

// Common implementation of join behavior used by `SignalJunction` and `SignalCapture`.
//
// - Parameters:
//   - processor: the `SignalJuction` or `SignalCapture`
//   - disconnect: receiver for a new `SignalInput` when the join is disconnected.
//   - to: destination of the join
//   - optionalErrorHandler: passed as the `param` to `addPreceedingInternal`
// - Throws: and `addPreceedingInternal` error or other `SignalJoinError<Value>.cancelled` errors if weak properties can't strongified.
fileprivate func joinFunction<Value>(processor: SignalProcessor<Value, Value>, disconnect: () -> SignalInput<Value>?, to input: SignalInput<Value>, optionalErrorHandler: Any?) throws {
	var dw = DeferredWork()
	defer { dw.runWork() }
	assert(!(input is SignalMultiInput<Value>))
	if let nextSignal = input.signal {
		try nextSignal.mutex.sync { () throws -> () in
			guard input.activationCount == nextSignal.activationCount else {
				throw SignalJoinError<Value>.cancelled
			}
			nextSignal.removeAllPreceedingInternal(dw: &dw)
			do {
				try nextSignal.addPreceedingInternal(processor, param: optionalErrorHandler, dw: &dw)
			} catch {
				switch error {
				case SignalJoinError<Value>.duplicate:
					throw SignalJoinError<Value>.duplicate(SignalInput<Value>(signal: nextSignal, activationCount: nextSignal.activationCount))
				default: throw error
				}
			}
		}
	} else {
		throw SignalJoinError<Value>.cancelled
	}
}

/// A junction is a point in the signal graph that can be disconnected and reconnected at any time. Constructed by calling `join(to:...)` or `junction()` on an `Signal`.
public class SignalJunction<Value>: SignalProcessor<Value, Value>, Cancellable {
	private var disconnectOnError: ((SignalJunction<Value>, Error, SignalInput<Value>) -> ())? = nil
	
	// Constructs a "join" handler
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - dw: required
	init(signal: Signal<Value>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	// Can't share mutex since successor may swap between different graphs
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate override var needsPredecessorCheck: Bool {
		return true
	}
	
	// If a `disconnectOnError` handler is configured, then `failure` signals are not sent through the junction. Instead, the junction is disconnected and the `disconnectOnError` function is given an opportunity to handle the `SignalJunction` (`self`) and `SignalInput` (from the `disconnect`).
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let disconnectAction = disconnectOnError
		return { [weak outputSignal, weak self] (r: Result<Value>) -> Void in
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
	public func disconnect() -> SignalInput<Value>? {
		var previous: ((SignalJunction<Value>, Error, SignalInput<Value>) -> ())? = nil
		let result = sync { () -> Signal<Value>? in
			previous = disconnectOnError
			return outputs.first?.destination.value
		}?.newInput(forDisconnector: self)
		withExtendedLifetime(previous) {}
		return result
	}
	
	/// Implementation of `Cancellable` simply invokes a `disconnect()`
	public func cancel() {
		_ = disconnect()
	}
	
	// Implementation of `Cancellable` requires `cancel` is called in the `deinit`
	deinit {
		cancel()
	}
	
	// The `disconnectOnError` needs to be set inside the mutex, if-and-only-if a successor connects successfully. To allow this to work, the desired `disconnectOnError` function is passed into this function via the `outputAddedSuccessorInternal` called from `addPreceedingInternal` in the `joinFunction`.
	//
	// - Parameter param: received through `addPreceedingInternal` – should be the onError handler from `join(to:resend:onError:)`
	fileprivate override func handleParamFromSuccessor(param: Any) {
		if let p = param as? ((SignalJunction<Value>, Error, SignalInput<Value>) -> ()) {
			disconnectOnError = p
		}
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameter to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalInput<Value>) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(), optionalErrorHandler: nil)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	///   - onError: if nil, errors from self will be passed through to `to`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalJunction` and the input created by calling `disconnect` on it.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalInput<Value>, onError: @escaping (SignalJunction<Value>, Error, SignalInput<Value>) -> ()) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(), optionalErrorHandler: onError)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameter to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalMergedInput<Value>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = false) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate), optionalErrorHandler: nil)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalJunction` will still be `disconnect`ed.
	///   - onError: if nil, errors from self will be passed through to `to`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalJunction` and the input created by calling `disconnect` on it.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalMergedInput<Value>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = false, onError: @escaping (SignalJunction<Value>, Error, SignalInput<Value>) -> ()) throws {
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate), optionalErrorHandler: onError)
	}
	
	/// Disconnect and reconnect to the same input, to deliberately deactivate and reactivate. If `disconnect` returns `nil`, no further action will be taken. Any error attempting to reconnect will be sent to the input.
	public func rejoin() {
		if let input = disconnect() {
			do {
				try join(to: input)
			} catch {
				input.send(result: .failure(error))
			}
		}
	}
	
	/// Disconnect and reconnect to the same input, to deliberately deactivate and reactivate. If `disconnect` returns `nil`, no further action will be taken. Any error attempting to reconnect will be sent to the input.
	///
	/// - Parameter onError: passed through to `join`
	public func rejoin(onError: @escaping (SignalJunction<Value>, Error, SignalInput<Value>) -> ()) {
		if let input = disconnect() {
			do {
				try join(to: input, onError: onError)
			} catch {
				input.send(result: .failure(error))
			}
		}
	}
}

// Used to hold the handler function for onError behavior for `SignalCapture`
struct SignalCaptureParam<Value> {
	let sendAsNormal: Bool
	let disconnectOnError: ((SignalCapture<Value>, Error, SignalInput<Value>) -> ())?
}

/// A "capture" handler separates activation signals (those sent immediately on connection) from normal signals. This allows activation signals to be handled separately or removed from the stream entirely.
/// NOTE: this handler *blocks* delivery between capture and connecting to the output. Signals sent in the meantime are queued.
public final class SignalCapture<Value>: SignalProcessor<Value, Value>, Cancellable {
	private var sendAsNormal: Bool = false
	private var capturedError: Error? = nil
	private var capturedValues: [Value] = []
	private var blockActivationCount: Int = 0
	private var disconnectOnError: ((SignalCapture<Value>, Error, SignalInput<Value>) -> ())? = nil
	
	// Constructs a capture handler
	//
	// - Parameters:
	//   - signal: the predecessor signal
	//   - dw: required
	fileprivate init(signal: Signal<Value>, dw: inout DeferredWork) {
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	// Once an output is connected, `SignalCapture` becomes a no-special-behaviors passthrough handler.
	fileprivate override var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return outputs.count > 0 ? false : true
	}
	
	/// Any activation signals captured can be accessed through this property between construction and activating an output (after that point, capture signals are cleared).
	///
	/// - Returns: and array of values (which may be empty) and an optional error, which are the signals received during activation.
	public func activation() -> (values: [Value], error: Error?) {
		return sync {
			return (values: capturedValues, error: capturedError)
		}
	}
	
	// Since this node operates as a junction, it cannot share mutex
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	// Typical processors *don't* need to check their predecessors for a loop (only junctions do)
	fileprivate override var needsPredecessorCheck: Bool {
		return true
	}
	
	// The initial behavior is to capture
	// - Returns: a function to use as the handler prior to activation
	fileprivate override func initialHandlerInternal() -> (Result<Value>) -> Void {
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
	
	// After the initial "capture" phase, the queue is blocked, causing any non-activation signals to queue.
	// - Parameter dw: required
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
	
	// If this handler disconnected, then it reactivates and reverts to being a "capture".
	// - Parameter dw: required
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
	
	// When an output activates, if `sendAsNormal` is true, the new output is sent any captured values. In all cases, the captured values are cleared at this point and the queue is unblocked.
	// - Parameter dw: required
	fileprivate override func firstOutputActivatedInternal(dw: inout DeferredWork) {
		if sendAsNormal, let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount {
			// Don't deliver errors if `disconnectOnError` is set
			if let d = disconnectOnError, let e = capturedError {
				// NOTE: we use the successors "internal" functon here since this is always called from successor's `updateActivationInternal` function
				// Push as *activated* (i.e. this is deferred from activation to normal)
				outputSignal.pushInternal(values: capturedValues, error: nil, activated: true, dw: &dw)
				dw.append {
					// We need to use a specialized version of disconnect that ensures another disconnect hasn't happened in the meantime. Since it's theoretically possible that this handler could be disconnected and reconnected in the meantime (or deactivated and reactivated) we need to check the output and activationCount to ensure everything's still the same.
					var previous: ((SignalCapture<Value>, Error, SignalInput<Value>) -> ())? = nil
					let input = self.sync { () -> Signal<Value>? in
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
				// Push as *activated* (i.e. this is deferred from activation to normal)
				outputSignal.pushInternal(values: capturedValues, error: capturedError, activated: true, dw: &dw)
			}
		}
		signal.unblockInternal(activationCountAtBlock: blockActivationCount)
		signal.resumeIfPossibleInternal(dw: &dw)
		let tuple = (self.capturedValues, self.capturedError)
		self.capturedValues = []
		self.capturedError = nil
		dw.append { withExtendedLifetime(tuple) {} }
	}
	
	// Like a `SignalJunction`, a capture can respond to an error by disconnecting instead of delivering.
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let disconnectAction = disconnectOnError
		return { [weak outputSignal, weak self] (r: Result<Value>) -> Void in
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
	public func disconnect() -> SignalInput<Value>? {
		var previous: ((SignalCapture<Value>, Error, SignalInput<Value>) -> ())? = nil
		let result = sync { () -> Signal<Value>? in
			previous = disconnectOnError
			return outputs.first?.destination.value
		}?.newInput(forDisconnector: self)
		withExtendedLifetime(previous) {}
		return result
	}
	
	/// Implementation of `Cancellable` simply invokes a `disconnect()`
	public func cancel() {
		_ = self.disconnect()
	}
	
	// Implementation of `Cancellable` requires `cancel` is called in the `deinit`
	deinit {
		cancel()
	}
	
	// The `disconnectOnError` needs to be set inside the mutex, if-and-only-if a successor connects successfully. To allow this to work, the desired `disconnectOnError` function is passed into this function via the `outputAddedSuccessorInternal` called from `addPreceedingInternal` in the `joinFunction`.
	//
	// - Parameter param: received through `addPreceedingInternal` – should be the onError handler from `join(to:resend:onError:)`
	fileprivate override func handleParamFromSuccessor(param: Any) {
		if let p = param as? SignalCaptureParam<Value> {
			disconnectOnError = p.disconnectOnError
			sendAsNormal = p.sendAsNormal
		}
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalInput<Value>, resend: Bool = false) throws {
		let param = SignalCaptureParam<Value>(sendAsNormal: resend, disconnectOnError: nil)
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(), optionalErrorHandler: param)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - onError: if nil, errors from self will be passed through to `to`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalCapture` and the input created by calling `disconnect` on it.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalInput<Value>, resend: Bool = false, onError: @escaping (SignalCapture<Value>, Error, SignalInput<Value>) -> ()) throws {
		let param = SignalCaptureParam<Value>(sendAsNormal: resend, disconnectOnError: onError)
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(), optionalErrorHandler: param)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalMergedInput<Value>, resend: Bool = false, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool) throws {
		let param = SignalCaptureParam<Value>(sendAsNormal: resend, disconnectOnError: nil)
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate), optionalErrorHandler: param)
	}
	
	/// Invokes `disconnect` on self before attemping to join this junction to a successor, identified by its `SignalInput`.
	///
	/// - Parameters:
	///   - to: used to identify an `Signal`. If this `SignalInput` is not the active input for its `Signal`, then no join attempt will occur (although this `SignalCapture` will still be `disconnect`ed.
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - onError: if nil, errors from self will be passed through to `to`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalCapture` and the input created by calling `disconnect` on it.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func join(to: SignalMergedInput<Value>, resend: Bool = false, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool, onError: @escaping (SignalCapture<Value>, Error, SignalInput<Value>) -> ()) throws {
		let param = SignalCaptureParam<Value>(sendAsNormal: resend, disconnectOnError: onError)
		try joinFunction(processor: self, disconnect: self.disconnect, to: to.singleInput(closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate), optionalErrorHandler: param)
	}
	
	/// Appends a `SignalEndpoint` listener to the value emitted from this `SignalCapture`. The endpoint will resume the stream interrupted by the `SignalCapture`.
	///
	/// - Parameters:
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: the function invoked for each received `Result`
	/// - returns: the created `SignalEndpoint`
	public func subscribe(resend: Bool = false, context: Exec = .direct, handler: @escaping (Result<Value>) -> Void) -> SignalEndpoint<Value> {
		let (input, output) = Signal<Value>.create()
		// This could be `duplicate` but that's a precondition failure
		try! join(to: input, resend: resend)
		return output.subscribe(context: context, handler: handler)
	}
	
	/// Appends a `SignalEndpoint` listener to the value emitted from this `SignalCapture`. The endpoint will resume the stream interrupted by the `SignalCapture`.
	///
	/// - Parameters:
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - onError: if nil, errors from self will be passed through to `to`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalCapture` and the input created by calling `disconnect` on it.
	///   - context: the `Exec` context used to invoke the `handler`
	///   - handler: the function invoked for each received `Result`
	/// - returns: the created `SignalEndpoint`
	public func subscribe(resend: Bool = false, onError: @escaping (SignalCapture<Value>, Error, SignalInput<Value>) -> (), context: Exec = .direct, handler: @escaping (Result<Value>) -> Void) -> SignalEndpoint<Value> {
		let (input, output) = Signal<Value>.create()
		// This could be `duplicate` but that's a precondition failure
		try! join(to: input, resend: resend, onError: onError)
		return output.subscribe(context: context, handler: handler)
	}
}

/// When an input to a `SignalMergedInput` sends an error, this behavior determines the effect on the merge set and its output
///
/// - none: the input signal is removed from the merge set but the error is not propagated through to the output. This is default for most `SignalMergedInput` usage.
/// - errors: if the error is not SignalError.closed, then the error is propagated through to the output. This is the default for many Reactive X operators like `flatMap`.
/// - close: any error, including SignalError.closed, is progagated through to the output
public enum SignalClosePropagation {
	case none
	case errors
	case all
	
	/// Determines whether the error should be sent or if the input should be removed instead.
	///
	/// - Parameter error: sent from one of the inputs
	/// - Returns: if `false`, the input that sent the error should be removed but the error should not be sent. If `true`, the error should be sent to the `SignalMergedInput`'s output (whether or not the input is removed is then determined by the `removeOnDeactivate` property).
	public func shouldPropagateError(_ error: Error) -> Bool {
		switch self {
		case .none: return false
		case .errors: return !(error as? SignalError == .closed)
		case .all: return true
		}
	}
}

// A handler that apples the different rules required for inputs to a `SignalMergedInput`.
fileprivate class SignalMultiInputProcessor<Value>: SignalProcessor<Value, Value> {
	let closePropagation: SignalClosePropagation
	let removeOnDeactivate: Bool
	
	// The input is added here to keep it alive at least as long as there are active inputs. You can `cancel` an input to remove all active inputs.
	let multiInput: SignalMultiInput<Value>
	
	// Constructs a `SignalMultiInputProcessor`
	//
	// - Parameters:
	//   - signal: destination of the `SignalMergedInput`
	//   - closePropagation: rules to use when this processor handles an error
	//   - removeOnDeactivate: behavior to apply on deactivate
	//   - mergedInput: the mergedInput that manages this processor
	//   - dw: required
	init(signal: Signal<Value>, multiInput: SignalMultiInput<Value>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool, dw: inout DeferredWork) {
		self.multiInput = multiInput
		self.closePropagation = closePropagation
		self.removeOnDeactivate = removeOnDeactivate
		super.init(signal: signal, dw: &dw, context: .direct)
	}
	
	// Can't share mutex since predecessor may swap between different graphs
	fileprivate override var successorsShareMutex: Bool {
		return false
	}
	
	// If `removeOnDeactivate` is true, then deactivating this `Signal` removes it from the set
	//
	// - parameter dw: required
	fileprivate override func lastOutputDeactivatedInternal(dw: inout DeferredWork) {
		if removeOnDeactivate {
			guard let output = outputs.first, let os = output.destination.value, let ac = output.activationCount else { return }
			os.mutex.sync {
				guard os.activationCount == ac else { return }
				os.removePreceedingWithoutInterruptionInternal(self, dw: &dw)
			}
		}
	}
	
	// The handler is largely a passthrough but allso applies `sourceClosesOutput` logic – removing error sending signals that don't close the output.
	// - Returns: a function to use as the handler after activation
	fileprivate override func nextHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		guard let output = outputs.first, let outputSignal = output.destination.value, let ac = output.activationCount else { return initialHandlerInternal() }
		let activated = signal.delivery.isNormal
		let predecessor: Unmanaged<AnyObject>? = Unmanaged.passUnretained(self)
		let propagation = closePropagation
		return { [weak outputSignal, weak self] (r: Result<Value>) -> Void in
			if case .failure(let e) = r, !propagation.shouldPropagateError(e), let os = outputSignal, let s = self {
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

/// Technically, a `SignalInput` is threadsafe and you could share it between multiple locations, if you wished. However, you might want to `join` multiple incoming signals to a single output – in that case, you need a `SignalMultiInput`.
/// You can use a `SignalMultiInput` like a `SignalInput`, if you wish, but that's not its key purpose. The key purpose of a `SignalMultiInput` is that you can `join` to it, multiple times, spawning multiple `SignalInput`s connected to the same outgoing `Signal`, in much the same way that `SignalMulti` can spawn multiple outgoing `Signal`s connected to the same source `Signal`.
/// There's an important semantic difference here between `SignalInput` and `SignalMultiInput`... when an error is sent to one of the inputs spawned by `SignalMultiInput`, it disconnects the `SignalInput` but the error is not propagated to the output signal. This is in accordance with the idea that `SignalMultiInput` is safe in a shared interface – one incoming signal cannot close the outgoing signal and disconnect all the other signals. If you need incoming signals to have the ability to close the outgoing signal, use the `SignalMergedInput` subclass.
/// Another difference is that a `SignalInput` is invalidated when the graph deactivates whereas `SignalMultiInput` remains valid.
/// NOTE: while a `SignalMultiInput` is generally usable in an external interface, it does include a `cancel` method (which removes all incoming signals and cancels the output). If you want to hide this behavior, you would still need to keep the `SignalMultiInput` internal and expose your own `add` function. 
public class SignalMultiInput<Value>: SignalInput<Value> {
	// Constructs a `SignalMergedInput` (typically called from `Signal<Value>.createMergedInput`)
	//
	// - Parameter signal: the destination `Signal`
	fileprivate init(signal: Signal<Value>) {
		super.init(signal: signal, activationCount: 0)
	}
	
	/// Connect a new predecessor to the `Signal`
	///
	/// - Parameters:
	///   - source: the `Signal` to connect as a new predecessor
	///   - closePropagation: behavior to use when `source` sends an error. See `SignalClosePropagation` for more.
	///   - removeOnDeactivate: if true, then when the output is deactivated, this source will be removed from the merge set. If false, then the source will remain connected through deactivation.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public func add(_ source: Signal<Value>) {
		self.add(source, closePropagation: .none)
	}
	
	// See the comments on the public override in `SignalMergedInput`
	fileprivate func add(_ source: Signal<Value>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = false) {
		guard let sig = signal else { return }
		let processor = source.attach { (s, dw) -> SignalMultiInputProcessor<Value> in
			SignalMultiInputProcessor<Value>(signal: s, multiInput: self, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate, dw: &dw)
		}
		var dw = DeferredWork()
		sig.mutex.sync {
			// This can't be `duplicate` since this a a new processor but `loop` is a precondition failure
			try! sig.addPreceedingInternal(processor, param: nil, dw: &dw)
		}
		dw.runWork()
	}
	
	/// Removes a predecessor from the merge set
	///
	/// - Parameter source: the predecessor to remove
	public final func remove(_ source: Signal<Value>) {
		guard let sig = signal else { return }
		var dw = DeferredWork()
		var mergeProcessor: SignalMultiInputProcessor<Value>? = nil
		source.mutex.sync {
			mergeProcessor = source.signalHandler as? SignalMultiInputProcessor<Value>
		}
		
		if let mp = mergeProcessor {
			sig.mutex.sync {
				sig.removePreceedingWithoutInterruptionInternal(mp, dw: &dw)
			}
		}
		dw.runWork()
	}
	
	/// Connects a new `SignalInput<Value>` to `self`. A single input may be faster than a multi-input over multiple `send` operations.
	public final override func singleInput() -> SignalInput<Value> {
		let (input, signal) = Signal<Value>.create()
		self.add(signal)
		return input
	}
	
	/// The primary signal sending function
	///
	/// NOTE: on `SignalMultiInput` this is a relatively low performance convenience method; it calls `singleInput()` on each send. If you plan to send multiple results, it is more efficient to call `singleInput()`, retain the `SignalInput` that creates and call `SignalInput` on that single input.
	///
	/// - Parameter result: the value or error to send, composed as a `Result`
	/// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult public final override func send(result: Result<Value>) -> SignalError? {
		return singleInput().send(result: result)
	}
	
	/// Implementation of `Cancellable` removes all inputs and sends a `SignalError.cancelled` to the `SignalMergedInput` destination.
	public final override func cancel() {
		guard let sig = signal else { return }
		var dw = DeferredWork()
		sig.mutex.sync {
			sig.removeAllPreceedingInternal(dw: &dw)
			sig.pushInternal(values: [], error: SignalError.cancelled, activated: true, dw: &dw)
		}
		dw.runWork()
	}
}

/// Direct use of `SignalMergedInput` is not particularly common. It's typical use is for internal subgraph construction where you need precise control over the interaction of multiple inputs to a `Signal`.
public class SignalMergedInput<Value>: SignalMultiInput<Value> {
	/// Changes the default closePropagation to `.all`
	public override func add(_ source: Signal<Value>) {
		self.add(source, closePropagation: .all, removeOnDeactivate: false)
	}

	/// Connect a new predecessor to the `Signal`
	///
	/// - Parameters:
	///   - source: the `Signal` to connect as a new predecessor
	///   - closePropagation: behavior to use when `source` sends an error. See `SignalClosePropagation` for more.
	///   - removeOnDeactivate: f true, then when the output is deactivated, this source will be removed from the merge set. If false, then the source will remain connected through deactivation.
	/// - Throws: may throw a `SignalJoinError` (see that type for possible cases)
	public override func add(_ source: Signal<Value>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = false) {
		super.add(source, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}

	/// Creates a new `SignalInput`/`Signal` pair, immediately adds the `Signal` to this `SignalMergedInput` and returns the `SignalInput`.
	///
	/// - Parameters:
	///   - closePropagation: passed to `add(_:closePropagation:removeOnDeactivate:) internally
	///   - removeOnDeactivate: passed to `add(_:closePropagation:removeOnDeactivate:) internally
	/// - Returns: the `SignalInput` that will now feed into this `SignalMergedInput`.
	public final func singleInput(closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = false) -> SignalInput<Value> {
		let (input, signal) = Signal<Value>.create()
		self.add(signal, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
}

/// The primary "exit point" for a signal graph. `SignalEndpoint` provides two important functions:
///	1. a `handler` function which receives signal values and errors
///	2. upon connecting to the graph, `SignalEndpoint` "activates" the signal graph (which allows sending through the graph to occur and may trigger some "on activation" behavior).
/// This class is instantiated by calling `subscribe` on any `Signal`.
public final class SignalEndpoint<Value>: SignalHandler<Value>, Cancellable {
	private let userHandler: (Result<Value>) -> Void
	
	/// Constructor called from `subscribe`
	///
	/// - Parameters:
	///   - signal: the source signal
	///   - dw: required
	///   - context: where `handler` will be run
	///   - handler: invoked when a new signal is received
	fileprivate init(signal: Signal<Value>, dw: inout DeferredWork, context: Exec, handler: @escaping (Result<Value>) -> Void) {
		userHandler = handler
		super.init(signal: signal, dw: &dw, context: context)
	}
	
	// Can't have an `output` so this intial handler is the *only* handler
	// - Returns: a function to use as the handler prior to activation
	fileprivate override func initialHandlerInternal() -> (Result<Value>) -> Void {
		assert(signal.mutex.unbalancedTryLock() == false)
		return { [userHandler] r in userHandler(r) }
	}
	
	// A `SignalEndpoint` is active until closed (receives a `failure` signal)
	fileprivate override var activeWithoutOutputsInternal: Bool {
		assert(signal.mutex.unbalancedTryLock() == false)
		return true
	}
	
	/// A simple test for whether this endpoint has received an error, yet. Not generally needed (responding to state changes is best done through the handler function itself).
	public var isClosed: Bool {
		return sync { signal.delivery.isDisabled }
	}
	
	/// Implementatation of `Cancellable` forces deactivation
	public func cancel() {
		var dw = DeferredWork()
		sync { if !signal.delivery.isDisabled { deactivateInternal(dueToLackOfOutputs: false, dw: &dw) } }
		dw.runWork()
	}
	
	// This is likely redundant but it's required by `Cancellable`
	deinit {
		cancel()
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
/// - cancelled: indicates the signal graph was deconstructed
///		This error will be sent through the graph in one of two situations
///			1. `.cancel` is explicitly called on one of the `Cancellable` entities (`SignalInput`, `SignalJunction`, `SignalCapture` or `SignalMergedInput`).
///			2. a `SignalInput` or `SignalMergedInput` is released while it is active
///		A `.cancelled` error may be an expected "end-of-use" scenario or it may indicate a programmer error.
/// - inactive:  the signal graph is not activated (no endpoints in the graph) and the Result was not sent
/// - duplicate: when attempts to add multiple listeners to non-multi `Signals` occurs, the subsequent attempts are instead connected to a separate, pre-closed `Signal` that sends this error.
/// - timeout:   used by some utility functions to indicate a time limit has expired
public enum SignalError: Error {
	case closed
	case inactive
	case cancelled
	case timeout
}

/// Attempts to join a `SignalInput` to a joinable handler (`SignalMergeSet`, `SignalJunction` or `SignalCapture`) can fail in two different ways.
/// - cancelled: the destination `SignalInput`/`SignalMergeSet` was no longer the active input for its `Signal` (either its `Signal` is joined to something else or `Signal` has been deactivated, invalidating old inputs)
/// - duplicate(`SignalInput<Value>`): the source `Signal` already had an output connected and doesn't support multiple outputs so the join failed. If the join destination was a `SignalInput` then that `SignalInput` was consumed by the attempt so the associated value will be a new `SignalInput` replacing the old one. If the join destination was a `SignalMergeSet`, the associated value will be `nil`.
public enum SignalJoinError<Value>: Error {
	case cancelled
	case loop
	case duplicate(SignalInput<Value>?)
}

/// Used by the Signal<Value>.combine(second:context:handler:) method
public enum EitherResult2<U, V> {
	case result1(Result<U>)
	case result2(Result<V>)
}

/// Used by the Signal<Value>.combine(second:third:context:handler:) method
public enum EitherResult3<U, V, W> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
}

/// Used by the Signal<Value>.combine(second:third:fourth:context:handler:) method
public enum EitherResult4<U, V, W, X> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
	case result4(Result<X>)
}

/// Used by the Signal<Value>.combine(second:third:fourth:fifth:context:handler:) method
public enum EitherResult5<U, V, W, X, Y> {
	case result1(Result<U>)
	case result2(Result<V>)
	case result3(Result<W>)
	case result4(Result<X>)
	case result5(Result<Y>)
}

