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

/// This protocol allows transformations that apply to `Signal` types to be applied to a type that exposes a signal.
public protocol SignalInterface {
	associatedtype OutputValue
	var signal: Signal<OutputValue> { get }
}

/// This protocol allows transformations that apply to `Signal` types to be applied to a type that exposes a signal.
public protocol SignalInputInterface {
	associatedtype InputValue
	var input: SignalInput<InputValue> { get }
}

/// Used to provide a light abstraction over the `SignalInput` and `SignalNext` types.
/// In general, the only real purpose of this protocol is to enable the `send(value:)`, `send(error:)`, `close()` extensions in "SignalExternsions.swift"
public protocol SignalSender {
	associatedtype InputValue
	
	/// The primary signal sending function
	///
	/// - Parameter result: the value or error to send, composed as a `Result`
	/// - Returns: `nil` on success. Non-`nil` values include `SignalError.cancelled` if the `predecessor` or `activationCount` fail to match, `SignalError.inactive` if the current `delivery` state is `.disabled`.
	@discardableResult func send(result: Result<InputValue>) -> SignalError?
}

extension Signal: SignalInterface {
	public var signal: Signal<OutputValue> { return self }
}

extension SignalInput: SignalInputInterface, SignalSender {
	public var input: SignalInput<InputValue> { return self }
}

extension SignalNext: SignalSender {}

// All transformations on a Signal are built on top of the following functions, implemented in CwlSignal.swift
extension SignalInterface {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Void) -> SignalEndpoint<OutputValue> {
		return signal.subscribe(context: context, handler: handler)
	}
	public func subscribeWhile(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Bool) {
		return signal.subscribeWhile(context: context, handler: handler)
	}
	public func junction() -> SignalJunction<OutputValue> {
		return signal.junction()
	}
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<OutputValue>, SignalNext<U>) -> Void) -> Signal<U> {
		return signal.transform(context: context, handler: handler)
	}
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<OutputValue>, SignalNext<U>) -> Void) -> Signal<U> {
		return signal.transform(initialState: initialState, context: context, handler: handler)
	}
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return signal.combine(second: second, context: context, handler: handler)
	}
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return signal.combine(second: second, third: third, context: context, handler: handler)
	}
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return signal.combine(second: second, third: third, fourth: fourth, context: context, handler: handler)
	}
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return signal.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler)
	}
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> Signal<V> {
		return signal.combine(initialState: initialState, second: second, context: context, handler: handler)
	}
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> Signal<W> {
		return signal.combine(initialState: initialState, second: second, third: third, context: context, handler: handler)
	}
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> Signal<X> {
		return signal.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler)
	}
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> Signal<Y> {
		return signal.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler)
	}
	public func continuous(initialValue: OutputValue) -> SignalMulti<OutputValue> {
		return signal.continuous(initialValue: initialValue)
	}
	public func continuous() -> SignalMulti<OutputValue> {
		return signal.continuous()
	}
	public func continuousWhileActive() -> SignalMulti<OutputValue> {
		return signal.continuousWhileActive()
	}
	public func playback() -> SignalMulti<OutputValue> {
		return signal.playback()
	}
	public func cacheUntilActive() -> Signal<OutputValue> {
		return signal.cacheUntilActive()
	}
	public func multicast() -> SignalMulti<OutputValue> {
		return signal.multicast()
	}
	public func customActivation(initialValues: Array<OutputValue> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<OutputValue>, _ cachedError: inout Error?, _ incoming: Result<OutputValue>) -> Void) -> SignalMulti<OutputValue> {
		return signal.customActivation(initialValues: initialValues, context: context, updater: updater)
	}
	public func reduce<State>(initialState: State, context: Exec = .direct, reducer: @escaping (_ state: inout State, _ message: OutputValue) throws -> State) -> SignalMulti<State> {
		return signal.reduce(initialState: initialState, context: context, reducer: reducer)
	}
	public func capture() -> SignalCapture<OutputValue> {
		return signal.capture()
	}
}

extension Signal {
	// Like `create` but also provides a trailing closure to transform the `Signal` normally returned from `create` and in its place, return the result of the transformation.
	//
	// - Parameter compose: a trailing closure which receices the `Signal` as a parameter and any result is returned as the second tuple parameter from this function
	// - Returns: a (`SignalInput`, U) tuple where `SignalInput` is the input to the signal graph and `U` is the return value from the `compose` function.
	// - Throws: rethrows any error from the closure
	public static func create<U>(compose: (Signal<OutputValue>) throws -> U) rethrows -> (input: SignalInput<OutputValue>, composed: U) {
		let (i, s) = Signal<OutputValue>.create()
		return (i, try compose(s))
	}
	
	/// A version of `generate` that retains the latest `input` so it doesn't automatically close the signal when the input falls out of scope. This enables a generator that never closes (lives until deactivation).
	///
	/// - Parameters:
	///   - context: the `activationChange` will be invoked in this context
	///   - activationChange: receives inputs on activation and nil on each deactivation
	/// - Returns: the constructed `Signal`
	public static func retainedGenerate(context: Exec = .direct, activationChange: @escaping (SignalInput<OutputValue>?) -> Void) -> Signal<OutputValue> {
		var latestInput: SignalInput<OutputValue>? = nil
		return .generate(context: context) { input in
			latestInput = input
			withExtendedLifetime(latestInput) {}
			activationChange(input)
		}
	}
	
}

extension SignalSender {
	/// A convenience version of `send` that wraps a value in `Result.success` before sending
	///
	/// - Parameter value: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send(value: InputValue) -> SignalError? {
		return send(result: .success(value))
	}
	
	/// A convenience version of `send` that wraps a value in `Result.success` before sending
	///
	/// - Parameter value: will be wrapped and sent
	/// - Returns: the return value from the underlying `send(result:)` function
	@discardableResult
	public func send(values: InputValue...) -> SignalError? {
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
	public func send<S: Sequence>(sequence: S) -> SignalError? where S.Iterator.Element == InputValue {
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

extension SignalInterface {
	/// Removes any activation from the signal. Useful in cases when you only want *changes*, not the latest value.
	public func dropActivation() -> Signal<OutputValue> {
		let pair = Signal<OutputValue>.create()
		try! signal.capture().bind(to: pair.input)
		return pair.signal
	}
	
	/// Causes any activation to be deferred past activation time to the "normal" phase. This avoids the synchronous send rules normally used for activation signals an allows this initial signal to be asynchronously delivered.
	public func deferActivation() -> Signal<OutputValue> {
		let pair = Signal<OutputValue>.create()
		try! signal.capture().bind(to: pair.input, resend: true)
		return pair.signal
	}
	
	public func transformValues<U>(context: Exec = .direct, handler: @escaping (OutputValue, SignalNext<U>) -> Void) -> Signal<U> {
		return signal.transform(context: context) { (result: Result<OutputValue>, next: SignalNext<U>) in
			switch result {
			case .success(let v): handler(v, next)
			case .failure(let e): next.send(error: e)
			}
		}
	}

	public func transformValues<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, OutputValue, SignalNext<U>) -> Void) -> Signal<U> {
		return signal.transform(initialState: initialState, context: context) { (state: inout S, result: Result<OutputValue>, next: SignalNext<U>) in
			switch result {
			case .success(let v): handler(&state, v, next)
			case .failure(let e): next.send(error: e)
			}
		}
	}

	/// A version of `subscribe` that retains the `SignalEndpoint` internally, keeping the signal graph alive. The `SignalEndpoint` is cancelled and released when the signal closes.
	///
	/// NOTE: this subscriber deliberately creates a reference counted loop. If the signal is never closed, it will result in a memory leak. This function should be used only when `self` is guaranteed to close.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public func subscribeUntilEnd(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Void) {
        return signal.subscribeWhile(context: context, handler: { (result: Result<OutputValue>) -> Bool in
			handler(result)
			return true
		})
	}
	
	/// A convenience version of `subscribe` that only invokes the `processor` on `Result.success`
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received
	/// - Returns: the `SignalEndpoint` created by this function
	public func subscribeValues(context: Exec = .direct, handler: @escaping (OutputValue) -> Void) -> SignalEndpoint<OutputValue> {
		return signal.subscribe(context: context) { r in
			if case .success(let v) = r {
				handler(v)
			}
		}
	}
	
	/// A convenience version of `subscribeUntilEnd` that only invokes the `processor` on `Result.success`
	///
	/// NOTE: this subscriber deliberately creates a reference counted loop. If the signal is never closed, it will result in a memory leak. This function should be used only when `self` is guaranteed to close.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public func subscribeValuesUntilEnd(context: Exec = .direct, handler: @escaping (OutputValue) -> Void) {
		signal.subscribeUntilEnd(context: context) { r in
			if case .success(let v) = r {
				handler(v)
			}
		}
	}
	
	/// A convenience version of `subscribeWhile` that only invokes the `processor` on `Result.success`
	///
	/// NOTE: this subscriber deliberately creates a reference counted loop. If the signal is never closed and the handler never returns false, it will result in a memory leak. This function should be used only when `self` is guaranteed to close or the handler `false` condition is guaranteed.
	///
	/// - Parameters:
	///   - context: the execution context where the `processor` will be invoked
	///   - handler: will be invoked with each value received and if returns `false`, the endpoint will be cancelled and released
	public func subscribeValuesWhile(context: Exec = .direct, handler: @escaping (OutputValue) -> Bool) {
		signal.subscribeWhile(context: context) { r in
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
	public func stride(count: Int, initialSkip: Int = 0) -> Signal<OutputValue> {
		return signal.transform(initialState: count - initialSkip - 1) { (state: inout Int, r: Result<OutputValue>, n: SignalNext<OutputValue>) in
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
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (OutputValue, SignalMergedInput<U>) -> ()) -> Signal<U> {
		return transformFlatten(initialState: (), closePropagation: closePropagation, context: context, { (state: inout (), value: OutputValue, mergedInput: SignalMergedInput<U>) in processor(value, mergedInput) })
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
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .errors, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue, SignalMergedInput<U>) -> ()) -> Signal<U> {
		let (mergedInput, result) = Signal<U>.createMergedInput()
		var closeError: Error? = nil
		let outerSignal = signal.transform(initialState: initialState, context: context) { (state: inout S, r: Result<OutputValue>, n: SignalNext<U>) in
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
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (OutputValue) -> Signal<U>) -> Signal<(Int, OutputValue?)> {
		return valueDurations(initialState: (), closePropagation: closePropagation, context: context, duration: { (state: inout (), value: OutputValue) -> Signal<U> in duration(value) })
	}

	/// A utility function, used by ReactiveX implementations, that generates "window" durations in single signal from the values in self and a "duration" function that returns duration signals for each value.
	///
	/// - Parameters:
	///   - initialState: initial state for the state parameter passed into the processor
	///   - closePropagation: passed through to the underlying `transformFlatten` call (unlikely to make much different in expected use cases of this function)
	///   - context: the context where `duration` will be invoked
	///   - duration: for each value emitted by `self`, emit a signal
	/// - Returns: a signal of two element tuples
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, OutputValue) -> Signal<U>) -> Signal<(Int, OutputValue?)> {
		return transformFlatten(initialState: (index: 0, userState: initialState), closePropagation: closePropagation, context: context) { (state: inout (index: Int, userState: V), v: OutputValue, mergedInput: SignalMergedInput<(Int, OutputValue?)>) in
			let count = state.index
			let innerSignal = duration(&state.userState, v).transform { (innerResult: Result<U>, innerInput: SignalNext<(Int, OutputValue?)>) in
				if case .failure(let e) = innerResult {
					innerInput.send(value: (count, nil))
					innerInput.send(error: e)
				}
			}
			let prefixedInnerSignal = Signal<(Int, OutputValue?)>.preclosed(values: [(count, Optional(v))]).combine(second: innerSignal) { (r: EitherResult2<(Int, OutputValue?), (Int, OutputValue?)>, n: SignalNext<(Int, OutputValue?)>) in
				switch r {
				case .result1(.success(let v)): n.send(value: v)
				case .result1(.failure): break
				case .result2(.success(let v)): n.send(value: v)
				case .result2(.failure(let e)): n.send(error: e)
				}
			}

			mergedInput.add(prefixedInnerSignal, closePropagation: .none)
			state.index += 1
		}
	}
	
	/// A continuous signal which alternates between true and false values each time it receives a value.
	///
	/// - Parameter initialState: before receiving the first value
	/// - Returns: the alternating, continuous signal
	public func toggle(initialState: Bool = false) -> Signal<Bool> {
		return signal.transform(initialState: initialState) { (state: inout Bool, toggle: Result<OutputValue>, next: SignalNext<Bool>) in
			switch toggle {
			case .success:
				state = !state
				next.send(value: state)
			case .failure(let e):
				next.send(error: e)
			}
		}
	}

	/// Joins this `Signal` to a destination `SignalInput`
	///
	/// WARNING: if you bind to a previously joined or otherwise inactive instance of the base `SignalInput` class, this function will have no effect. To get underlying errors, use `junction().bind(to: input)` instead.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	public func bind<InputInterface>(to interface: InputInterface) where InputInterface: SignalInputInterface, InputInterface.InputValue == OutputValue {
		let input = interface.input
		if let multiInput = input as? SignalMultiInput<OutputValue> {
			multiInput.add(signal)
		} else {
			_ = try? signal.junction().bind(to: input)
		}
	}
	
	/// Joins this `Signal` to a destination `SignalMergedInput`
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	public func bind(to input: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = true) {
		input.add(signal, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	/// Joins this `Signal` to a destination `SignalMultiInput` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMultiInput` again.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	/// - Returns: a `Cancellable` that will undo the bind if cancelled or released
	public func cancellableJoin<InputInterface>(to interface: InputInterface) -> Cancellable where InputInterface: SignalInputInterface, InputInterface.InputValue == OutputValue {
		let input = interface.input
		if let multiInput = input as? SignalMultiInput<OutputValue> {
			multiInput.add(signal)
			return OnDelete { [weak multiInput, weak signal] in
				guard let mi = multiInput, let s = signal else { return }
				mi.remove(s)
			}
		} else {
			let j = signal.junction()
			_ = try? j.bind(to: input)
			return j
		}
	}
	
	/// Joins this `Signal` to a destination `SignalMultiInput` and returns a `Cancellable` that, when cancelled, will remove the `Signal` from the `SignalMultiInput` again.
	///
	/// - Parameters:
	///   - to: target `SignalMultiInput` to which this signal will be added
	/// - Returns: a `Cancellable` that will undo the bind if cancelled or released
	public func cancellableJoin(to input: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation, removeOnDeactivate: Bool = true) -> Cancellable {
		input.add(signal, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return OnDelete { [weak input, weak signal] in
			guard let i = input, let s = signal else { return }
			i.remove(s)
		}
	}
}

/// This wrapper around `SignalEndpoint` saves the last received value from the signal so that it can be 'polled' (read synchronously from an arbitrary execution context). This class ensures thread-safety on the read operation.
///
/// The typical use-case for this type of class is in the implementation of delegate methods and similar callback functions that must synchronously return a value. Holding a `SignalPollingEndpoint` set to run in the same context as the delegate (e.g. .main) will allow the delegate to synchronously respond with the latest value.
///
/// Note that there is a semantic difference between this class which is intended to be left active for some time and polled periodically and `SignalCapture` which captures the *activation* value (leaving it running for a duration is pointless). For that reason, the standalone `poll()` function actually uses `SignalCapture` rather than this class (`SignalCapture` is more consistent in the presence of multi-threaded updates since there is no possibility of asychronous updates between creation and reading).
///
/// However, `SignalCapture` can only read activation values (not regular values). Additionally, `poll()` will be less efficient than this class if multiple reads are required since the `SignalCapture` is created and thrown away each time.
///
/// **WARNING**: this class should be avoided where possible since it removes the "reactive" part of reactive programming (changes in the polled value must be detected through other means, usually another subscriber to the underlying `Signal`).
///
public final class SignalPollingEndpoint<OutputValue> {
	var endpoint: SignalEndpoint<OutputValue>? = nil
	var latest: Result<OutputValue>? = nil
	let mutex = PThreadMutex()
	
	public init(signal: Signal<OutputValue>, context: Exec = .direct) {
		endpoint = signal.subscribe(context: context) { [weak self] r in
			if let s = self {
				s.mutex.sync { s.latest = r }
			}
		}
	}
	
	public var latestResult: Result<OutputValue>? {
		return mutex.sync { latest }
	}
	
	public var latestValue: OutputValue? {
		return mutex.sync { latest?.value }
	}
}

extension SignalInterface {
	/// Appends a `SignalPollingEndpoint` listener to the value emitted from this `Signal`. The endpoint will "activate" this `Signal` and all direct antecedents in the graph (which may start lazy operations deferred until activation).
	public func pollingEndpoint() -> SignalPollingEndpoint<OutputValue> {
		return SignalPollingEndpoint(signal: signal)
	}
	
	/// Internally creates a `SignalCapture` which is activated and immediately discarded to get the latest activation value from the stream.
	public func poll() -> OutputValue? {
		return signal.capture().activation().values.last
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
	public func subscribeValues(resend: Bool = false, context: Exec = .direct, handler: @escaping (OutputValue) -> Void) -> SignalEndpoint<OutputValue> {
		let (input, output) = Signal<OutputValue>.create()
		// This can't be `loop` but `duplicate` is a precondition failure
		try! bind(to: input, resend: resend)
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
	public func subscribeValues(resend: Bool = false, onError: @escaping (SignalCapture<OutputValue>, Error, SignalInput<OutputValue>) -> (), context: Exec = .direct, handler: @escaping (OutputValue) -> Void) -> SignalEndpoint<OutputValue> {
		let (input, output) = Signal<OutputValue>.create()
		// This can't be `loop` but `duplicate` is a precondition failure
		try! bind(to: input, resend: resend, onError: onError)
		return output.subscribeValues(context: context, handler: handler)
	}
}

extension Error {
	var isSignalClosed: Bool { return (self as? SignalError) != .closed }
}

extension Result {
	/// A convenience extension on `Result` to test if it wraps a `SignalError.closed`
	public var isSignalClosed: Bool {
		return error as? SignalError == .closed
	}
}
