//
//  CwlSignalChannel.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 2017/06/27.
//  Copyright © 2017 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

#if SWIFT_PACKAGE
	import CwlUtils
#endif

/// A `SignalChannel` forms a basic wrapper around a `SignalInput`/`Signal` pair and exists for syntactic convenience when building a series of pipeline stages and returning the head and tail of the pipeline.
///
/// e.g.: let (input, output) = Signal<Int>.channel().map { $0 + 1 }.subscribe { print($0) }
///
/// Every transform in the CwlSignal library that can be applied to `Signal<Interface.OutputValue>` can also be applied to `SignalChannel<Interface.OutputValue>`. Where possible, the result is another `SignalChannel` so the result can be immediately transformed again.
public struct SignalChannel<InputInterface: SignalInputInterface, Interface: SignalInterface> {
	public let input: InputInterface
	public let signal: Interface
	public init(input: InputInterface, signal: Interface) { (self.input, self.signal) = (input, signal) }
}

extension SignalChannel {
	/// Append an additional `Signal` stage in the `SignalChannel` pipeline, returning a new SignalChannel that combines the `input` from `self` and the `signal` from the new stage.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns a new `Signal`.
	/// - Returns: a `SignalChannel` combining `input` and the result from `compose`.
	/// - Throws: rethrows the contents of the `compose` closure.
	public func next<Next>(_ compose: (Signal<Interface.OutputValue>) throws -> Next) rethrows -> SignalChannel<InputInterface, Next> {
		return try SignalChannel<InputInterface, Next>(input: input, signal: compose(signal.signal))
	}
	
	/// Similar to `next` but producing a new stage that is *not* a `Signal` and returning `input` and this new stage as a tuple.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns a new value.
	/// - Returns: a tuple combining `input` and the result from `compose`.
	/// - Throws: rethrows the contents of the `compose` closure.
	public func final<U>(_ compose: (Signal<Interface.OutputValue>) throws -> U) rethrows -> (input: InputInterface, output: U) {
		return try (input, compose(signal.signal))
	}
	
	/// Similar to `next` but consuming (not returning) the result from the `compose` function. The result is simply `input` from `self`. Typically used when `bind(to:)` is invoked, linking the output of this channel to another signal graph.
	///
	/// - Parameter compose: a transformation that takes `signal` from `self` and returns `Void`.
	/// - Returns: `input` from `self`
	/// - Throws: rethrows the contents of the `compose` closure.
	public func consume(_ compose: (Signal<Interface.OutputValue>) throws -> ()) rethrows -> InputInterface {
		try compose(signal.signal)
		return input
	}
	
	/// A `SignalChannel` is essentially a tuple. This property explodes the contents as a convenience in some scenarios.
	public var tuple: (input: InputInterface, signal: Interface) { return (input: input, signal: signal) }
}

public typealias Input<Value> = SignalChannel<SignalInput<Value>, Signal<Value>>
public typealias MultiInput<Value> = SignalChannel<SignalMultiInput<Value>, Signal<Value>>
public typealias MergedInput<Value> = SignalChannel<SignalMergedInput<Value>, Signal<Value>>

extension SignalChannel { 
	public init<Value>() where SignalInput<Value> == InputInterface, Signal<Value> == Interface {
		self = Signal<Value>.channel()
	}
	public init<Value>() where SignalMultiInput<Value> == InputInterface, Signal<Value> == Interface {
		self = Signal<Value>.multiChannel()
	}
	public init<Value>() where SignalMergedInput<Value> == InputInterface, Signal<Value> == Interface {
		self = Signal<Value>.mergedChannel()
	}
}

extension Signal {
	/// This function is used for starting SignalChannel pipelines with a `SignalInput`
	public static func channel() -> SignalChannel<SignalInput<OutputValue>, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.create()
		return SignalChannel<SignalInput<OutputValue>, Signal<OutputValue>>(input: input, signal: signal)
	}
	
	/// This function is used for starting SignalChannel pipelines with a `SignalMultiInput`
	public static func multiChannel() -> SignalChannel<SignalMultiInput<OutputValue>, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.createMultiInput()
		return SignalChannel<SignalMultiInput<OutputValue>, Signal<OutputValue>>(input: input, signal: signal)
	}
	
	/// This function is used for starting SignalChannel pipelines with a `SignalMergedInput`
	public static func mergedChannel(onLastInputClosed: SignalEnd? = nil, onDeinit: SignalEnd = .cancelled) -> SignalChannel<SignalMergedInput<OutputValue>, Signal<OutputValue>> {
		let (input, signal) = Signal<OutputValue>.createMergedInput(onLastInputClosed: onLastInputClosed, onDeinit: onDeinit)
		return SignalChannel<SignalMergedInput<OutputValue>, Signal<OutputValue>>(input: input, signal: signal)
	}
}

// Implementation of Signal.swift
extension SignalChannel {
	public func subscribe(context: Exec = .direct, _ handler: @escaping (Result<Interface.OutputValue, SignalEnd>) -> Void) -> (input: InputInterface, output: SignalOutput<Interface.OutputValue>) {
		let tuple = final { $0.subscribe(context: context, handler) }
		return (input: tuple.input, output: tuple.output)
	}
	
	public func subscribeWhile(context: Exec = .direct, _ handler: @escaping (Result<Interface.OutputValue, SignalEnd>) -> Bool) -> InputInterface {
		return final { $0.subscribeWhile(context: context, handler) }.input
	}
	
	public func junction() -> (input: InputInterface, junction: SignalJunction<Interface.OutputValue>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, _ processor: @escaping (Result<Interface.OutputValue, SignalEnd>) -> Signal<U>.Next) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.transform(context: context, processor) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, Result<Interface.OutputValue, SignalEnd>) -> Signal<U>.Next) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.transform(initialState: initialState, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V>(_ second: U, context: Exec = .direct, _ processor: @escaping (EitherResult2<Interface.OutputValue, U.OutputValue>) -> Signal<V>.Next) -> SignalChannel<InputInterface, Signal<V>> {
		return next { $0.combine(second, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W>(_ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (EitherResult3<Interface.OutputValue, U.OutputValue, V.OutputValue>) -> Signal<W>.Next) -> SignalChannel<InputInterface, Signal<W>> {
		return next { $0.combine(second, third, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(_ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (EitherResult4<Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue>) -> Signal<X>.Next) -> SignalChannel<InputInterface, Signal<X>> {
		return next { $0.combine(second, third, fourth, context: context, processor) }
	}
	
	public func combine<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(_ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (EitherResult5<Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue>) -> Signal<Y>.Next) -> SignalChannel<InputInterface, Signal<Y>> {
		return next { $0.combine(second, third, fourth, fifth, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V>(initialState: S, _ second: U, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult2<Interface.OutputValue, U.OutputValue>) -> Signal<V>.Next) -> SignalChannel<InputInterface, Signal<V>> {
		return next { $0.combine(second, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W>(initialState: S, _ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult3<Interface.OutputValue, U.OutputValue, V.OutputValue>) -> Signal<W>.Next) -> SignalChannel<InputInterface, Signal<W>> {
		return next { $0.combine(second, third, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(initialState: S, _ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult4<Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue>) -> Signal<X>.Next) -> SignalChannel<InputInterface, Signal<X>> {
		return next { $0.combine(second, third, fourth, initialState: initialState, context: context, processor) }
	}
	
	public func combine<S, U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(initialState: S, _ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (inout S, EitherResult5<Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue>) -> Signal<Y>.Next) -> SignalChannel<InputInterface, Signal<Y>> {
		return next { $0.combine(second, third, fourth, fifth, initialState: initialState, context: context, processor) }
	}
	
	public func continuous(initialValue: Interface.OutputValue) -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.continuous(initialValue: initialValue) }
	}
	
	public func continuous() -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.continuous() }
	}
	
	public func continuousWhileActive() -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.continuousWhileActive() }
	}
	
	public func playback() -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.playback() }
	}
	
	public func cacheUntilActive() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.cacheUntilActive() }
	}
	
	public func multicast() -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.multicast() }
	}
	
	public func multicast(sequence: [SignalInput<Interface.OutputValue>]) -> InputInterface {
		return final {
			let multi = $0.multicast()
			for i in sequence {
				multi.bind(to: i)
			}
		}.input
	}
	
	public func multicast(_ interfaces: SignalInput<Interface.OutputValue>...) -> InputInterface {
		return multicast(sequence: interfaces)
	}
	
	public func customActivation(initialValues: Array<Interface.OutputValue> = [], context: Exec = .direct, _ updater: @escaping (_ cachedValues: inout Array<Interface.OutputValue>, _ cachedEnd: inout SignalEnd?, _ incoming: Result<Interface.OutputValue, SignalEnd>) -> Void) -> SignalChannel<InputInterface, SignalMulti<Interface.OutputValue>> {
		return next { $0.customActivation(initialValues: initialValues, context: context, updater) }
	}
	
	public func reduce<State>(initialState: State, context: Exec = .direct, _ reducer: @escaping (_ state: State, _ message: Interface.OutputValue) throws -> State) -> SignalChannel<InputInterface, SignalMulti<State>> {
		return next { $0.reduce(initialState: initialState, context: context, reducer) }
	}
	
	public func capture() -> (input: InputInterface, capture: SignalCapture<Interface.OutputValue>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalChannel {
	public func dropActivation() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.dropActivation() }
	}
	
	public func deferActivation() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.deferActivation() }
	}
	
	public func subscribeUntilEnd(context: Exec = .direct, _ handler: @escaping (Result<Interface.OutputValue, SignalEnd>) -> Void) -> InputInterface {
		return final { $0.subscribeUntilEnd(context: context, handler) }.input
	}
	
	public func subscribeValues(context: Exec = .direct, _ handler: @escaping (Interface.OutputValue) -> Void) -> (input: InputInterface, output: SignalOutput<Interface.OutputValue>) {
		let tuple = final { $0.subscribeValues(context: context, handler) }
		return (input: tuple.input, output: tuple.output)
	}
	
	public func subscribeValuesUntilEnd(context: Exec = .direct, _ handler: @escaping (Interface.OutputValue) -> Void) -> InputInterface {
		signal.subscribeValuesUntilEnd(context: context, handler)
		return input
	}
	
	public func subscribeValuesWhile(context: Exec = .direct, _ handler: @escaping (Interface.OutputValue) -> Bool) -> InputInterface {
		signal.subscribeValuesWhile(context: context, handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalEndPropagation = .none, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalEndPropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, Interface.OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<DurationInterface: SignalInterface>(closePropagation: SignalEndPropagation = .none, context: Exec = .direct, _ duration: @escaping (Interface.OutputValue) -> DurationInterface) -> SignalChannel<InputInterface, Signal<(Int, Interface.OutputValue?)>> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration) }
	}
	
	public func valueDurations<DurationInterface: SignalInterface, V>(initialState: V, closePropagation: SignalEndPropagation = .none, context: Exec = .direct, _ duration: @escaping (inout V, Interface.OutputValue) -> DurationInterface) -> SignalChannel<InputInterface, Signal<(Int, Interface.OutputValue?)>> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration) }
	}
	
	public func toggle(initialState: Bool = false) -> SignalChannel<InputInterface, Signal<Bool>> {
		return next { $0.toggle(initialState: initialState) }
	}
	
	public func optional() -> SignalChannel<InputInterface, Signal<Interface.OutputValue?>> {
		return next { $0.optional() }
	}
	
	public func optionalToArray<U>() -> SignalChannel<InputInterface, Signal<[U]>> where Interface.OutputValue == Optional<U> {
		return next { $0.optionalToArray() }
	}
	
	public func bind<Target>(to interface: Target) -> InputInterface where Target: SignalInputInterface, Target.InputValue == Interface.OutputValue {
		return final { $0.bind(to: interface) }.input
	}
	
	public func bind(to: SignalMergedInput<Interface.OutputValue>, closePropagation: SignalEndPropagation = .none, removeOnDeactivate: Bool = false) -> InputInterface {
		signal.signal.bind(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cacheLatest() -> (input: InputInterface, output: SignalLatest<Interface.OutputValue>) {
		let tuple = final { SignalLatest(signal: $0) }
		return (input: tuple.input, output: tuple.output)
	}
}

// Implementation of SignalReactive.swift
extension SignalChannel {
	public func buffer<Boundaries: SignalInterface>(boundaries: Boundaries) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<Boundaries: SignalInterface>(windows: Boundaries) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> where Boundaries.OutputValue: SignalInterface {
		return next { $0.buffer(windows: windows) }
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> {
		return next { $0.buffer(count: count, skip: skip) }
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> {
		return next { $0.buffer(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func buffer(count: UInt) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> {
		return next { $0.buffer(count: count, skip: count) }
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<[Interface.OutputValue]>> {
		return next { $0.buffer(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func compact<U>() -> SignalChannel<InputInterface, Signal<U>> where Interface.OutputValue == Optional<U> {
		return next { $0.compact() }
	}
		
	public func compactMap<U>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> U?) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.compactMap(context: context, processor) }
	}
	
	public func compactMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, Interface.OutputValue) throws -> U?) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.compactMap(initialState: initialState, context: context, processor) }
	}

	public func compactMapActivation<U>(select: SignalActivationSelection, context: Exec = .direct, activation: @escaping (Interface.OutputValue) throws -> U?, remainder: @escaping (Interface.OutputValue) throws -> U?) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.compactMapActivation(select: select, context: context, activation: activation, remainder: remainder) }
	}
	
	public func compactMapLatestActivation(select: SignalActivationSelection, context: Exec = .direct, activation: @escaping (Interface.OutputValue) throws -> Interface.OutputValue?) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.compactMapLatestActivation(context: context, activation: activation) }
	}
	
	public func flatten<V>() -> SignalChannel<InputInterface, Signal<V>> where Interface.OutputValue: SignalInterface, Interface.OutputValue.OutputValue == V {
		return next { $0.flatten() }
	}
	
	public func flatMap<Content: SignalInterface>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> Content) -> SignalChannel<InputInterface, Signal<Content.OutputValue>> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<Content: SignalInterface>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> Content) -> SignalChannel<InputInterface, Signal<Content.OutputValue>> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<Content: SignalInterface>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> Content) -> SignalChannel<InputInterface, Signal<Content.OutputValue>> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<Content: SignalInterface, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, Interface.OutputValue) throws -> Content) -> SignalChannel<InputInterface, Signal<Content.OutputValue>> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<Content: SignalInterface>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> Content) -> SignalChannel<InputInterface, Signal<Content.OutputValue>> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> U) -> SignalChannel<InputInterface, Signal<(U, Signal<Interface.OutputValue>)>> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func mapErrors(context: Exec = .direct, _ processor: @escaping (SignalEnd) -> SignalEnd) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.mapErrors(context: context, processor) }
	}
	
	public func keyPath<U>(_ keyPath: KeyPath<Interface.OutputValue, U>) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.keyPath(keyPath) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (Interface.OutputValue) throws -> U) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, Interface.OutputValue) throws -> U) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, Interface.OutputValue) throws -> U) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<Boundaries: SignalInterface>(boundaries: Boundaries) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<Boundaries: SignalInterface>(windows: Boundaries) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> where Boundaries.OutputValue: SignalInterface {
		return next { $0.window(windows: windows) }
	}
	
	public func window(count: UInt, skip: UInt) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> {
		return next { $0.window(count: count, skip: skip) }
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> {
		return next { $0.window(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func window(count: UInt) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> {
		return next { $0.window(count: count, skip: count) }
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Signal<Interface.OutputValue>>> {
		return next { $0.window(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = false, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.debounce(interval: interval, flushOnClose: flushOnClose, context: context) }
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.throttleFirst(interval: interval, context: context) }
	}
}

extension SignalChannel where Interface.OutputValue: Hashable {
	public func distinct() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.distinct() }
	}
}

extension SignalChannel where Interface.OutputValue: Equatable {
	public func distinctUntilChanged() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalChannel {
	public func distinctUntilChanged(context: Exec = .direct, compare: @escaping (Interface.OutputValue, Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.distinctUntilChanged(context: context, compare: compare) }
	}
	
	public func elementAt(_ index: UInt) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.elementAt(index) }
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.filter(context: context, matching: matching) }
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.ofType(type) }
	}
	
	public func first(context: Exec = .direct, matching: @escaping (Interface.OutputValue) throws -> Bool = { _ in true }) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.first(context: context, matching: matching) }
	}
	
	public func single(context: Exec = .direct, matching: @escaping (Interface.OutputValue) throws -> Bool = { _ in true }) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.single(context: context, matching: matching) }
	}
	
	public func ignoreElements<U>(outputType: U.Type = U.self) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.ignoreElements(outputType: outputType) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (Interface.OutputValue) throws -> Bool = { _ in true }) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample<Trigger: SignalInterface>(_ trigger: Trigger) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> where Trigger.OutputValue == () {
		return next { $0.sample(trigger) }
	}
	
	public func throttleFirst<Trigger: SignalInterface>(_ trigger: Trigger) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> where Trigger.OutputValue == () {
		return next { $0.throttleFirst(trigger) }
	}
	
	public func withLatestFrom<Interface: SignalInterface>(_ sample: Interface) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.withLatestFrom(sample) }
	}
	
	public func withLatestFrom<Other: SignalInterface, R>(_ sample: Other, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, Other.OutputValue) throws -> R) -> SignalChannel<InputInterface, Signal<R>> {
		return next { $0.withLatestFrom(sample, context: context, processor) }
	}
	
	public func skip(_ count: Int) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.skip(count) }
	}
	
	public func skipLast(_ count: Int) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.skipLast(count) }
	}
	
	public func take(_ count: Int) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.take(count) }
	}
	
	public func takeLast(_ count: Int) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.takeLast(count) }
	}
	
	public func combineLatestWtith<U: SignalInterface, V>(_ second: U, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, U.OutputValue) throws -> V) -> SignalChannel<InputInterface, Signal<V>> {
		return next { $0.combineLatestWith(second, context: context, processor) }
	}
	
	public func combineLatestWith<U: SignalInterface, V: SignalInterface, W>(_ second: U, _ third: V, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, U.OutputValue, V.OutputValue) throws -> W) -> SignalChannel<InputInterface, Signal<W>> {
		return next { $0.combineLatestWith(second, third, context: context, processor) }
	}
	
	public func combineLatestWith<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(_ second: U, _ third: V, _ fourth: W, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue) throws -> X) -> SignalChannel<InputInterface, Signal<X>> {
		return next { $0.combineLatestWith(second, third, fourth, context: context, processor) }
	}
	
	public func combineLatestWith<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface, Y>(_ second: U, _ third: V, _ fourth: W, _ fifth: X, context: Exec = .direct, _ processor: @escaping (Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue) throws -> Y) -> SignalChannel<InputInterface, Signal<Y>> {
		return next { $0.combineLatestWith(second, third, fourth, fifth, context: context, processor) }
	}
	
	public func intersect<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(withRight: U, leftEnd: @escaping (Interface.OutputValue) -> V, rightEnd: @escaping (U.OutputValue) -> W, context: Exec = .direct, _ processor: @escaping ((Interface.OutputValue, U.OutputValue)) -> X) -> SignalChannel<InputInterface, Signal<X>> {
		return next { $0.intersect(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupIntersect<U: SignalInterface, V: SignalInterface, W: SignalInterface, X>(withRight: U, leftEnd: @escaping (Interface.OutputValue) -> V, rightEnd: @escaping (U.OutputValue) -> W, context: Exec = .direct, _ processor: @escaping ((Interface.OutputValue, Signal<U.OutputValue>)) -> X) -> SignalChannel<InputInterface, Signal<X>> {
		return next { $0.groupIntersect(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func merge(_ sources: Signal<Interface.OutputValue>...) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.merge(sequence: sources) }
	}
	
	public func merge<S: Sequence>(sequence: S) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> where S.Iterator.Element == Signal<Interface.OutputValue> {
		return next { $0.merge(sequence: sequence) }
	}
	
	public func startWith<S: Sequence>(sequence: S) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> where S.Iterator.Element == Interface.OutputValue {
		return next { $0.startWith(sequence: sequence) }
	}
	
	public func startWith(_ values: Interface.OutputValue...) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.startWith(sequence: values) }
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (SignalEnd) -> SignalEnd? = { e in e }) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> where U.Iterator.Element == Interface.OutputValue {
		return next { $0.endWith(sequence: sequence, conditional: conditional) }
	}
	
	func endWith(_ values: Interface.OutputValue..., conditional: @escaping (SignalEnd) -> SignalEnd? = { e in e }) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.endWith(sequence: values, conditional: conditional) }
	}
	
	public func switchLatest<U>() -> SignalChannel<InputInterface, Signal<U>> where Interface.OutputValue: Signal<U> {
		return next { $0.switchLatest() }
	}

	public func zipWith<U: SignalInterface>(_ second: U) -> SignalChannel<InputInterface, Signal<(Interface.OutputValue, U.OutputValue)>> {
		return next { $0.zipWith(second) }
	}
	
	public func zipWith<U: SignalInterface, V: SignalInterface>(_ second: U, _ third: V) -> SignalChannel<InputInterface, Signal<(Interface.OutputValue, U.OutputValue, V.OutputValue)>> {
		return next { $0.zipWith(second, third) }
	}
	
	public func zipWith<U: SignalInterface, V: SignalInterface, W: SignalInterface>(_ second: U, _ third: V, _ fourth: W) -> SignalChannel<InputInterface, Signal<(Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue)>> {
		return next { $0.zipWith(second, third, fourth) }
	}
	
	public func zipWith<U: SignalInterface, V: SignalInterface, W: SignalInterface, X: SignalInterface>(_ second: U, _ third: V, _ fourth: W, _ fifth: X) -> SignalChannel<InputInterface, Signal<(Interface.OutputValue, U.OutputValue, V.OutputValue, W.OutputValue, X.OutputValue)>> {
		return next { $0.zipWith(second, third, fourth, fifth) }
	}
	
	public func catchError(context: Exec = .direct, recover: @escaping (SignalEnd) -> Signal<Interface.OutputValue>) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, SignalEnd) -> DispatchTimeInterval?) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.retry(initialState, context: context, shouldRetry: shouldRetry) }
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.retry(count: count, delayInterval: delayInterval, context: context) }
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalEndPropagation = .none, context: Exec = .direct, offset: @escaping (inout U, Interface.OutputValue) -> DispatchTimeInterval) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.delay(interval: interval, context: context) }
	}
	
	public func delay<U>(closePropagation: SignalEndPropagation = .none, context: Exec = .direct, offset: @escaping (Interface.OutputValue) -> Signal<U>) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.delay(closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalEndPropagation = .none, context: Exec = .direct, offset: @escaping (inout V, Interface.OutputValue) -> Signal<U>) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func onActivate(context: Exec = .direct, _ handler: @escaping () -> ()) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.onActivate(context: context, handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, _ handler: @escaping () -> ()) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.onDeactivate(context: context, handler) }
	}
	
	public func onResult(context: Exec = .direct, _ handler: @escaping (Result<Interface.OutputValue, SignalEnd>) -> ()) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.onResult(context: context, handler) }
	}
	
	public func onValue(context: Exec = .direct, _ handler: @escaping (Interface.OutputValue) -> ()) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.onValue(context: context, handler) }
	}
	
	public func onError(context: Exec = .direct, _ handler: @escaping (SignalEnd) -> ()) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.onError(context: context, handler) }
	}

	public func debug(logPrefix: String = "", file: String = #file, line: Int = #line) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.debug(logPrefix: logPrefix, file: file, line: line) }
	}
	
	public func materialize() -> SignalChannel<InputInterface, Signal<Result<Interface.OutputValue, SignalEnd>>> {
		return next { $0.materialize() }
	}
	
	public func timeInterval(context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Double>> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalChannel<InputInterface, Signal<(Interface.OutputValue, DispatchTime)>> {
		return next { $0.timestamp(context: context) }
	}
	
	public func all(context: Exec = .direct, test: @escaping (Interface.OutputValue) -> Bool) -> SignalChannel<InputInterface, Signal<Bool>> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func find(context: Exec = .direct, test: @escaping (Interface.OutputValue) -> Bool) -> SignalChannel<InputInterface, Signal<Bool>> {
		return next { $0.find(context: context, test: test) }
	}
	
	public func findIndex(context: Exec = .direct, test: @escaping (Interface.OutputValue) -> Bool) -> SignalChannel<InputInterface, Signal<Int?>> {
		return next { $0.findIndex(context: context, test: test) }
	}
}

extension SignalChannel where Interface.OutputValue: Equatable {
	public func find(value: Interface.OutputValue) -> SignalChannel<InputInterface, Signal<Bool>> {
		return next { $0.find(value: value) }
	}
}

extension SignalChannel {
	public func defaultIfEmpty(value: Interface.OutputValue) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<Interface.OutputValue>) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalChannel where Interface.OutputValue: Equatable {
	public func sequenceEqual(to: Signal<Interface.OutputValue>) -> SignalChannel<InputInterface, Signal<Bool>> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalChannel {
	public func skipUntil<U: SignalInterface>(_ other: U) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U: SignalInterface>(_ other: U) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.takeUntil(other) }
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.takeWhile(context: context, condition: condition) }
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, Interface.OutputValue) throws -> Bool) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.takeWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) throws -> U?, fold: @escaping (V, Interface.OutputValue) throws -> V) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold) }
	}
}

extension SignalChannel where Interface.OutputValue: BinaryInteger {
	public func average() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.average() }
	}
}

extension SignalChannel {
	public func concat(_ other: Signal<Interface.OutputValue>) -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalChannel<InputInterface, Signal<Int>> {
		return next { $0.count() }
	}
}

extension SignalChannel where Interface.OutputValue: Comparable {
	public func min() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.min() }
	}
	
	public func max() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.max() }
	}
}

extension SignalChannel {
	public func aggregate<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, Interface.OutputValue) -> U) -> SignalChannel<InputInterface, Signal<U>> {
		return next { $0.aggregate(initial, context: context, fold: fold) }
	}
}

extension SignalChannel where Interface.OutputValue: Numeric {
	public func sum() -> SignalChannel<InputInterface, Signal<Interface.OutputValue>> {
		return next { $0.sum() }
	}
}
