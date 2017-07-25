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
public struct SignalChannel<I, T> {
	public typealias InputType = I
	public typealias ValueType = T
	public let input: I
	public let signal: Signal<T>
	public init(input: I, signal: Signal<T>) {
		self.input = input
		self.signal = signal
	}
	public init(_ tuple: (I, Signal<T>)) {
		self.init(input: tuple.0, signal: tuple.1)
	}
	public func next<U>(_ compose: (Signal<T>) throws -> Signal<U>) rethrows -> SignalChannel<I, U> {
		return try SignalChannel<I, U>(input: input, signal: compose(signal))
	}
	public func final<U>(_ compose: (Signal<T>) throws -> U) rethrows -> (input: I, output: U) {
		return try (input, compose(signal))
	}
	public var pair: (input: I, signal: Signal<T>) { return (input, signal) }
}

public func channel<T>() -> SignalChannel<SignalInput<T>, T> {
	return SignalChannel<SignalInput<T>, T>(Signal<T>.create())
}

extension Signal {
	public static func channel() -> SignalChannel<SignalInput<T>, T> {
		return SignalChannel<SignalInput<T>, T>(Signal<T>.create())
	}
	public static func multiChannel() -> SignalChannel<SignalMultiInput<T>, T> {
		return SignalChannel<SignalMultiInput<T>, T>(Signal<T>.createMultiInput())
	}
	public static func mergedChannel() -> SignalChannel<SignalMergedInput<T>, T> {
		return SignalChannel<SignalMergedInput<T>, T>(Signal<T>.createMergedInput())
	}
	public static func variable() -> (input: SignalMultiInput<T>, signal: SignalMulti<T>) {
		return SignalChannel<SignalMultiInput<T>, T>(Signal<T>.createMultiInput()).continuous()
	}
	public static func variable(initialValue: T) -> (input: SignalMultiInput<T>, signal: SignalMulti<T>) {
		return SignalChannel<SignalMultiInput<T>, T>(Signal<T>.createMultiInput()).continuous(initialValue: initialValue)
	}
}

// Implementation of Signal.swift
extension SignalChannel {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> (input: I, endpoint: SignalEndpoint<T>) {
		let tuple = final { $0.subscribe(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> I {
		return final { $0.subscribeAndKeepAlive(context: context, handler: handler) }.input
	}
	
	public func join(to: SignalInput<T>) -> I {
		return final { $0.join(to: to) }.input
	}
	
	public func junction() -> (input: I, junction: SignalJunction<T>) {
		let tuple = final { $0.junction() }
		return (input: tuple.input, junction: tuple.output)
	}
	
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<T>, SignalNext<U>) -> Void) -> SignalChannel<I, U> {
		return next { $0.transform(context: context, handler: handler) }
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) -> SignalChannel<I, U> {
		return next { $0.transform(initialState: initialState, context: context, handler: handler) }
	}
	
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<I, V> {
		return next { $0.combine(second: second, context: context, handler: handler) }
	}
	
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<I, W> {
		return next { $0.combine(second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<I, X> {
		return next { $0.combine(second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<I, Y> {
		return next { $0.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<I, V> {
		return next { $0.combine(initialState: initialState, second: second, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<I, W> {
		return next { $0.combine(initialState: initialState, second: second, third: third, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<I, X> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler) }
	}
	
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<I, Y> {
		return next { $0.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler) }
	}
	
	public func continuous(initialValue: T) -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.continuous(initialValue: initialValue) }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func continuous() -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.continuous() }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func continuousWhileActive() -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.continuousWhileActive() }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func playback() -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.playback() }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func cacheUntilActive() -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.playback() }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func multicast() -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.playback() }
		return (input: tuple.input, signal: tuple.output)
	}
	
	public func capture() -> (input: I, capture: SignalCapture<T>) {
		let tuple = final { $0.capture() }
		return (input: tuple.input, capture: tuple.output)
	}
	
	public func customActivation(initialValues: Array<T> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<T>, _ cachedError: inout Error?, _ incoming: Result<T>) -> Void) -> (input: I, signal: SignalMulti<T>) {
		let tuple = final { $0.customActivation(initialValues: initialValues, context: context, updater: updater) }
		return (input: tuple.input, signal: tuple.output)
	}
}

// Implementation of SignalExtensions.swift
extension SignalChannel {
	public func subscribeValues(context: Exec = .direct, handler: @escaping (T) -> Void) -> (input: I, endpoint: SignalEndpoint<T>) {
		let tuple = final { $0.subscribeValues(context: context, handler: handler) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) -> I {
		signal.subscribeValuesAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<I, T> {
		return next { $0.stride(count: count, initialSkip: initialSkip) }
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergedInput<U>) -> ()) -> SignalChannel<I, U> {
		return next { $0.transformFlatten(closePropagation: closePropagation, context: context, processor) }
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergedInput<U>) -> ()) -> SignalChannel<I, U> {
		return next { $0.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor) }
	}
	
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> SignalChannel<I, (Int, T?)> {
		return next { $0.valueDurations(closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, (Int, T?)> {
		return next { $0.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration) }
	}
	
	public func join(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> I {
		signal.join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cancellableJoin(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> (input: I, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func join(to: SignalMultiInput<T>) -> I {
		return final { $0.join(to: to) }.input
	}
	
	public func cancellableJoin(to: SignalMultiInput<T>) -> (input: I, cancellable: Cancellable) {
		let tuple = final { $0.cancellableJoin(to: to) }
		return (input: tuple.input, cancellable: tuple.output)
	}
	
	public func pollingEndpoint() -> (input: I, endpoint: SignalPollingEndpoint<T>) {
		let tuple = final { SignalPollingEndpoint(signal: $0) }
		return (input: tuple.input, endpoint: tuple.output)
	}
	
	public func toggle(initialState: Bool = false) -> (input: I, signal: SignalMulti<Bool>) {
		let tuple = final { $0.toggle(initialState: initialState) }
		return (input: tuple.input, signal: tuple.output)
	}
}

// Implementation of SignalReactive.swift
extension SignalChannel {
	public func buffer<U>(boundaries: Signal<U>) -> SignalChannel<I, [T]> {
		return next { $0.buffer(boundaries: boundaries) }
	}
	
	public func buffer<U>(windows: Signal<Signal<U>>) -> SignalChannel<I, [T]> {
		return next { $0.buffer(windows: windows) }
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalChannel<I, [T]> {
		return next { $0.buffer(count: count, skip: skip) }
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<I, [T]> {
		return next { $0.buffer(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func buffer(count: UInt) -> SignalChannel<I, [T]> {
		return next { $0.buffer(count: count, skip: count) }
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, [T]> {
		return next { $0.buffer(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func filterMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> U?) -> SignalChannel<I, U> {
		return next { $0.filterMap(context: context, processor) }
	}
	
	public func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) -> SignalChannel<I, U> {
		return next { $0.filterMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U) -> SignalChannel<I, U> {
		return next { $0.failableMap(context: context, processor) }
	}
	
	public func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) throws -> U) -> SignalChannel<I, U> {
		return next { $0.failableMap(initialState: initialState, context: context, processor) }
	}
	
	public func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U?) -> SignalChannel<I, U> {
		return next { $0.failableFilterMap(context: context, processor) }
	}
	
	public func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) throws -> SignalChannel<I, U> {
		return next { $0.failableFilterMap(initialState: initialState, context: context, processor) }
	}
	
	public func flatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return next { $0.flatMap(context: context, processor) }
	}
	
	public func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return next { $0.flatMapFirst(context: context, processor) }
	}
	
	public func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return next { $0.flatMapLatest(context: context, processor) }
	}
	
	public func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, U> {
		return next { $0.flatMap(initialState: initialState, context: context, processor) }
	}
	
	public func concatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return next { $0.concatMap(context: context, processor) }
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<I, (U, Signal<T>)> {
		return next { $0.groupBy(context: context, processor) }
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<I, U> {
		return next { $0.map(context: context, processor) }
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> U) -> SignalChannel<I, U> {
		return next { $0.map(initialState: initialState, context: context, processor) }
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, T) -> U) -> SignalChannel<I, U> {
		return next { $0.scan(initialState: initialState, context: context, processor) }
	}
	
	public func window<U>(boundaries: Signal<U>) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(boundaries: boundaries) }
	}
	
	public func window<U>(windows: Signal<Signal<U>>) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(windows: windows) }
	}
	
	public func window(count: UInt, skip: UInt) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(count: count, skip: skip) }
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(interval: interval, count: count, continuous: continuous, context: context) }
	}
	
	public func window(count: UInt) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(count: count, skip: count) }
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, Signal<T>> {
		return next { $0.window(interval: interval, timeshift: timeshift, context: context) }
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalChannel<I, T> {
		return next { $0.debounce(interval: interval, flushOnClose: flushOnClose, context: context) }
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return next { $0.throttleFirst(interval: interval, context: context) }
	}
}

extension SignalChannel where T: Hashable {
	public func distinct() -> SignalChannel<I, T> {
		return next { $0.distinct() }
	}
	
	public func distinctUntilChanged() -> SignalChannel<I, T> {
		return next { $0.distinctUntilChanged() }
	}
}

extension SignalChannel {
	public func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (T, T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.distinctUntilChanged(context: context, comparator: comparator) }
	}
	
	public func elementAt(_ index: UInt) -> SignalChannel<I, T> {
		return next { $0.elementAt(index) }
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.filter(context: context, matching: matching) }
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalChannel<I, U> {
		return next { $0.ofType(type) }
	}
	
	public func first(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return next { $0.first(context: context, matching: matching) }
	}
	
	public func single(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return next { $0.single(context: context, matching: matching) }
	}
	
	public func ignoreElements() -> SignalChannel<I, T> {
		return next { $0.ignoreElements() }
	}
	
	public func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalChannel<I, S.Iterator.Element> {
		return next { $0.ignoreElements(endWith: endWith) }
	}
	
	public func ignoreElements<U>(endWith value: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<I, U> {
		return next { $0.ignoreElements(endWith: value, conditional: conditional) }
	}
	
	public func last(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return next { $0.last(context: context, matching: matching) }
	}
	
	public func sample(_ trigger: Signal<()>) -> SignalChannel<I, T> {
		return next { $0.sample(trigger) }
	}
	
	public func sampleCombine<U>(_ trigger: Signal<U>) -> SignalChannel<I, (sample: T, trigger: U)> {
		return next { $0.sampleCombine(trigger) }
	}
	
	public func latest<U>(_ source: Signal<U>) -> SignalChannel<I, U> {
		return next { $0.latest(source) }
	}
	
	public func latestCombine<U>(_ source: Signal<U>) -> SignalChannel<I, (trigger: T, sample: U)> {
		return next { $0.latestCombine(source) }
	}
	
	public func skip(_ count: Int) -> SignalChannel<I, T> {
		return next { $0.skip(count) }
	}
	
	public func skipLast(_ count: Int) -> SignalChannel<I, T> {
		return next { $0.skipLast(count) }
	}
	
	public func take(_ count: Int) -> SignalChannel<I, T> {
		return next { $0.take(count) }
	}
	
	public func takeLast(_ count: Int) -> SignalChannel<I, T> {
		return next { $0.takeLast(count) }
	}
}


extension SignalChannel {
	
	public func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (T, U) -> V) -> SignalChannel<I, V> {
		return next { $0.combineLatest(second: second, context: context, processor) }
	}
	
	public func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (T, U, V) -> W) -> SignalChannel<I, W> {
		return next { $0.combineLatest(second: second, third: third, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (T, U, V, W) -> X) -> SignalChannel<I, X> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, context: context, processor) }
	}
	
	public func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (T, U, V, W, X) -> Y) -> SignalChannel<I, Y> {
		return next { $0.combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor) }
	}
	
	public func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, U)) -> X) -> SignalChannel<I, X> {
		return next { $0.join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, Signal<U>)) -> X) -> SignalChannel<I, X> {
		return next { $0.groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor) }
	}
	
	public func mergeWith(_ sources: Signal<T>...) -> SignalChannel<I, T> {
		return next { $0.mergeWith(sources) }
	}
	
	public func mergeWith<S: Sequence>(_ sequence: S) -> SignalChannel<I, T> where S.Iterator.Element == Signal<T> {
		return next { $0.mergeWith(sequence) }
	}
	
	public func startWith<S: Sequence>(_ sequence: S) -> SignalChannel<I, T> where S.Iterator.Element == T {
		return next { $0.startWith(sequence) }
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<I, T> where U.Iterator.Element == T {
		return next { $0.endWith(sequence, conditional: conditional) }
	}
	
	func endWith(_ value: T, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<I, T> {
		return next { $0.endWith(value, conditional: conditional) }
	}
	
	public func zip<U>(second: Signal<U>) -> SignalChannel<I, (T, U)> {
		return next { $0.zip(second: second) }
	}
	
	public func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalChannel<I, (T, U, V)> {
		return next { $0.zip(second: second, third: third) }
	}
	
	public func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalChannel<I, (T, U, V, W)> {
		return next { $0.zip(second: second, third: third, fourth: fourth) }
	}
	
	public func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalChannel<I, (T, U, V, W, X)> {
		return next { $0.zip(second: second, third: third, fourth: fourth, fifth: fifth) }
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalChannel<I, T> where S.Iterator.Element == T {
		return next { $0.catchError(context: context, recover: recover) }
	}
}

extension SignalChannel {
	public func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<T>?) -> SignalChannel<I, T> {
		return next { $0.catchError(context: context, recover: recover) }
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalChannel<I, T> {
		return next { $0.retry(initialState, context: context, shouldRetry: shouldRetry) }
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return next { $0.retry(count: count, delayInterval: delayInterval, context: context) }
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, T) -> DispatchTimeInterval) -> SignalChannel<I, T> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return next { $0.delay(interval: interval, context: context) }
	}
	
	public func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (T) -> Signal<U>) -> SignalChannel<I, T> {
		return next { $0.delay(closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, T> {
		return next { $0.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset) }
	}
	
	public func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<I, T> {
		return next { $0.onActivate(context: context, handler: handler) }
	}
	
	public func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<I, T> {
		return next { $0.onDeactivate(context: context, handler: handler) }
	}
	
	public func onResult(context: Exec = .direct, handler: @escaping (Result<T>) -> ()) -> SignalChannel<I, T> {
		return next { $0.onResult(context: context, handler: handler) }
	}
	
	public func onValue(context: Exec = .direct, handler: @escaping (T) -> ()) -> SignalChannel<I, T> {
		return next { $0.onValue(context: context, handler: handler) }
	}
	
	public func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalChannel<I, T> {
		return next { $0.onError(context: context, handler: handler) }
	}
	
	public func materialize() -> SignalChannel<I, Result<T>> {
		return next { $0.materialize() }
	}
}


extension SignalChannel {
	
	public func timeInterval(context: Exec = .direct) -> SignalChannel<I, Double> {
		return next { $0.timeInterval(context: context) }
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<I, T> {
		return next { $0.timeout(interval: interval, resetOnValue: resetOnValue, context: context) }
	}
	
	public func timestamp(context: Exec = .direct) -> SignalChannel<I, (T, DispatchTime)> {
		return next { $0.timestamp(context: context) }
	}
}


extension SignalChannel {
	
	public func all(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<I, Bool> {
		return next { $0.all(context: context, test: test) }
	}
	
	public func some(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<I, Bool> {
		return next { $0.some(context: context, test: test) }
	}
}

extension SignalChannel where T: Equatable {
	
	public func contains(value: T) -> SignalChannel<I, Bool> {
		return next { $0.contains(value: value) }
	}
}

extension SignalChannel {
	
	public func defaultIfEmpty(value: T) -> SignalChannel<I, T> {
		return next { $0.defaultIfEmpty(value: value) }
	}
	
	public func switchIfEmpty(alternate: Signal<T>) -> SignalChannel<I, T> {
		return next { $0.switchIfEmpty(alternate: alternate) }
	}
}

extension SignalChannel where T: Equatable {
	
	public func sequenceEqual(to: Signal<T>) -> SignalChannel<I, Bool> {
		return next { $0.sequenceEqual(to: to) }
	}
}

extension SignalChannel {
	
	public func skipUntil<U>(_ other: Signal<U>) -> SignalChannel<I, T> {
		return next { $0.skipUntil(other) }
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.skipWhile(context: context, condition: condition) }
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.skipWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func takeUntil<U>(_ other: Signal<U>) -> SignalChannel<I, T> {
		return next { $0.takeUntil(other) }
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.takeWhile(context: context, condition: condition) }
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<I, T> {
		return next { $0.takeWhile(initialState: initial, context: context, condition: condition) }
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, T) -> V) -> SignalChannel<I, U> {
		return next { $0.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold) }
	}
}

extension SignalChannel where T: BinaryInteger {
	
	public func average() -> SignalChannel<I, T> {
		return next { $0.average() }
	}
}

extension SignalChannel {
	
	public func concat(_ other: Signal<T>) -> SignalChannel<I, T> {
		return next { $0.concat(other) }
	}
	
	public func count() -> SignalChannel<I, Int> {
		return next { $0.count() }
	}
}

extension SignalChannel where T: Comparable {
	
	public func min() -> SignalChannel<I, T> {
		return next { $0.min() }
	}
	
	public func max() -> SignalChannel<I, T> {
		return next { $0.max() }
	}
}

extension SignalChannel {
	
	public func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, T) -> U) -> SignalChannel<I, U> {
		return next { $0.reduce(initial, context: context, fold: fold) }
	}
}

extension SignalChannel where T: Numeric {
	
	public func sum() -> SignalChannel<I, T> {
		return next { $0.sum() }
	}
}

// Implementation of Signal.swift
extension SignalInput {
	public static func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> SignalInput<T> {
		return Signal<T>.channel().subscribeAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalInput<T>) -> SignalInput<T> {
		return Signal<T>.channel().join(to: to)
	}
	
	public static func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) -> SignalInput<T> {
		return Signal<T>.channel().subscribeValuesAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalMergedInput<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SignalInput<T> {
		return Signal<T>.channel().join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	public static func join(to: SignalMultiInput<T>) -> SignalInput<T> {
		return Signal<T>.channel().join(to: to)
	}
}

