//
//  CwlSignalPair.swift
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

/// On its own, the `SignalPair` protocol is fairly useless – a tuple of two unconstrained types.
/// Actual usefulness comes from situations where it is constrained as:
///
///	Input: SignalInput<InputValue>, Output: Signal<OutputValue>
///
/// Due to limitations in Swift 3 and 4's type system, this constraint can be applied in extensions but cannot be applied in the base protocol.
/// `SignalChannel` is the most generic implementation of this protocol and encodes the expected constraints.
public protocol SignalPair {
	associatedtype InputValue
	associatedtype OutputValue
	associatedtype Input
	associatedtype Output
	
	var input: Input { get }
	var signal: Output { get }
	init(input: Input, signal: Output)
}

/// A `SignalChannel` and its common typealiases, `Channel`, `MultiChannel` form basic wrappers around a `SignalInput`/`Signal` pair.
///
/// This class exists for syntactic convenience when building a series of pipeline stages.
/// e.g.:
///		let (input, signal) = Channel<Int>().map { $0 + 1 }.tuple
///
/// Every transform in the CwlSignal library that can be applied to `Signal<OutputValue>` can also be applied to `SignalChannel<OutputValue>`. Where possible, the result is another `SignalChannel` so the result can be immediately transformed again.
///
/// A `Channel()` function exists in global scope to simplify syntax further in situations where the result type is already constrained:
///		someFunction(signalInput: Channel().map { $0 + 1 }.join(to: multiInputChannelFromElsewhere))
///
/// For similar syntactic reasons, `SignalInput<OutputValue>` includes static versions of all of those `SignalChannel` methods where the result is either a `SignalInput<OutputValue>` or a `SignalChannel` where `InputValue` remains unchanged.
/// e.g.:
///		someFunction(signalInput: .join(to: multiInputChannelFromElsewhere))
/// Unfortunately, due to limitations in Swift, this bare `SiganlInput` approach works only in those cases where the channel is a single stage ending in a `SignalInput<OutputValue>`.
public struct SignalChannel<IV, I: SignalInput<IV>, OV, O: Signal<OV>>: SignalPair {
	public typealias InputValue = IV
	public typealias OutputValue = OV
	public typealias Input = I
	public typealias Output = O
	
	public let input: Input
	public let signal: Output
	public init(input: Input, signal: Output) {
		(self.input, self.signal) = (input, signal)
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public init(_ tuple: (Input, Output)) {
		self.init(input: tuple.0, signal: tuple.1)
	}
	public func next<U, SU: Signal<U>>(_ compose: (Signal<OutputValue>) throws -> SU) rethrows -> SignalChannel<InputValue, Input, U, SU> {
		return try SignalChannel<InputValue, Input, U, SU>(input: input, signal: compose(signal))
	}
	public func final<U>(_ compose: (Signal<OutputValue>) throws -> U) rethrows -> (input: Input, output: U) {
		return try (input, compose(signal))
	}
	public func consume(_ compose: (Signal<OutputValue>) throws -> ()) rethrows -> Input {
		try compose(signal)
		return input
	}
	public var tuple: (input: Input, signal: Output) { return (input: input, signal: signal) }
}

public typealias Channel<Value> = SignalChannel<Value, SignalInput<Value>, Value, Signal<Value>>
public typealias MultiChannel<Value> = SignalChannel<Value, SignalMultiInput<Value>, Value, Signal<Value>>
public typealias MergedChannel<Value> = SignalChannel<Value, SignalMergedInput<Value>, Value, Signal<Value>>

extension SignalChannel where IV == OV, I == SignalInput<IV>, O == Signal<OV> {
	// An empty Channel can be default constructed
	public init() {
		self.init(Signal<InputValue>.create())
	}
}

extension SignalChannel where InputValue == OutputValue, Input == SignalMultiInput<InputValue>, Output == Signal<OutputValue> {
	// An empty MultiChannel can be default constructed
	public init() {
		self.init(Signal<InputValue>.createMultiInput())
	}
}

extension SignalChannel where InputValue == OutputValue, Input == SignalMergedInput<InputValue>, Output == Signal<OutputValue> {
	// An empty MergedChannel can be default constructed
	public init() {
		self.init(Signal<InputValue>.createMergedInput())
	}
}

extension Signal {
	public static func channel() -> Channel<Value> {
		return Channel<Value>()
	}
	public static func multiChannel() -> MultiChannel<Value> {
		return MultiChannel<Value>()
	}
	public static func mergedChannel() -> MergedChannel<Value> {
		return MergedChannel<Value>()
	}
}

// Implementation of Signal.swift
extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribe(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> Bool) -> Input {
		return final { $0.subscribeAndKeepAlive(context: context, handler: handler) }.input
	}
	
	public func join(to: SignalInput<OutputValue>) -> Input {
		return final { $0.join(to: to) }.input
	}
	
	public func junction() -> (input: Input, junction: SignalJunction<OutputValue>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<OutputValue>, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(context: context, handler: handler) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<OutputValue>, SignalNext<U>) -> Void) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transform(initialState: initialState, context: context, handler: handler) }
	}
	
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(second: second, context: context, handler: handler) }
	}
	
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<OutputValue, U>, SignalNext<V>) -> Void) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combine(initialState: initialState, second: second, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<OutputValue, U, V>, SignalNext<W>) -> Void) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<OutputValue, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<OutputValue, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
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
	
	public func cacheUntilActive() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func multicast() -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.playback() }
	}
	
	public func customActivation(initialValues: Array<OutputValue> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<OutputValue>, _ cachedError: inout Error?, _ incoming: Result<OutputValue>) -> Void) -> SignalChannel<InputValue, Input, OutputValue, SignalMulti<OutputValue>> {
		return next { $0.customActivation(initialValues: initialValues, context: context, updater: updater) }
	}
	
	public func capture() -> (input: Input, capture: SignalCapture<OutputValue>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public func subscribeValues(context: Exec = .direct, handler: @escaping (OutputValue) -> Void) -> (input: Input, endpoint: SignalEndpoint<OutputValue>) {
		let tuple = final { $0.subscribeValues(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (OutputValue) -> Bool) -> Input {
		signal.subscribeValuesAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputValue, Input, U, Signal<U>>{
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue, SignalMergedInput<U>) -> ()) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, (Int, OutputValue?), Signal<(Int, OutputValue?)>> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func join(to: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> Input {
		signal.join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cancellableJoin(to: SignalMergedInput<OutputValue>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> (input: Input, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func join(to: SignalMultiInput<OutputValue>) -> Input {
		return final { $0.join(to: to) }.input
	}
	
	public func cancellableJoin(to: SignalMultiInput<OutputValue>) -> (input: Input, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func pollingEndpoint() -> (input: Input, endpoint: SignalPollingEndpoint<OutputValue>) {
		let tuple = final { SignalPollingEndpoint(signal: $0) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func toggle(initialState: Bool = false) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.toggle(initialState: initialState) }
	}
}

// Implementation of SignalReactive.swift
extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public func buffer<U>(boundaries: Signal<U>) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<U>(windows: Signal<Signal<U>>) -> SignalChannel<InputValue, Input, [OutputValue], Signal<[OutputValue]>> {
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
	
	public func filterMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U?) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.filterMap(context: context, processor) }
	}
	
	public func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) -> U?) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.filterMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.failableMap(context: context, processor) }
	}
	
	public func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) throws -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.failableMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) throws -> U?) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.failableFilterMap(context: context, processor) }
	}
	
	public func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, OutputValue) -> U?) throws -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.failableFilterMap(initialState: initialState, context: context, processor) }
	}
	
	public func flatMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U) -> SignalChannel<InputValue, Input, (U, Signal<OutputValue>), Signal<(U, Signal<OutputValue>)>> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<U>(boundaries: Signal<U>) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<U>(windows: Signal<Signal<U>>) -> SignalChannel<InputValue, Input, Signal<OutputValue>, Signal<Signal<OutputValue>>> {
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

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: Hashable {
	public func distinct() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinct() }
	}
	
	public func distinctUntilChanged() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (OutputValue, OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.distinctUntilChanged(context: context, comparator: comparator) }
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
	
	public func ignoreElements() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.ignoreElements() }
	}
	
	public func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalChannel<InputValue, Input, S.Iterator.Element, Signal<S.Iterator.Element>> {
		return next { $0.ignoreElements(endWith: endWith) }
	}
	
	public func ignoreElements<U>(endWith value: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.ignoreElements(endWith: value, conditional: conditional) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (OutputValue) -> Bool = { _ in true }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample(_ trigger: Signal<()>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.sample(trigger) }
	}
	
	public func sampleCombine<U>(_ trigger: Signal<U>) -> SignalChannel<InputValue, Input, (sample: OutputValue, trigger: U), Signal<(sample: OutputValue, trigger: U)>> {
		return next { $0.sampleCombine(trigger) }
	}
	
	public func latest<U>(_ source: Signal<U>) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.latest(source) }
	}
	
	public func latestCombine<U>(_ source: Signal<U>) -> SignalChannel<InputValue, Input, (trigger: OutputValue, sample: U), Signal<(trigger: OutputValue, sample: U)>> {
		return next { $0.latestCombine(source) }
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
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (OutputValue, U) -> V) -> SignalChannel<InputValue, Input, V, Signal<V>> {
		return next { $0.combineLatest(second: second, context: context, processor) }
	}
	
	public func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V) -> W) -> SignalChannel<InputValue, Input, W, Signal<W>> {
		return next { $0.combineLatest(second: second, third: third, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V, W) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (OutputValue, U, V, W, X) -> Y) -> SignalChannel<InputValue, Input, Y, Signal<Y>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor) }
	}
	
	public func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (OutputValue) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((OutputValue, U)) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (OutputValue) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((OutputValue, Signal<U>)) -> X) -> SignalChannel<InputValue, Input, X, Signal<X>> {
		return next { $0.groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
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
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where U.Iterator.Element == OutputValue {
		return next { $0.endWith(sequence, conditional: conditional) }
	}
	
	func endWith(_ value: OutputValue, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.endWith(value, conditional: conditional) }
	}
	
	public func zip<U>(second: Signal<U>) -> SignalChannel<InputValue, Input, (OutputValue, U), Signal<(OutputValue, U)>> {
		return next { $0.zip(second: second) }
	}
	
	public func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalChannel<InputValue, Input, (OutputValue, U, V), Signal<(OutputValue, U, V)>> {
		return next { $0.zip(second: second, third: third) }
	}
	
	public func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalChannel<InputValue, Input, (OutputValue, U, V, W), Signal<(OutputValue, U, V, W)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth) }
	}
	
	public func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalChannel<InputValue, Input, (OutputValue, U, V, W, X), Signal<(OutputValue, U, V, W, X)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth, fifth: fifth) }
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> where S.Iterator.Element == OutputValue {
		return next { $0.catchError(context: context, recover: recover) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
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
	
	public func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onActivate(context: context, handler: handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onDeactivate(context: context, handler: handler) }
	}
	
	public func onResult(context: Exec = .direct, handler: @escaping (Result<OutputValue>) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onResult(context: context, handler: handler) }
	}
	
	public func onValue(context: Exec = .direct, handler: @escaping (OutputValue) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onValue(context: context, handler: handler) }
	}
	
	public func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.onError(context: context, handler: handler) }
	}
	
	public func materialize() -> SignalChannel<InputValue, Input, Result<OutputValue>, Signal<Result<OutputValue>>> {
		return next { $0.materialize() }
	}
}


extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func timeInterval(context: Exec = .direct) -> SignalChannel<InputValue, Input, Double, Signal<Double>> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalChannel<InputValue, Input, (OutputValue, DispatchTime), Signal<(OutputValue, DispatchTime)>> {
		return next { $0.timestamp(context: context) }
	}
}


extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func all(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func some(context: Exec = .direct, test: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.some(context: context, test: test) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: Equatable {
	
	public func contains(value: OutputValue) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.contains(value: value) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func defaultIfEmpty(value: OutputValue) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<OutputValue>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: Equatable {
	
	public func sequenceEqual(to: Signal<OutputValue>) -> SignalChannel<InputValue, Input, Bool, Signal<Bool>> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func skipUntil<U>(_ other: Signal<U>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, OutputValue) -> Bool) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U>(_ other: Signal<U>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
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

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: BinaryInteger {
	
	public func average() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.average() }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	
	public func concat(_ other: Signal<OutputValue>) -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalChannel<InputValue, Input, Int, Signal<Int>> {
		return next { $0.count() }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: Comparable {
	
	public func min() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.min() }
	}
	
	public func max() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.max() }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue> {
	public func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, OutputValue) -> U) -> SignalChannel<InputValue, Input, U, Signal<U>> {
		return next { $0.reduce(initial, context: context, fold: fold) }
	}
}

extension SignalPair where Input: SignalInput<InputValue>, Output: Signal<OutputValue>, OutputValue: Numeric {
	public func sum() -> SignalChannel<InputValue, Input, OutputValue, Signal<OutputValue>> {
		return next { $0.sum() }
	}
}

// Implementation of Signal.swift
extension SignalInput {
	public static func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<Value>) -> Bool) -> SignalInput<Value> {
		return Channel().subscribeAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalInput<Value>) -> SignalInput<Value> {
		return Channel().join(to: to)
	}
	
	public static func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (Value) -> Bool) -> SignalInput<Value> {
		return Channel().subscribeValuesAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalMergedInput<Value>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SignalInput<Value> {
		return Channel().join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	public static func join(to: SignalMultiInput<Value>) -> SignalInput<Value> {
		return Channel().join(to: to)
	}
}

