//
//  CwlSignalChannel.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2017/06/27.
//  Copyright © 2017 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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

/// A `SignalChannel` forms a basic wrapper around a `SignalInput`/`Signal` pair and exists for syntactic convenience when building a series of pipeline stages and returning the head and tail of the pipeline.
///
/// e.g.: let (input, endpoint) = Signal<Int>.channel().map { $0 + 1 }.subscribe { print($0) }
///
/// Every transform in the CwlSignal library that can be applied to `Signal<OutputValue>` can also be applied to `SignalChannel<OutputValue>`. Where possible, the result is another `SignalChannel` so the result can be immediately transformed again.
/// Since Swift can't represent higher-kinded types, this type uses two pairs of parameters, with each pair consisting of a free type and a constrained type, cooperating to acheive the desired effect. Unfortunately, this makes the `SignalChannel` little clumsy. If you need to declare a variable, you might want to consider one of the SignalPair typealiases since these remove the redundancy.
public struct SignalChannel<InputValue, Input: SignalInput<InputValue>, OutputValue, Output: Signal<OutputValue>> {
	public let input: Input
	public let signal: Output
	public init(input: Input, signal: Output) {
		(self.input, self.signal) = (input, signal)
	}
	
	/// Append an additional `Signal` stage in the `SignalChannel` pipeline, returning a new SignalChannel that combines the `input` from `self` and the `signal` from the new stage.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns a new `Signal`.
	/// - Returns: a `SignalChannel` combining `input` and the result from `compose`.
	/// - Throws: rethrows the contents of the `compose` closure.
	public func next<U, SU: Signal<U>>(_ compose: (Signal<OutputValue>) throws -> SU) rethrows -> SignalChannel<InputValue, Input, U, SU> {
		return try SignalChannel<InputValue, Input, U, SU>(input: input, signal: compose(signal))
	}
	
	/// Similar to `next` but producing a new stage that is *not* a `Signal` and returning `input` and this new stage as a tuple.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns a new value.
	/// - Returns: a tuple combining `input` and the result from `compose`.
	/// - Throws: rethrows the contents of the `compose` closure.
	public func final<U>(_ compose: (Signal<OutputValue>) throws -> U) rethrows -> (input: Input, output: U) {
		return try (input, compose(signal))
	}
	
	/// Similar to `next` but consuming (not returning) the result from the `compose` function. The result is simply `input` from `self`. Typically used when `bind(to:)` is invoked, linking the output of this channel to another signal graph.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns `Void`.
	/// - Returns: `input` from `self`
	/// - Throws: rethrows the contents of the `compose` closure.
	public func consume(_ compose: (Signal<OutputValue>) throws -> ()) rethrows -> Input {
		try compose(signal)
		return input
	}
	
	/// A `SignalChannel` is essentially a tuple. This property explodes the contents as a convenience in some scenarios.
	public var tuple: (input: Input, signal: Output) { return (input: input, signal: signal) }
}

public typealias SignalPair<InputValue, OutputValue> = SignalChannel<InputValue, SignalInput<InputValue>, OutputValue, Signal<OutputValue>>
public typealias SignalMultiOutputPair<InputValue, OutputValue> = SignalChannel<InputValue, SignalInput<InputValue>, OutputValue, SignalMulti<OutputValue>>
public typealias SignalMultiInputPair<InputValue, OutputValue> = SignalChannel<InputValue, SignalMultiInput<InputValue>, OutputValue, Signal<OutputValue>>
public typealias SignalMultiPair<InputValue, OutputValue> = SignalChannel<InputValue, SignalMultiInput<InputValue>, OutputValue, SignalMulti<OutputValue>>

public typealias Input<Value> = SignalPair<Value, Value>
extension SignalChannel where InputValue == OutputValue, Input == SignalInput<InputValue>, Output == Signal<OutputValue> {
	public init() {
		self = Signal<InputValue>.channel()
	}
}

extension Signal {
	/// This function is used for starting SignalChannel pipeliens with a `SignalInput`
	public static func channel() -> SignalChannel<OutputValue, SignalInput<OutputValue>, OutputValue, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.create()
		return SignalChannel<OutputValue, SignalInput<OutputValue>, OutputValue, Signal<OutputValue>>(input: input, signal: signal)
	}
	
	/// This function is used for starting SignalChannel pipeliens with a `SignalMultiInput`
	public static func multiChannel() -> SignalChannel<OutputValue, SignalMultiInput<OutputValue>, OutputValue, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.createMultiInput()
		return SignalChannel<OutputValue, SignalMultiInput<OutputValue>, OutputValue, Signal<OutputValue>>(input: input, signal: signal)
	}
	
	/// This function is used for starting SignalChannel pipeliens with a `SignalMergedInput`
	public static func mergedChannel(onLastInputClosed: Error? = nil, onDeinit: Error = SignalComplete.cancelled) -> SignalChannel<OutputValue, SignalMergedInput<OutputValue>, OutputValue, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.createMergedInput(onLastInputClosed: onLastInputClosed, onDeinit: onDeinit)
		return SignalChannel<OutputValue, SignalMergedInput<OutputValue>, OutputValue, Signal<OutputValue>>(input: input, signal: signal)
	}
}

// Implementation of Signal.swift
extension SignalChannel {
	public func subscribe(context: Exec = .direct, _ handler: @escaping (Result<OutputValue>) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribe(context: context, handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeWhile(context: Exec = .direct, _ handler: @escaping (Result<OutputValue>) -> Bool) -> Input {
		return final { $0.subscribeWhile(context: context, handler) }.input
	}
	
	public func junction() -> (input: Input, junction: SignalJunction<OutputValue>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, _ processor: @escaping (Result<OutputValue>, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(context: context, processor) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, Result<OutputValue>, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(initialState: initialState, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V>(_ second: U, context: Exec = .direct, _ processor: @escaping (EitherResult2<OutputValue, U.OutputValue>, SignalNext<V>) -> Void) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(second, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W>(_ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (EitherResult3<OutputValue, U.OutputValue, V.OutputValue>, SignalNext<W>) -> Void) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(second, third, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(_ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (EitherResult4<OutputValue, U.OutputValue, V.OutputValue, W.OutputValue>, SignalNext<X>) -> Void) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(second, third, fourth, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(_ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (EitherResult5<OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue>, SignalNext<Y>) -> Void) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(second, third, fourth, fifth, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V>(initialState: S, _ second: U, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult2<OutputValue, U.OutputValue>, SignalNext<V>) -> Void) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(second, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W>(initialState: S, _ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult3<OutputValue, U.OutputValue, V.OutputValue>, SignalNext<W>) -> Void) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(second, third, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(initialState: S, _ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult4<OutputValue, U.OutputValue, V.OutputValue, W.OutputValue>, SignalNext<X>) -> Void) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(second, third, fourth, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(initialState: S, _ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult5<OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue>, SignalNext<Y>) -> Void) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(second, third, fourth, fifth, initialState: initialState, context: context, processor) }
	}
	
	public func continuous(initialValue: OutputValue) -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuous(initialValue: initialValue) }
	}
	
	public func continuous() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuous() }
	}
	
	public func continuousWhileActive() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.continuousWhileActive() }
	}
	
	public func playback() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func cacheUntilActive() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.cacheUntilActive() }
	}
	
	public func multicast() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.multicast() }
	}
	
	public func multicast(_ interfaces: SignalInput<OutputValue>...) -> Input {
		return final {
			let multi = $0.multicast()
			for i in interfaces {
				multi.bind(to: i)
			}
		}.input
	}
	
	public func customActivation(initialValues: Array<OutputValue> = [], context: Exec = .direct, _ updater: @escaping (_ cachedValues: inout Array<OutputValue>, _ cachedError: inout Error?, _ incoming: Result<OutputValue>) -> Void) -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.customActivation(initialValues: initialValues, context: context, updater) }
	}
	
	public func reduce<State>(initialState: State, context: Exec = .direct, _ reducer: @escaping (_ state: inout State, _ message: OutputValue) throws -> State) -> SignalChannel<InputValue, Input, State, SignalMulti<State>> {
		return next { $0.reduce(initialState: initialState, context: context, reducer) }
	}
	
	public func capture() -> (input: Input, capture: SignalCapture<OutputValue>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalChannel {
	public func dropActivation() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.dropActivation() }
	}
	
	public func deferActivation() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.deferActivation() }
	}
	
	public func transformValues<U>(context: Exec = .direct, _ processor: @escaping (OutputValue, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transformValues(context: context, processor) }
	}
	
	public func transformValues<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transformValues(initialState: initialState, context: context, processor) }
	}
	
	public func subscribeUntilEnd(context: Exec = .direct, _ handler: @escaping (Result<OutputValue>) -> Void) -> Input {
		return final { $0.subscribeUntilEnd(context: context, handler) }.input
	}
	
	public func subscribeValues(context: Exec = .direct, _ handler: @escaping (OutputValue) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribeValues(context: context, handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeValuesUntilEnd(context: Exec = .direct, _ handler: @escaping (OutputValue) -> Void) -> Input {
		signal.subscribeValuesUntilEnd(context: context, handler)
		return input
	}
	
	public func subscribeValuesWhile(context: Exec = .direct, _ handler: @escaping (OutputValue) -> Bool) -> Input {
		signal.subscribeValuesWhile(context: context, handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<Interface: SignalInterface>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ duration: @escaping (OutputValue) -> Interface) -> SignalChannel<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration) }
	}
	
	public func valueDurations<Interface: SignalInterface, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ duration: @escaping (inout V, OutputValue) -> Interface) -> SignalChannel<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration) }
	}
	
	public func toggle(initialState: Bool = false) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.toggle(initialState: initialState) }
	}
	
	public func optionalToArray<U>() -> SignalChannel<InputValue, Input, [U], Signal<[U]>> where OutputValue == Optional<U> {
		return next { $0.optionalToArray() }
	}
	
	public func bind<InputInterface>(to interface: InputInterface) -> Input where InputInterface: SignalInputInterface, InputInterface.InputValue == OutputValue {
		return final { $0.bind(to: interface) }.input
	}
	
	public func bind(to: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> Input {
		signal.bind(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cacheLatest() -> (input: Input, endpoint: SignalLatest<OutputValue>) {
		let tuple = final { SignalLatest(signal: $0) }
		return (input: tuple.input, endpoint: tuple.output)
	}
}

// Implementation of SignalReactive.swift
extension SignalChannel {
	public func buffer<Interface: SignalInterface>(boundaries: Interface) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<Interface: SignalInterface>(windows: Interface) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> where Interface.OutputValue: SignalInterface {
		return next { $0.buffer(windows: windows) }
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(count: count, skip: skip) }
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func buffer(count: UInt) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(count: count, skip: count) }
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func compactMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U?) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.compactMap(context: context, processor) }
	}
	
	public func compactMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) throws -> U?) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.compactMap(initialState: initialState, context: context, processor) }
	}
	
	public func flatMap<Interface: SignalInterface>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<Interface: SignalInterface>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<Interface: SignalInterface>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<Interface: SignalInterface, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) -> Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<Interface: SignalInterface>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U) -> SignalChannel<InputValue, Input, (U, Signal<OutputValue>), Signal<(U, Signal<OutputValue>)>> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func mapErrors(context: Exec = .direct, _ processor: @escaping (Error) -> Error) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.mapErrors(context: context, processor) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) throws -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<Interface: SignalInterface>(boundaries: Interface) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<Interface: SignalInterface>(windows: Interface) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> where Interface.OutputValue: SignalInterface {
		return next { $0.window(windows: windows) }
	}
	
	public func window(count: UInt, skip: UInt) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(count: count, skip: skip) }
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func window(count: UInt) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(count: count, skip: count) }
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.debounce(interval: interval, flushOnClose: flushOnClose, context: context) }
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.throttleFirst(interval: interval, context: context) }
	}
}

extension SignalChannel where OutputValue: Hashable {
	public func distinct() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinct() }
	}
}

extension SignalChannel where OutputValue: Equatable {
	public func distinctUntilChanged() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalChannel {
	public func distinctUntilChanged(context: Exec = .direct, compare: @escaping (OutputValue, OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged(context: context, compare: compare) }
	}
	
	public func elementAt(_ index: UInt) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.elementAt(index) }
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.filter(context: context, matching: matching) }
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.ofType(type) }
	}
	
	public func first(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.first(context: context, matching: matching) }
	}
	
	public func single(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.single(context: context, matching: matching) }
	}
	
	public func ignoreElements<U>(outputType: U.Type = U.self) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.ignoreElements(outputType: outputType) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample<Interface: SignalInterface>(_ trigger: Interface) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where Interface.OutputValue == () {
		return next { $0.sample(trigger) }
	}
	
	public func sampleCombine<Interface: SignalInterface>(_ trigger: Interface) -> SignalChannel<InputValue, Input, (sample: OutputValue, trigger: Interface.OutputValue), Signal<(sample: OutputValue, trigger: Interface.OutputValue)>> {
		return next { $0.sampleCombine(trigger) }
	}
	
	public func trigger<Interface: SignalInterface>(_ source: Interface) -> SignalChannel<InputValue, Input, Interface.OutputValue, Signal<Interface.OutputValue>> {
		return next { $0.trigger(source) }
	}
	
	public func triggerCombine<Interface: SignalInterface>(_ source: Interface) -> SignalChannel<InputValue, Input, (trigger: OutputValue, sample: Interface.OutputValue), Signal<(trigger: OutputValue, sample: Interface.OutputValue)>> {
		return next { $0.triggerCombine(source) }
	}
	
	public func skip(_ count: Int) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skip(count) }
	}
	
	public func skipLast(_ count: Int) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipLast(count) }
	}
	
	public func take(_ count: Int) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.take(count) }
	}
	
	public func takeLast(_ count: Int) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeLast(count) }
	}
	
	public func combineLatest<U: SignalInterface, V>(_ second: U, context: Exec = .direct, _ processor: @escaping (OutputValue, U.OutputValue) -> V) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combineLatest(second, context: context, processor) }
	}
	
	public func combineLatest<U: SignalInterface, V: SignalInterface, W>(_ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (OutputValue, U.OutputValue, V.OutputValue) -> W) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combineLatest(second, third, context: context, processor) }
	}
	
	public func combineLatest<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(_ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (OutputValue, U.OutputValue, V.OutputValue, W.OutputValue) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combineLatest(second, third, fourth, context: context, processor) }
	}
	
	public func combineLatest<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(_ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue) -> Y) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combineLatest(second, third, fourth, fifth, context: context, processor) }
	}
	
	public func intersect<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(withRight: U, leftEnd: @escaping (OutputValue) -> V, rightEnd: @escaping (U.OutputValue) -> W, context: Exec = .direct, _ processor: @escaping ((OutputValue, U.OutputValue)) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.intersect(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupIntersect<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(withRight: U, leftEnd: @escaping (OutputValue) -> V, rightEnd: @escaping (U.OutputValue) -> W, context: Exec = .direct, _ processor: @escaping ((OutputValue, Signal<U.OutputValue>)) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.groupIntersect(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func mergeWith(_ sources: Signal<OutputValue>...) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.mergeWith(sources) }
	}
	
	public func mergeWith<S: Sequence>(_ sequence: S) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == Signal<OutputValue> {
		return next { $0.mergeWith(sequence) }
	}
	
	public func startWith<S: Sequence>(_ sequence: S) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == OutputValue {
		return next { $0.startWith(sequence) }
	}
	
	public func startWith(_ values: OutputValue...) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.startWith(values) }
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where U.Iterator.Element == OutputValue {
		return next { $0.endWith(sequence, conditional: conditional) }
	}
	
	func endWith(_ value: OutputValue, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.endWith(value, conditional: conditional) }
	}
	
	public func switchLatest<U>() -> SignalChannel<InputValue, Input, U, Signal<U>> where OutputValue: Signal<U> {
		return next { $0.switchLatest() }
	}

	public func zip<U: SignalInterface>(_ second: U) -> SignalChannel<InputValue, Input, (OutputValue, U.OutputValue), Signal<(OutputValue, U.OutputValue)>> {
		return next { $0.zip(second) }
	}
	
	public func zip<U: SignalInterface, V: SignalInterface>(_ second: U, _ third: V) -> SignalChannel<InputValue, Input, (OutputValue, U.OutputValue, V.OutputValue), Signal<(OutputValue, U.OutputValue, V.OutputValue)>> {
		return next { $0.zip(second, third) }
	}
	
	public func zip<U: SignalInterface, V: SignalInterface, W: SignalInterface>(_ second: U, _ third: V, _ fourth: W) -> SignalChannel<InputValue, Input, (OutputValue, U.OutputValue, V.OutputValue, W.OutputValue), Signal<(OutputValue, U.OutputValue, V.OutputValue, W.OutputValue)>> {
		return next { $0.zip(second, third, fourth) }
	}
	
	public func zip<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface>(_ second: U, _ third: V, _ fourth: W, _ fifth: X) -> SignalChannel<InputValue, Input, (OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue), Signal<(OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue)>> {
		return next { $0.zip(second, third, fourth, fifth) }
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == OutputValue {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<OutputValue>?) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.retry(initialState, context: context, shouldRetry: shouldRetry) }
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.retry(count: count, delayInterval: delayInterval, context: context) }
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, OutputValue) -> DispatchTimeInterval) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(interval: interval, context: context) }
	}
	
	public func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func onActivate(context: Exec = .direct, _ handler: @escaping () -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onActivate(context: context, handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, _ handler: @escaping () -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onDeactivate(context: context, handler) }
	}
	
	public func onResult(context: Exec = .direct, _ handler: @escaping (Result<OutputValue>) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onResult(context: context, handler) }
	}
	
	public func onValue(context: Exec = .direct, _ handler: @escaping (OutputValue) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onValue(context: context, handler) }
	}
	
	public func onError(context: Exec = .direct, _ handler: @escaping (Error) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onError(context: context, handler) }
	}
	
	public func materialize() -> SignalChannel<InputValue, Input, Result<OutputValue>, Signal<Result<OutputValue>>> {
		return next { $0.materialize() }
	}
	
	public func timeInterval(context: Exec = .direct) -> SignalChannel<InputValue, Input, Double, Signal<Double>> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalChannel<InputValue, Input, (OutputValue, DispatchTime), Signal<(OutputValue, DispatchTime)>> {
		return next { $0.timestamp(context: context) }
	}
	
	public func all(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func some(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.some(context: context, test: test) }
	}
}

extension SignalChannel where OutputValue: Equatable {
	public func contains(value: OutputValue) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.contains(value: value) }
	}
}

extension SignalChannel {
	public func defaultIfEmpty(value: OutputValue) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<OutputValue>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalChannel where OutputValue: Equatable {
	public func sequenceEqual(to: Signal<OutputValue>) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalChannel {
	public func skipUntil<U: SignalInterface>(_ other: U) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U: SignalInterface>(_ other: U) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeUntil(other) }
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeWhile(context: context, condition: condition) }
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.takeWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, OutputValue) -> V) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold) }
	}
}

extension SignalChannel where OutputValue: BinaryInteger {
	public func average() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.average() }
	}
}

extension SignalChannel {
	public func concat(_ other: Signal<OutputValue>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalChannel<InputValue, Input, Int, Signal<Int>> {
		return next { $0.count() }
	}
}

extension SignalChannel where OutputValue: Comparable {
	public func min() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.min() }
	}
	
	public func max() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.max() }
	}
}

extension SignalChannel {
	public func aggregate<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.aggregate(initial, context: context, fold: fold) }
	}
}

extension SignalChannel where OutputValue: Numeric {
	public func sum() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.sum() }
	}
}
