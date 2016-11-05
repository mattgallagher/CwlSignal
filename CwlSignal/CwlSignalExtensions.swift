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
	///   - processor: will be invoked with each value received
	/// - Returns: the `SignalEndpoint` created by this function
	public func subscribeValues(context: Exec = .direct, processor: @escaping (ValueType) -> Void) -> SignalEndpoint<ValueType> {
		return subscribe(context: context) { r in
			if case .success(let v) = r {
				processor(v)
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
	public func transformFlatten<U>(context: Exec = .direct, closesImmediate: Bool = false, processor: @escaping (T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		let (mergeSet, result) = Signal<U>.mergeSetAndSignal()
		let closeSignal = self.transform(context: context) { (r: Result<T>, n: SignalNext<U>) in
			switch r {
			case .success(let v): processor(v, mergeSet)
			case .failure(let e): n.send(error: e)
			}
		}
		// Keep the merge set alive at least as long as self
		mergeSet.add(closeSignal, closesOutput: closesImmediate)
		return result
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
	public func transformFlatten<S, U>(withState initialState: S, closesImmediate: Bool = false, context: Exec = .direct, processor: @escaping (inout S, T, SignalMergeSet<U>) -> ()) -> Signal<U> {
		let (mergeSet, result) = Signal<U>.mergeSetAndSignal()
		var closeError: Error? = nil
		let closeSignal = transform(withState: (onDelete: nil, userState: initialState), context: context) { (state: inout (onDelete: OnDelete?, userState: S), r: Result<T>, n: SignalNext<U>) in
			switch r {
			case .success(let v): processor(&state.userState, v, mergeSet)
			case .failure(let e):
				closeError = e
				n.send(error: e)
			}
		}
		
		// Keep the merge set alive at least as long as self
		mergeSet.add(closeSignal, closesOutput: closesImmediate)
		
		// On close, emit the error from self rather than the error from the merge set (which is usually `SignalError.cancelled` when `closesImmediate` is false.
		return result.transform { (r, n) in
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
		return transformFlatten(withState: 0, closesImmediate: closesImmediate, context: context) { (count: inout Int, v: T, mergeSet: SignalMergeSet<(Int, T?)>) in
			let innerSignal = duration(v).transform { [count] (innerResult: Result<U>, innerInput: SignalNext<(Int, T?)>) in
				if case .failure(let e) = innerResult {
					innerInput.send(value: (count, nil))
					innerInput.send(error: e)
				}
			}
			let prefixedInnerSignal = Signal<(Int, T?)>.preclosed(values: [(count, Optional(v))]).combine(second: innerSignal) { (r: CombinedResult2<(Int, T?), (Int, T?)>, n: SignalNext<(Int, T?)>) in
				switch r {
				case .result1(.success(let v)): n.send(value: v)
				case .result1(.failure): break
				case .result2(.success(let v)): n.send(value: v)
				case .result2(.failure(let e)): n.send(error: e)
				}
			}

			mergeSet.add(prefixedInnerSignal)
			count += 1
		}
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
			let prefixedInnerSignal = Signal<(Int, T?)>.preclosed(values: [(count, Optional(v))]).combine(second: innerSignal) { (r: CombinedResult2<(Int, T?), (Int, T?)>, n: SignalNext<(Int, T?)>) in
				switch r {
				case .result1(.success(let v)): n.send(value: v)
				case .result1(.failure): break
				case .result2(.success(let v)): n.send(value: v)
				case .result2(.failure(let e)): n.send(error: e)
				}
			}

			mergeSet.add(prefixedInnerSignal)
			state.index += 1
		}
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
