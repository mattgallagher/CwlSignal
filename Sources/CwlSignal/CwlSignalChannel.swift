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

/// A basic wrapper around a `Signal` and an input which feeds input into it (usually a `SignalInput` but possibly also a `SignalMergedInput`, `SignalMultiInput`).
///
/// You don't generally hold onto a `SignalChannel`; it exists for syntactic convenience when building a series of pipeline stages.
/// e.g.:
///		let (input, signal) = Signal<Int>.channel().map { $0 + 1 }.pair
///
/// Every transform in the CwlSignal library that can be applied to `Signal<T>` can also be applied to `SignalChannel<T>`. Where possible, the result is another `SignalChannel` so the result can be immediately transformed again.
///
/// A `channel()` function exists in global scope to simplify syntax further in situations where the result type is already constrained:
///		someFunction(signalInput: channel().map { $0 + 1 }.join(to: multiInputChannelFromElsewhere))
///
/// For similar syntactic reasons, `SignalInput<T>` includes static versions of all of those `SignalChannel` methods where the result is either a `SignalInput<T>` or a `SignalChannel` where `I` remains unchanged.
/// e.g.:
///		someFunction(signalInput: .join(to: multiInputChannelFromElsewhere))
/// Unfortunately, due to limitations in Swift, this bare `SiganlInput` approach works only in those cases where the channel is a single stage ending in a `SignalInput<T>`.
public struct SignalPair<I, SI: SignalInput<I>, T, ST: Signal<T>> {
	public let input: SI
	public let signal: ST
	public init(input: SI, signal: ST) {
		self.input = input
		self.signal = signal
	}
	public init(_ tuple: (SI, ST)) {
		self.init(input: tuple.0, signal: tuple.1)
	}
	public func next<U, SU: Signal<U>>(_ compose: (Signal<T>) throws -> SU) rethrows -> SignalPair<I, SI, U, SU> {
		return try SignalPair<I, SI, U, SU>(input: input, signal: compose(signal))
	}
	public func final<U>(_ compose: (Signal<T>) throws -> U) rethrows -> (input: SI, output: U) {
		return try (input, compose(signal))
	}
	public func consume(_ compose: (Signal<T>) throws -> ()) rethrows -> SI {
		try compose(signal)
		return input
	}
}

public typealias Channel<T> = SignalPair<T, SignalInput<T>, T, Signal<T>>
public typealias MultiChannel<T> = SignalPair<T, SignalMultiInput<T>, T, Signal<T>>
public typealias Variable<T> = SignalPair<T, SignalMultiInput<T>, T, SignalMulti<T>>

extension SignalPair where I == T, SI == SignalInput<I>, ST == Signal<T> {
	public init() {
		self.init(Signal<I>.create())
	}
}

extension SignalPair where I == T, SI == SignalInput<I>, ST == SignalMulti<T> {
	public init(continuous: Bool = true) {
		let c = Channel<T>()
		self = continuous ? c.continuous() : c.multicast()
	}
	public init(initialValue: T) {
		self = Channel<T>().continuous(initialValue: initialValue)
	}
}

extension SignalPair where I == T, SI == SignalMultiInput<I>, ST == Signal<T> {
	public init() {
		self.init(Signal<I>.createMultiInput())
	}
}

extension SignalPair where I == T, SI == SignalMultiInput<I>, ST == SignalMulti<T> {
	public init(continuous: Bool = true) {
		let c = MultiChannel<T>()
		self = continuous ? c.continuous() : c.multicast()
	}
	public init(initialValue: T) {
		self = MultiChannel<T>().continuous(initialValue: initialValue)
	}
}

// Implementation of Signal.swift
extension SignalPair {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> (input: SI, endpoint: SignalEndpoint<T>) {
		let tuple = final { $0.subscribe(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> SI {
		return final { $0.subscribeAndKeepAlive(context: context, handler: handler) }.input
	}
	
	public func join(to: SignalInput<T>) -> SI {
		return final { $0.join(to: to) }.input
	}
	
	public func junction() -> (input: SI, junction: SignalJunction<T>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<T>, SignalNext<U>) -> Void) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.transform(context: context, handler: handler) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.transform(initialState: initialState, context: context, handler: handler) }
	}
	
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalPair<I, SI, V, Signal<V>> {
		return next { $0.combine(second: second, context: context, handler: handler) }
	}
	
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalPair<I, SI, W, Signal<W>> {
		return next { $0.combine(second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalPair<I, SI, X, Signal<X>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalPair<I, SI, Y, Signal<Y>> {
		return next { $0.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalPair<I, SI, V, Signal<V>> {
		return next { $0.combine(initialState: initialState, second: second, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalPair<I, SI, W, Signal<W>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalPair<I, SI, X, Signal<X>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalPair<I, SI, Y, Signal<Y>> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func continuous(initialValue: T) -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.continuous(initialValue: initialValue) }
	}
	
	public func continuous() -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.continuous() }
	}
	
	public func continuousWhileActive() -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.continuousWhileActive() }
	}
	
	public func playback() -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.playback() }
	}
	
	public func cacheUntilActive() -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.playback() }
	}
	
	public func multicast() -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.playback() }
	}
	
	public func customActivation(initialValues: Array<T> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<T>, _ cachedError: inout Error?, _ incoming: Result<T>) -> Void) -> SignalPair<I, SI, T, SignalMulti<T>> {
		return next { $0.customActivation(initialValues: initialValues, context: context, updater: updater) }
	}
	
	public func capture() -> (input: SI, capture: SignalCapture<T>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalPair {
	public func subscribeValues(context: Exec = .direct, handler: @escaping (T) -> Void) -> (input: SI, endpoint: SignalEndpoint<T>) {
		let tuple = final { $0.subscribeValues(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (T) -> Bool) -> SI {
		signal.subscribeValuesAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergedInput<U>) -> ()) -> SignalPair<I, SI, U, Signal<U>>{
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergedInput<U>) -> ()) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, (Int, T?), Signal<(Int, T?)>> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> SignalPair<I, SI, (Int, T?), Signal<(Int, T?)>> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func join(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SI {
		signal.join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cancellableJoin(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> (input: SI, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func join(to: SignalMultiInput<T>) -> SI {
		return final { $0.join(to: to) }.input
	}
	
	public func cancellableJoin(to: SignalMultiInput<T>) -> (input: SI, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func pollingEndpoint() -> (input: SI, endpoint: SignalPollingEndpoint<T>) {
		let tuple = final { SignalPollingEndpoint(signal: $0) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func toggle(initialState: Bool = false) -> SignalPair<I, SI, Bool, Signal<Bool>> {
		return next { $0.toggle(initialState: initialState) }
	}
}

// Implementation of SignalReactive.swift
extension SignalPair {
	public func buffer<U>(boundaries: Signal<U>) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<U>(windows: Signal<Signal<U>>) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(windows: windows) }
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(count: count, skip: skip) }
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func buffer(count: UInt) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(count: count, skip: count) }
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<I, SI, [T], Signal<[T]>> {
		return next { $0.buffer(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func filterMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> U?) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.filterMap(context: context, processor) }
	}
	
	public func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.filterMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.failableMap(context: context, processor) }
	}
	
	public func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) throws -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.failableMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U?) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.failableFilterMap(context: context, processor) }
	}
	
	public func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) throws -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.failableFilterMap(initialState: initialState, context: context, processor) }
	}
	
	public func flatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalPair<I, SI, (U, Signal<T>), Signal<(U, Signal<T>)>> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, T) -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<U>(boundaries: Signal<U>) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<U>(windows: Signal<Signal<U>>) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(windows: windows) }
	}
	
	public func window(count: UInt, skip: UInt) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(count: count, skip: skip) }
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func window(count: UInt) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(count: count, skip: count) }
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<I, SI, Signal<T>, Signal<Signal<T>>> {
		return next { $0.window(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.debounce(interval: interval, flushOnClose: flushOnClose, context: context) }
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.throttleFirst(interval: interval, context: context) }
	}
}

extension SignalPair where T: Hashable {
	public func distinct() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.distinct() }
	}
	
	public func distinctUntilChanged() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalPair {
	public func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (T, T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.distinctUntilChanged(context: context, comparator: comparator) }
	}
	
	public func elementAt(_ index: UInt) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.elementAt(index) }
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.filter(context: context, matching: matching) }
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.ofType(type) }
	}
	
	public func first(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.first(context: context, matching: matching) }
	}
	
	public func single(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.single(context: context, matching: matching) }
	}
	
	public func ignoreElements() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.ignoreElements() }
	}
	
	public func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalPair<I, SI, S.Iterator.Element, Signal<S.Iterator.Element>> {
		return next { $0.ignoreElements(endWith: endWith) }
	}
	
	public func ignoreElements<U>(endWith value: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.ignoreElements(endWith: value, conditional: conditional) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample(_ trigger: Signal<()>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.sample(trigger) }
	}
	
	public func sampleCombine<U>(_ trigger: Signal<U>) -> SignalPair<I, SI, (sample: T, trigger: U), Signal<(sample: T, trigger: U)>> {
		return next { $0.sampleCombine(trigger) }
	}
	
	public func latest<U>(_ source: Signal<U>) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.latest(source) }
	}
	
	public func latestCombine<U>(_ source: Signal<U>) -> SignalPair<I, SI, (trigger: T, sample: U), Signal<(trigger: T, sample: U)>> {
		return next { $0.latestCombine(source) }
	}
	
	public func skip(_ count: Int) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.skip(count) }
	}
	
	public func skipLast(_ count: Int) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.skipLast(count) }
	}
	
	public func take(_ count: Int) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.take(count) }
	}
	
	public func takeLast(_ count: Int) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.takeLast(count) }
	}
}

extension SignalPair {
	
	public func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (T, U) -> V) -> SignalPair<I, SI, V, Signal<V>> {
		return next { $0.combineLatest(second: second, context: context, processor) }
	}
	
	public func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (T, U, V) -> W) -> SignalPair<I, SI, W, Signal<W>> {
		return next { $0.combineLatest(second: second, third: third, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (T, U, V, W) -> X) -> SignalPair<I, SI, X, Signal<X>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (T, U, V, W, X) -> Y) -> SignalPair<I, SI, Y, Signal<Y>> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor) }
	}
	
	public func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, U)) -> X) -> SignalPair<I, SI, X, Signal<X>> {
		return next { $0.join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, Signal<U>)) -> X) -> SignalPair<I, SI, X, Signal<X>> {
		return next { $0.groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func mergeWith(_ sources: Signal<T>...) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.mergeWith(sources) }
	}
	
	public func mergeWith<S: Sequence>(_ sequence: S) -> SignalPair<I, SI, T, Signal<T>> where S.Iterator.Element == Signal<T> {
		return next { $0.mergeWith(sequence) }
	}
	
	public func startWith<S: Sequence>(_ sequence: S) -> SignalPair<I, SI, T, Signal<T>> where S.Iterator.Element == T {
		return next { $0.startWith(sequence) }
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<I, SI, T, Signal<T>> where U.Iterator.Element == T {
		return next { $0.endWith(sequence, conditional: conditional) }
	}
	
	func endWith(_ value: T, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.endWith(value, conditional: conditional) }
	}
	
	public func zip<U>(second: Signal<U>) -> SignalPair<I, SI, (T, U), Signal<(T, U)>> {
		return next { $0.zip(second: second) }
	}
	
	public func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalPair<I, SI, (T, U, V), Signal<(T, U, V)>> {
		return next { $0.zip(second: second, third: third) }
	}
	
	public func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalPair<I, SI, (T, U, V, W), Signal<(T, U, V, W)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth) }
	}
	
	public func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalPair<I, SI, (T, U, V, W, X), Signal<(T, U, V, W, X)>> {
		return next { $0.zip(second: second, third: third, fourth: fourth, fifth: fifth) }
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalPair<I, SI, T, Signal<T>> where S.Iterator.Element == T {
		return next { $0.catchError(context: context, recover: recover) }
	}
}

extension SignalPair {
	public func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<T>?) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.retry(initialState, context: context, shouldRetry: shouldRetry) }
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.retry(count: count, delayInterval: delayInterval, context: context) }
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, T) -> DispatchTimeInterval) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.delay(interval: interval, context: context) }
	}
	
	public func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (T) -> Signal<U>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.delay(closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, T) -> Signal<U>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.onActivate(context: context, handler: handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.onDeactivate(context: context, handler: handler) }
	}
	
	public func onResult(context: Exec = .direct, handler: @escaping (Result<T>) -> ()) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.onResult(context: context, handler: handler) }
	}
	
	public func onValue(context: Exec = .direct, handler: @escaping (T) -> ()) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.onValue(context: context, handler: handler) }
	}
	
	public func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.onError(context: context, handler: handler) }
	}
	
	public func materialize() -> SignalPair<I, SI, Result<T>, Signal<Result<T>>> {
		return next { $0.materialize() }
	}
}


extension SignalPair {
	
	public func timeInterval(context: Exec = .direct) -> SignalPair<I, SI, Double, Signal<Double>> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalPair<I, SI, (T, DispatchTime), Signal<(T, DispatchTime)>> {
		return next { $0.timestamp(context: context) }
	}
}


extension SignalPair {
	
	public func all(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalPair<I, SI, Bool, Signal<Bool>> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func some(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalPair<I, SI, Bool, Signal<Bool>> {
		return next { $0.some(context: context, test: test) }
	}
}

extension SignalPair where T: Equatable {
	
	public func contains(value: T) -> SignalPair<I, SI, Bool, Signal<Bool>> {
		return next { $0.contains(value: value) }
	}
}

extension SignalPair {
	
	public func defaultIfEmpty(value: T) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<T>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalPair where T: Equatable {
	
	public func sequenceEqual(to: Signal<T>) -> SignalPair<I, SI, Bool, Signal<Bool>> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalPair {
	
	public func skipUntil<U>(_ other: Signal<U>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U>(_ other: Signal<U>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.takeUntil(other) }
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.takeWhile(context: context, condition: condition) }
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.takeWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, T) -> V) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold) }
	}
}

extension SignalPair where T: BinaryInteger {
	
	public func average() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.average() }
	}
}

extension SignalPair {
	
	public func concat(_ other: Signal<T>) -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalPair<I, SI, Int, Signal<Int>> {
		return next { $0.count() }
	}
}

extension SignalPair where T: Comparable {
	
	public func min() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.min() }
	}
	
	public func max() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.max() }
	}
}

extension SignalPair {
	
	public func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, T) -> U) -> SignalPair<I, SI, U, Signal<U>> {
		return next { $0.reduce(initial, context: context, fold: fold) }
	}
}

extension SignalPair where T: Numeric {
	
	public func sum() -> SignalPair<I, SI, T, Signal<T>> {
		return next { $0.sum() }
	}
}

// Implementation of Signal.swift
extension SignalInput {
	public static func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> SignalInput<T> {
		return Channel().subscribeAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalInput<T>) -> SignalInput<T> {
		return Channel().join(to: to)
	}
	
	public static func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) -> SignalInput<T> {
		return Channel().subscribeValuesAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SignalInput<T> {
		return Channel().join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	public static func join(to: SignalMultiInput<T>) -> SignalInput<T> {
		return Channel().join(to: to)
	}
}

