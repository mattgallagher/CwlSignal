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

#if SWIFT_PACKAGE
	import Foundation
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
	
	/// A convenience version of `send` that wraps a value in `Result.success` before sending
	///
	/// - Parameter value: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send(values: ValueType...) -> SignalError? {
		for v in values {
			if let e = send(result: .success(v)) {
				return e
			}
		}
		return nil
	}
	
	/// A convenience version of `send` that wraps a value in `Result.success` before sending
	///
	/// - Parameter value: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send<S: Sequence>(sequence: S) -> SignalError? where S.Iterator.Element == ValueType {
		for v in sequence {
			if let e = send(result: .success(v)) {
				return e
			}
		}
		return nil
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
	// Like `create` but also provides a trailing closure to transform the `Signal` normally returned from `create` and in its place, return the result of the transformation.
	//
	// - Parameter compose: a trailing closure which receices the `Signal` as a parameter and any result is returned as the second tuple parameter from this function
	// - Returns: a (`SignalInput`, U) tuple where `SignalInput` is the input to the signal graph and `U` is the return value from the `compose` function.
	// - Throws: rethrows any error from the closure
	public static func create<U>(compose: (Signal<T>) throws -> U) rethrows -> (input: SignalInput<T>, composed: U) {
		let (i, s) = Signal<T>.create()
		return (i, try compose(s))
	}
	
	/// A version of `generate` that retains the latest `input` so it doesn't automatically close the signal when the input falls out of scope. This enables a generator that never closes (lives until deactivation).
	///
	/// - Parameters:
	///   - context: the `activationChange` will be invoked in this context
	///   - activationChange: receives inputs on activation and nil on each deactivation
	/// - Returns: the constructed `Signal`
	public static func retainedGenerate(context: Exec = .direct, activationChange: @escaping (SignalInput<T>?) -> Void) -> Signal<T> {
		var latestInput: SignalInput<T>? = nil
		return .generate(context: context) { input in
			latestInput = input
			withExtendedLifetime(latestInput) {}
			activationChange(input)
		}
	}

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
	
	/// A convenience version of `subscribeAndKeepAlive` that only invokes the `processor` on `Result.success`
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
	/// - Parameters:
	///   - count: number of values beteen emissions
	///   - initialSkip: number of values before the first emission
	/// - Returns: the strided signal
	public func stride(count: Int, initialSkip: Int = 0) -> Signal<T> {
		return transform(initialState: count - initialSkip - 1) { (state: inout Int, r: Result<T>, n: SignalNext<T>) in
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
	
	/// A signal transform function that, instead of creating plain values and emitting them to a `SignalNext`, creates entire signals and adds them to a `SignalMergedInput`. The output of the merge set (which contains the merged output from all of the created signals) forms the signal returned from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - Parameters:
	///   - closePropagation: whether signals added to the merge set will close the output
	///   - context: the context where the processor will run
	///   - processor: performs work with values from this `Signal` and the `SignalMergedInput` used for output
	/// - Returns: output of the merge set
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergedInput<U>) -> ()) -> Signal<U> {
		return transformFlatten(initialState: (), closePropagation: closePropagation, context: context, { (state: inout (), value: T, mergedInput: SignalMergedInput<U>) in processor(value, mergedInput) })
	}
	
	/// A signal transform function that, instead of creating plain values and emitting them to a `SignalNext`, creates entire signals and adds them to a `SignalMergedInput`. The output of the merge set (which contains the merged output from all of the created signals) forms the signal returned from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - Parameters:
	///   - initialState: initial state for the state parameter passed into the processor
	///   - closePropagation: whether signals added to the merge set will close the output
	///   - context: the context where the processor will run
	///   - processor: performs work with values from this `Signal` and the `SignalMergedInput` used for output
	/// - Returns: output of the merge set
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergedInput<U>) -> ()) -> Signal<U> {
		let (mergedInput, result) = Signal<U>.createMergedInput()
		var closeError: Error? = nil
		let outerSignal = transform(initialState: initialState, context: context) { (state: inout S, r: Result<T>, n: SignalNext<U>) in
			switch r {
			case .success(let v): processor(&state, v, mergedInput)
			case .failure(let e):
				closeError = e
				n.send(error: e)
			}
		}
		
		// Keep the merge set alive at least as long as self
		mergedInput.add(outerSignal, closePropagation: closePropagation)
		
		return result.transform(initialState: nil) { [weak mergedInput] (onDelete: inout OnDelete?, r: Result<U>, n: SignalNext<U>) in
			if onDelete == nil {
				onDelete = OnDelete {
					closeError = nil
				}
			}
			switch r {
			case .success(let v): n.send(value: v)
			case .failure(SignalError.cancelled):
				// If the `mergedInput` is `nil` at this point, that means that this `.cancelled` comes from the `mergedInput`, not one of its inputs. We'd prefer in that case to emit the `outerSignal`'s `closeError` rather than follow the `shouldPropagateError` logic.
				n.send(error: mergedInput == nil ? (closeError ?? SignalError.cancelled) : SignalError.cancelled)
			case .failure(let e):
				n.send(error: closePropagation.shouldPropagateError(e) ? e : (closeError ?? SignalError.cancelled))
			}
		}
	}

	/// A utility function, used by ReactiveX implementations, that generates "window" durations in single signal from the values in self and a "duration" function that returns duration signals for each value.
	///
	/// - Parameters:
	///   - closePropagation: passed through to the underlying `transformFlatten` call (unlikely to make much different in expected use cases of this function)
	///   - context: the context where `duration` will be invoked
	///   - duration: for each value emitted by `self`, emit a signal
	/// - Returns: a signal of two element tuples
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> Signal<(Int, T?)> {
		return valueDurations(initialState: (), closePropagation: closePropagation, context: context, duration: { (state: inout (), value: T) -> Signal<U> in duration(value) })
	}

	/// A utility function, used by ReactiveX implementations, that generates "window" durations in single signal from the values in self and a "duration" function that returns duration signals for each value.
	///
	/// - Parameters:
	///   - initialState: initial state for the state parameter passed into the processor
	///   - closePropagation: passed through to the underlying `transformFlatten` call (unlikely to make much different in expected use cases of this function)
	///   - context: the context where `duration` will be invoked
	///   - duration: for each value emitted by `self`, emit a signal
	/// - Returns: a signal of two element tuples
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> Signal<(Int, T?)> {
		return transformFlatten(initialState: (index: 0, userState: initialState), closePropagation: closePropagation, context: context) { (state: inout (index: Int, userState: V), v: T, mergedInput: SignalMergedInput<(Int, T?)>) in
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

			mergedInput.add(prefixedInnerSignal)
			state.index += 1
		}
	}
	
	/// A continuous signal which alternates between true and false values each time it receives a value.
	///
	/// - Parameter initialState: before receiving the first value
	/// - Returns: the alternating, continuous signal
	public func toggle(initialState: Bool = false) -> Signal<Bool> {
		return transform(initialState: initialState) { (state: inout Bool, toggle: Result<ValueType>, next: SignalNext<Bool>) in
			switch toggle {
			case .success:
				state = !state
				next.send(value: state)
			case .failure(let e):
				next.send(error: e)
			}
		}
	}
}

extension Signal {
	/// Joins this `Signal` to a destination `SignalInput`
	///
	/// WARNING: if you join to a previously joined or otherwise inactive instance of the base `SignalInput` class, this function will have no effect. To get underlying errors, use `junction().join(to: input)` instead.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	public final func join(to input: SignalInput<T>) {
		if let multiInput = input as? SignalMultiInput<T> {
			multiInput.add(self)
		} else {
			_ = try? junction().join(to: input)
		}
	}
	
	/// Joins this `Signal` to a destination `SignalMergedInput`
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	public final func join(to input: SignalMergedInput<T>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = true) {
		input.add(self, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	/// Joins this `Signal` to a destination `SignalMultiInput` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMultiInput` again.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	/// - Returns: a `Cancellable` that will undo the join if cancelled or released
	public final func cancellableJoin(to input: SignalInput<T>) -> Cancellable {
		if let multiInput = input as? SignalMultiInput<T> {
			multiInput.add(self)
			return OnDelete { [weak multiInput, weak self] in
				guard let mi = multiInput, let s = self else { return }
				mi.remove(s)
			}
		} else {
			let j = junction()
			_ = try? j.join(to: input)
			return j
		}
	}
	
	/// Joins this `Signal` to a destination `SignalMultiInput` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMultiInput` again.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	/// - Returns: a `Cancellable` that will undo the join if cancelled or released
	public final func cancellableJoin(to input: SignalMergedInput<T>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = true) -> Cancellable {
		input.add(self, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return OnDelete { [weak input, weak self] in
			guard let i = input, let s = self else { return }
			i.remove(s)
		}
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
	
	/// Internally creates a polling endpoint which is polled once for the latest Result<T> and then discarded.
	public var poll: T? {
		return SignalPollingEndpoint(signal: self).latestValue
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
		// This can't be `loop` but `duplicate` is a precondition failure
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
		// This can't be `loop` but `duplicate` is a precondition failure
		try! join(to: input, resend: resend, onError: onError)
		return output.subscribeValues(context: context, handler: handler)
	}
}

extension Result {
	/// A convenience extension on `Result` to test if it wraps a `SignalError.closed`
	public var isSignalClosed: Bool {
		return error as? SignalError == .closed
	}
}
