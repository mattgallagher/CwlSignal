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
	
	/// Similar to `create` but uses a `SignalMergeSet` as the input to the signal pipeline instead of a `SignalInput`. A `SignalMergeSet` can accept multiple, changing inputs with different "on-error/on-close" behaviors.
	///
	/// - Parameters:
	///   - initialInputs: any initial signals to be used as inputs to the `SignalMergeSet`.
	///   - closePropagation: close and error propagation behavior to be used for each of `initialInputs`
	///   - removeOnDeactivate: deactivate behavior to be used for each of `initialInputs`
	/// - Returns: the (mergeSet, signal)
	public static func createMergeSet<S: Sequence>(_ initialInputs: S, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> (mergeSet: SignalMergeSet<T>, signal: Signal<T>) where S.Iterator.Element: Signal<T> {
		let (mergeSet, signal) = Signal<T>.createMergeSet()
		for i in initialInputs {
			try! mergeSet.add(i, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		}
		return (mergeSet, signal)
	}
	
	/// Similar to `create` but uses a `SignalMergeSet` as the input to the signal pipeline instead of a `SignalInput`. A `SignalMergeSet` can accept multiple, changing inputs with different "on-error/on-close" behaviors.
	///
	/// - Parameters:
	///   - initialInputs: any initial signals to be used as inputs to the `SignalMergeSet`.
	///   - closePropagation: close and error propagation behavior to be used for each of `initialInputs`
	///   - removeOnDeactivate: deactivate behavior to be used for each of `initialInputs`
	///   - compose: a trailing closure which receices the `Signal` as a parameter and any result is returned as the second tuple parameter from this function
	/// - Returns: a (`SignalMergeSet`, U) tuple where `SignalMergeSet` is the input to the signal graph and `U` is the return value from the `compose` function.
	/// - Throws: rethrows any error from the closure
	public static func createMergeSet<S: Sequence, U>(_ initialInputs: S, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false, compose: (Signal<T>) throws -> U) rethrows -> (mergeSet: SignalMergeSet<T>, composed: U) where S.Iterator.Element: Signal<T> {
		let (mergeSet, signal) = try Signal<T>.createMergeSet(compose: compose)
		for i in initialInputs {
			try! mergeSet.add(i, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		}
		return (mergeSet, signal)
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
	
	/// A signal transform function that, instead of creating plain values and emitting them to a `SignalNext`, creates entire signals and adds them to a `SignalMergeSet`. The output of the merge set (which contains the merged output from all of the created signals) forms the signal returned from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - Parameters:
	///   - closePropagation: whether signals added to the merge set will close the output
	///   - context: the context where the processor will run
	///   - processor: performs work with values from this `Signal` and the `SignalMergeSet` used for output
	/// - Returns: output of the merge set
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		return transformFlatten(initialState: (), closePropagation: closePropagation, context: context, { (state: inout (), value: T, mergeSet: SignalMergeSet<U>) in processor(value, mergeSet) })
	}
	
	/// A signal transform function that, instead of creating plain values and emitting them to a `SignalNext`, creates entire signals and adds them to a `SignalMergeSet`. The output of the merge set (which contains the merged output from all of the created signals) forms the signal returned from this function.
	///
	/// NOTE: this function is primarily used for implementing various Reactive X operators.
	///
	/// - Parameters:
	///   - initialState: initial state for the state parameter passed into the processor
	///   - closePropagation: whether signals added to the merge set will close the output
	///   - context: the context where the processor will run
	///   - processor: performs work with values from this `Signal` and the `SignalMergeSet` used for output
	/// - Returns: output of the merge set
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		let (mergeSet, result) = Signal<U>.createMergeSet()
		var closeError: Error? = nil
		let outerSignal = transform(initialState: initialState, context: context) { (state: inout S, r: Result<T>, n: SignalNext<U>) in
			switch r {
			case .success(let v): processor(&state, v, mergeSet)
			case .failure(let e):
				closeError = e
				n.send(error: e)
			}
		}
		
		// Keep the merge set alive at least as long as self
		_ = try? mergeSet.add(outerSignal, closePropagation: closePropagation)
		
		return result.transform(initialState: nil) { [weak mergeSet] (onDelete: inout OnDelete?, r: Result<U>, n: SignalNext<U>) in
			if onDelete == nil {
				onDelete = OnDelete {
					closeError = nil
				}
			}
			switch r {
			case .success(let v): n.send(value: v)
			case .failure(SignalError.cancelled):
				// If the `mergeSet` is `nil` at this point, that means that this `.cancelled` comes from the `mergeSet`, not one of its inputs. We'd prefer in that case to emit the `outerSignal`'s `closeError` rather than follow the `shouldPropagateError` logic.
				n.send(error: mergeSet == nil ? (closeError ?? SignalError.cancelled) : SignalError.cancelled)
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
		return transformFlatten(initialState: (index: 0, userState: initialState), closePropagation: closePropagation, context: context) { (state: inout (index: Int, userState: V), v: T, mergeSet: SignalMergeSet<(Int, T?)>) in
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

/// A `SignalMergeSet` exposes the ability to close the output signal and disconnect on deactivation. For public interfaces, neither of these is really appropriate to expose. A `SignalMultiInput` provides a simple wrapper around `SignalMergeSet` that forces `closesOutput` and `removeOnDeactivate` to be *false* for all inputs created through this interface.
/// A `SignalMultiInput` also hides details about the output from the input. Forcing `removeOnDeactivate` is one part of this but the other part is that `SignalMultiInput` does not `throw` from its `add` or `Signal.join` functions.
/// NOTE: it is possible to create the underlying `SignalMergeSet` and privately add inputs with other properties, if you wish.
public final class SignalMultiInput<T>: SignalSender {
	public typealias ValueType = T

	private let mergeSet: SignalMergeSet<T>
	public init(mergeSet: SignalMergeSet<T>) {
		self.mergeSet = mergeSet
	}
	
	/// Calls `add` on the underlying mergeSet with default parameters (closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false)
	///
	/// NOTE: any possible error thrown by the underlying `SignalMergeSet.add` will be consumed and hidden (it's not `SignalMultiInput`s responsibility to communicate information about the output).
	///
	/// - Parameter source: added to the underlying merge set
	public func add(_ source: Signal<T>) {
		_ = try? mergeSet.add(source)
	}
	
	/// Calls `remove` on the underlying mergeSet
	///
	/// - Parameter source: removed from the underlying merge set
	public func remove(_ source: Signal<T>) {
		mergeSet.remove(source)
	}

	/// Creates a new `SignalInput`/`Signal` pair, immediately adds the `Signal` to this `SignalMergeSet` and returns the `SignalInput`.
	/// Equivalent to `input()` on `SignalMergeSet` with default parameters
	///
	/// - Returns: a new `SignalInput` that feeds into the collector
	public func newInput() -> SignalInput<T> {
		let (i, s) = Signal<T>.create()
		self.add(s)
		return i
	}

	/// The primary signal sending function
	///
	/// NOTE: on `SignalMultiInput` this is a low performance convenience method; it calls `newInput()` on each send. If you plan to send multiple results, it is more efficient to call `newInput()`, retain the `SignalInput` that creates and call `SignalInput` on that single input.
	///
	/// - Parameter result: the value or error to send, composed as a `Result`
	/// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult public func send(result: Result<ValueType>) -> SignalError? {
		return newInput().send(result: result)
	}
}

extension Signal {
	/// Joins this `Signal` to a destination `SignalMergeSet`
	///
	/// - Parameters:
	///   - to: the destination
	///   - closesOutput: whether errors from this `Signal` should be passed through to the `SignalMergeSet` output.
	///   - removeOnDeactivate: whether deactivate should disconnect this `Signal` from the `SignalMergeSet`.
	/// - Throws: a `SignalJoinError` if the connection is not made (see that type for details)
	public final func join(to: SignalMergeSet<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) throws {
		try to.add(self, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	/// Joins this `Signal` to a destination `SignalMergeSet` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMergeSet` again.
	///
	/// - Parameters:
	///   - to: target `SignalMergeSet` to which this signal will be added
	///   - closePropagation: used as a parameter to `SignalMergeSet.add`
	///   - removeOnDeactivate: used as a parameter to `SignalMergeSet.add`
	/// - Returns: a `Cancellable` that will undo the join if cancelled or released
	/// - Throws: may throw any `SignalJoinError` from `SignalMergeSet.add` (see that type for possible cases)
	public final func cancellableJoin(to: SignalMergeSet<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) throws -> Cancellable {
		try to.add(self, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return OnDelete { [weak to, weak self] in
			guard let t = to, let s = self else { return }
			t.remove(s)
		}
	}

	/// Joins this `Signal` to a destination `SignalMultiInput`
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	public final func join(to: SignalMultiInput<T>) {
		to.add(self)
	}
	
	/// Joins this `Signal` to a destination `SignalMultiInput` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMultiInput` again.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	/// - Returns: a `Cancellable` that will undo the join if cancelled or released
	public final func cancellableJoin(to: SignalMultiInput<T>) -> Cancellable {
		to.add(self)
		return OnDelete { [weak to, weak self] in
			guard let t = to, let s = self else { return }
			t.remove(s)
		}
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func createMultiInput() -> (collector: SignalMultiInput<T>, signal: Signal<T>) {
		let (ms, s) = Signal<T>.createMergeSet()
		return (SignalMultiInput(mergeSet: ms), s)
	}
	
	/// Create a manual input/output pair where values sent to the `input` are passed through the `signal` output.
	///
	/// - returns: the `SignalInput` and `Signal` pair
	public static func createMultiInput<U>(compose: (Signal<T>) throws -> U) rethrows -> (collector: SignalMultiInput<T>, composed: U) {
		let (a, b) = try Signal<T>.createMergeSet(compose: compose)
		return (SignalMultiInput(mergeSet: a), b)
	}
}

/// This wrapper around `SignalEndpoint` exposes the last received value in a stream so that it can be 'polled' (read synchronously from an arbitrary execution context).
///
/// **WARNING**: this class should be avoided where possible since it removes the "reactive" part of reactive programming (changes in the polled value must be detected through other means, usually another subscriber to the underlying `Signal`).
///
/// The typical use-case for this type of class is in the implementation of delegate methods and similar callback functions that must synchronously return a value. Since you cannot simply `Signal.combine` the delegate method with another `Signal`, you must use polling to generate a calculation involving values from another `Signal`.
public final class SignalPollableEndpoint<T> {
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
	/// Appends a `SignalPollableEndpoint` listener to the value emitted from this `Signal`. The endpoint will "activate" this `Signal` and all direct antecedents in the graph (which may start lazy operations deferred until activation).
	public func pollingEndpoint() -> SignalPollableEndpoint<T> {
		return SignalPollableEndpoint(signal: self)
	}
	
	/// Internally creates a polling endpoint which is polled once for the latest Result<T> and then discarded.
	public var poll: Result<T>? {
		return SignalPollableEndpoint(signal: self).latestResult
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
	/// A convenience extension on `Result` to test if it wraps a `SignalError.closed`
	public var isSignalClosed: Bool {
		return error as? SignalError == .closed
	}
}
