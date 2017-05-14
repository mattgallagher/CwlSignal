//
//  CwlSignalExtensions.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2016/08/04.
//  Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation

#if SWIFT_PACKAGE
import CwlUtils
#endif

extension SignalSender {
	/// A convenience version of `send` that wraps a value in `Result.success` before sending
	///
	/// - Parameter value: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send(value: ValueType) -> SignalError? {
		return send(result: .success(value))
	}

	/// A convenience version of `send` that wraps an error in `Result.failure` before sending
	///
	/// - Parameter error: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send(error: Error) -> SignalError? {
		return send(result: .failure(error))
	}
	
	/// Sends a `Result.failure(SignalError.closed)`
	///
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func close() -> SignalError? {
		return send(result: .failure(SignalError.closed))
	}
}

extension Signal {
	/// A convenience version of `subscribe` that only invokes the `processor` on `Result.success`
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received
	/// - Returns: the `SignalEndpoint` created by this function
	public func subscribeValues(context: Exec = .direct, handler: @escaping (ValueType) -> Void) -> SignalEndpoint<ValueType> {
		return subscribe(context: context) { r in
			if case .success(let v) = r {
				handler(v)
			}
		}
	}
	
	/// A version of `subscribe` that creates a reference counted loop to the `SignalEndpoint`, keeping the signal graph alive. Unlike a typical `subscribe` handler (which returns `Void`), this handler returns a `Bool` – the the `Bool` is false, the reference counted loop is broken. The reference counted loop is also broken if the signal closes.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<ValueType>) -> Bool) {
		var endpoint: SignalEndpoint<T>? = nil
		endpoint = subscribe(context: context) { r in
			withExtendedLifetime(endpoint) {}
			if !handler(r) || r.isError {
				endpoint?.cancel()
				endpoint = nil
			}
		}
	}
	
	/// A version of `subscribe` that creates a reference counted loop to the `SignalEndpoint`, keeping the signal graph alive. Unlike a typical `subscribe` handler (which returns `Void`), this handler returns a `Bool` – the the `Bool` is false, the reference counted loop is broken. The reference counted loop is also broken if the signal closes.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) {
		subscribeAndKeepAlive(context: context) { r in
			if case .success(let v) = r {
				return handler(v)
			} else {
				return false
			}
		}
	}
	
	/// Returns a signal that drops an `initial` number of values from the start of the stream and emits the next value and every `count`-th value after that.
	///
	/// - parameter count:       number of values beteen emissions
	/// - parameter initialSkip: number of values before the first emission
	///
	/// - returns: the strided signal
	public func stride(count: Int, initialSkip: Int = 0) -> Signal<T> {
		return transform(withState: count - initialSkip - 1) { (state: inout Int, r: Result<T>, n: SignalNext<T>) in
			switch r {
			case .success(let v) where state >= count - 1:
				n.send(value: v)
				state = 0
			case .success:
				state += 1
			case .failure(let e):
				n.send(error: e)
			}
		}
	}
	
	/// A signal transform function that, instead of sending values to a `SignalNext`, outputs entire signals to a `SignalMergeSet`. The output of the merge set is then the result from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - parameter context:         the context where the processor will run
	/// - parameter closesImmediate: whether signals added to the merge set will close the output
	/// - parameter processor:       performs work with values from this `Signal` and the `SignalMergeSet` used for output.
	///
	/// - returns: output of the merge set
	public func transformFlatten<U>(context: Exec = .direct, closesImmediate: Bool = false, _ processor: @escaping (T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		return transformFlatten(withState: (), closesImmediate: closesImmediate, context: context, { (state: inout (), value: T, mergeSet: SignalMergeSet<U>) in processor(value, mergeSet) })
	}
	
	/// A signal transform function that, instead of sending values to a `SignalNext`, outputs entire signals to a `SignalMergeSet`. The output of the merge set is then the result from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - parameter withState:       initial state for the state parameter passed into the processor
	/// - parameter context:         the context where the processor will run
	/// - parameter closesImmediate: whether signals added to the merge set will close the output
	/// - parameter processor:       performs work with values from this `Signal` and the `SignalMergeSet` used for output.
	///
	/// - returns: output of the merge set
	public func transformFlatten<S, U>(withState initialState: S, closesImmediate: Bool = false, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		let (mergeSet, result) = Signal<U>.createMergeSet()
		var closeError: Error? = nil
		let closeSignal = transform(withState: initialState, context: context) { (state: inout S, r: Result<T>, n: SignalNext<U>) in
			switch r {
			case .success(let v): processor(&state, v, mergeSet)
			case .failure(let e):
				closeError = e
				n.send(error: e)
			}
		}
		
		// Keep the merge set alive at least as long as self
		_ = try? mergeSet.add(closeSignal, closesOutput: closesImmediate)
		
		// On close, emit the error from self rather than the error from the merge set (which is usually `SignalError.cancelled` when `closesImmediate` is false.
		return result.transform(withState: nil) { (onDelete: inout OnDelete?, r: Result<U>, n: SignalNext<U>) in
			if onDelete == nil {
				onDelete = OnDelete {
					closeError = nil
				}
			}
			switch r {
			case .success(let v): n.send(value: v)
			case .failure(let e): n.send(error: closeError ?? e)
			}
		}
	}

	/// A utility function, used by ReactiveX implementations, that generates "window" durations in single signal from the values in self and a "duration" function that returns duration signals for each value.
	///
	/// - parameter context:  the context where `duration` will be invoked
	/// - parameter duration: for each value emitted by `self`, emit a signal
	///
	/// - returns: a signal of two element tuples
	public func valueDurations<U>(closesImmediate: Bool = false, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> Signal<(Int, T?)> {
		return valueDurations(withState: (), closesImmediate: closesImmediate, context: context, duration: { (state: inout (), value: T) -> Signal<U> in duration(value) })
	}

	/// A utility function, used by ReactiveX implementations, that generates "window" durations in single signal from the values in self and a "duration" function that returns duration signals for each value.
	///
	/// - parameter context:  the context where `duration` will be invoked
	/// - parameter duration: for each value emitted by `self`, emit a signal
	///
	/// - returns: a signal of two element tuples
	public func valueDurations<U, V>(withState initialState: V, closesImmediate: Bool = false, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> Signal<(Int, T?)> {
		return transformFlatten(withState: (index: 0, userState: initialState), closesImmediate: closesImmediate, context: context) { (state: inout (index: Int, userState: V), v: T, mergeSet: SignalMergeSet<(Int, T?)>) in
			let count = state.index
			let innerSignal = duration(&state.userState, v).transform { (innerResult: Result<U>, innerInput: SignalNext<(Int, T?)>) in
				if case .failure(let e) = innerResult {
					innerInput.send(value: (count, nil))
					innerInput.send(error: e)
				}
			}
			let prefixedInnerSignal = Signal<(Int, T?)>.preclosed(values: [(count, Optional(v))]).combine(second: innerSignal) { (r: EitherResult2<(Int, T?), (Int, T?)>, n: SignalNext<(Int, T?)>) in
				switch r {
				case .result1(.success(let v)): n.send(value: v)
				case .result1(.failure): break
				case .result2(.success(let v)): n.send(value: v)
				case .result2(.failure(let e)): n.send(error: e)
				}
			}

			_ = try? mergeSet.add(prefixedInnerSignal)
			state.index += 1
		}
	}
}

/// A `SignalMergeSet` exposes the ability to close the output signal and disconnect on deactivation. For public interfaces, neither of these is really appropriate to expose. A `SignalCollector` provides a simple wrapper around `SignalMergeSet` that forces `closesOutput` and `removeOnDeactivate` to be *false* for all inputs created through this interface.
/// A `SignalCollector` also hides details about the output from the input. Forcing `removeOnDeactivate` is one part of this but the other part is that `SignalCollector` does not `throw` from its `add` or `Signal.join` functions.
/// NOTE: it is possible to create the underlying `SignalMergeSet` and privately add inputs with other properties, if you wish.
public final class SignalCollector<T> {
	private let mergeSet: SignalMergeSet<T>
	public init(mergeSet: SignalMergeSet<T>) {
		self.mergeSet = mergeSet
	}
	
	public func add(_ source: Signal<T>) {
		_ = try? mergeSet.add(source)
	}
	
	public func remove(_ source: Signal<T>) {
		mergeSet.remove(source)
	}

	public func input() -> SignalInput<T> {
		return Signal<T>.create { s -> () in self.add(s) }.input
	}
}

extension Signal {
	public final func join(to: SignalCollector<T>) {
		to.add(self)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func createCollector() -> (collector: SignalCollector<T>, signal: Signal<T>) {
		let (ms, s) = Signal<T>.createMergeSet()
		return (SignalCollector(mergeSet: ms), s)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func createCollector<U>(compose: (Signal<T>) throws -> U) rethrows -> (collector: SignalCollector<T>, composed: U) {
		let (a, b) = try Signal<T>.createMergeSet(compose: compose)
		return (SignalCollector(mergeSet: a), b)
	}
}

/// This wrapper around `SignalEndpoint` exposes the last received value in a stream so that it can be 'polled' (read synchronously from an arbitrary execution context).
///
/// **WARNING**: this class should be avoided where possible since it removes the "reactive" part of reactive programming (changes in the polled value must be detected through other means, usually another subscriber to the underlying `Signal`).
///
/// The typical use-case for this type of class is in the implementation of delegate methods and similar callback functions that must synchronously return a value. Since you cannot simply `Signal.combine` the delegate method with another `Signal`, you must use polling to generate a calculation involving values from another `Signal`.
public final class SignalPollingEndpoint<T> {
	var endpoint: SignalEndpoint<T>? = nil
	var latest: Result<T>? = nil
	let queueContext = DispatchQueueContext()
	
	public init(signal: Signal<T>) {
		endpoint = signal.subscribe(context: .custom(queueContext)) { [weak self] r in
			self?.latest = r
		}
	}
	
	public var latestResult: Result<T>? {
		return queueContext.queue.sync { latest }
	}
	
	public var latestValue: T? {
		return queueContext.queue.sync { latest?.value }
	}
}

extension Signal {
	/// Appends a `SignalPollingEndpoint` listener to the value emitted from this `Signal`. The endpoint will "activate" this `Signal` and all direct antecedents in the graph (which may start lazy operations deferred until activation).
	public func pollingEndpoint() -> SignalPollingEndpoint<T> {
		return SignalPollingEndpoint(signal: self)
	}
}

extension SignalInput {
	/// Create a `SignalInput`-`Signal` pair, returning the `SignalInput` and handling the `Signal` internally using the `compose` closure. This is a syntactic convenience for functions that require a `SignalInput` parameter.
	public static func into(_ compose: (Signal<T>) throws -> Void) rethrows -> SignalInput<T> {
		return try Signal<T>.create { s in try compose(s) }.input
	}
	
	/// Creates a new `SignalInput`-`Signal` pair, appends a `map` transform to the `Signal` and then the transformed `Signal` is `join(to:)` self. The `SignalInput` from the pair is returned.
	public func viaMap<U>(_ map: @escaping (U) -> T) throws -> SignalInput<U> {
		return try .into { s in try s.map(map).join(to: self) }
	}
	
	/// Creates a new `SignalInput`-`Signal` pair, appends a `map` transform to the `Signal` and then the transformed `Signal` is `join(to:)` self. The `SignalInput` from the pair is returned.
	public func via<U>(_ compose: (Signal<U>) -> Signal<T>) throws -> SignalInput<U> {
		return try .into { s in try compose(s).join(to: self) }
	}
}

extension SignalCollector {
	/// Creates a new `SignalInput`-`Signal` pair, appends a `map` transform to the `Signal` and then the transformed `Signal` is `join(to:)` self. The `SignalInput` from the pair is returned.
	public func viaMap<U>(_ map: @escaping (U) -> T) -> SignalInput<U> {
		return .into { s in s.map(map).join(to: self) }
	}
	
	/// Creates a new `SignalInput`-`Signal` pair, appends a `map` transform to the `Signal` and then the transformed `Signal` is `join(to:)` self. The `SignalInput` from the pair is returned.
	public func via<U>(_ compose: (Signal<U>) -> Signal<T>) -> SignalInput<U> {
		return .into { s in compose(s).join(to: self) }
	}
}

extension SignalCapture {
	/// A convenience version of `subscribe` that only invokes the `processor` on `Result.success`
	///
	/// - Parameters:
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - context: the execution context where the `processor` will be invoked
	///   - processor: will be invoked with each value received
	/// - Returns: the `SignalEndpoint` created by this function
	public func subscribeValues(resend: Bool = false, context: Exec = .direct, handler: @escaping (T) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(to: input, resend: resend)
		return output.subscribeValues(context: context, handler: handler)
	}
	
	/// A convenience version of `subscribe` that only invokes the `processor` on `Result.success`
	///
	/// - Parameters:
	///   - resend: if true, captured values are sent to the new output as the first values in the stream, otherwise, captured values are not sent (default is false)
	///   - onError: if nil, errors from self will be passed through to `toInput`'s `Signal` normally. If non-nil, errors will not be sent, instead, the `Signal` will be disconnected and the `onError` function will be invoked with the disconnected `SignalCapture` and the input created by calling `disconnect` on it.
	///   - context: the execution context where the `processor` will be invoked
	///   - processor: will be invoked with each value received
	/// - Returns: the `SignalEndpoint` created by this function
	public func subscribeValues(resend: Bool = false, onError: @escaping (SignalCapture<T>, Error, SignalInput<T>) -> (), context: Exec = .direct, handler: @escaping (T) -> Void) -> SignalEndpoint<T> {
		let (input, output) = Signal<T>.create()
		try! join(to: input, resend: resend, onError: onError)
		return output.subscribeValues(context: context, handler: handler)
	}
}

extension Result {
	public var isSignalClosed: Bool {
		if case .failure(SignalError.closed) = self {
			return true
		} else {
			return false
		}
	}
}
