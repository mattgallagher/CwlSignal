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

/// A basic wrapper around a `Signal` and an input which feeds input into it (usually a `SignalInput` but possibly also a `SignalMergeSet`, `SignalCollector`).
///
/// You don't generally hold onto a `SignalChannel`; it exists for syntactic convenience when building a series of pipeline stages.
/// e.g.:
///		let (input, signal) = Signal<Int>.channel().map { $0 + 1 }.pair
///
/// Every transform in the CwlSignal library that can be applied to `Signal<T>` can also be applied to `SignalChannel<T>`. Where possible, the result is another `SignalChannel`.
///
/// For similar syntactic reasons, `SignalInput<T>` includes static versions of all of those `SignalChannel` methods where the result is either a `SignalInput<T>` or a `SignalChannel` where `I` remains unchanged.
/// e.g.:
///		someFunctionRequiringASignalInput(.map { $0 + 1 }.join(to: collectorFromElsewhere))
/// can be used to return a `SignalInput` matching the parameter and have it pass into a map function and join to a pre-existing collector.
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
		self.input = tuple.0
		self.signal = tuple.1
	}
	public func nextStage<U>(_ signal: Signal<U>) -> SignalChannel<I, U> {
		return SignalChannel<I, U>(input: input, signal: signal)
	}
	
	// 
	public var pair: (I, Signal<T>) { return (input, signal) }
}

extension Signal {
	public static func channel() -> SignalChannel<SignalInput<T>, T> {
		return SignalChannel<SignalInput<T>, T>(Signal<T>.create())
	}
	public static func mergeSetChannel<S: Sequence>(_ initialInputs: S, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) -> SignalChannel<SignalMergeSet<T>, T> where S.Iterator.Element: Signal<T> {
		return SignalChannel<SignalMergeSet<T>, T>(Signal<T>.createMergeSet(initialInputs, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate))
	}
	public static func mergeSetChannel() -> SignalChannel<SignalMergeSet<T>, T> {
		return SignalChannel<SignalMergeSet<T>, T>(Signal<T>.createMergeSet())
	}
	public static func collectorChannel() -> SignalChannel<SignalCollector<T>, T> {
		return SignalChannel<SignalCollector<T>, T>(Signal<T>.createCollector())
	}
}

// Implementation of Signal.swift
extension SignalChannel {
	public func subscribe(context: Exec = .direct, handler: @escaping (Result<T>) -> Void) -> (I, SignalEndpoint<T>) {
		return (input, signal.subscribe(context: context, handler: handler))
	}
	
	public func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> I {
		signal.subscribeAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func join(to: SignalInput<T>) throws -> I {
		try signal.join(to: to)
		return input
	}
	
	public func join(to: SignalInput<T>, onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) throws -> I {
		try signal.join(to: to, onError: onError)
		return input
	}
	
	public func junction() -> (I, SignalJunction<T>) {
		return (input, signal.junction())
	}
	
	public func junctionSignal() -> SignalChannel<(I, SignalJunction<T>), T> {
		let (junction, s) = signal.junctionSignal()
		return SignalChannel<(I, SignalJunction<T>), T>(input: (input, junction), signal: s)
	}
	
	public func junctionSignal(onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) -> SignalChannel<(I, SignalJunction<T>), T> {
		let (junction, s) = signal.junctionSignal(onError: onError)
		return SignalChannel<(I, SignalJunction<T>), T>(input: (input, junction), signal: s)
	}
	
	public func transform<U>(context: Exec = .direct, handler: @escaping (Result<T>, SignalNext<U>) -> Void) -> SignalChannel<I, U> {
		return nextStage(signal.transform(context: context, handler: handler))
	}
	
	public func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) -> SignalChannel<I, U> {
		return nextStage(signal.transform(initialState: initialState, context: context, handler: handler))
	}
	
	public func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<I, V> {
		return nextStage(signal.combine(second: second, context: context, handler: handler))
	}
	
	public func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<I, W> {
		return nextStage(signal.combine(second: second, third: third, context: context, handler: handler))
	}
	
	public func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<I, X> {
		return nextStage(signal.combine(second: second, third: third, fourth: fourth, context: context, handler: handler))
	}
	
	public func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<I, Y> {
		return nextStage(signal.combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler))
	}
	
	public func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<I, V> {
		return nextStage(signal.combine(initialState: initialState, second: second, context: context, handler: handler))
	}
	
	public func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<I, W> {
		return nextStage(signal.combine(initialState: initialState, second: second, third: third, context: context, handler: handler))
	}
	
	public func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<I, X> {
		return nextStage(signal.combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler))
	}
	
	public func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<I, Y> {
		return nextStage(signal.combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler))
	}
	
	public func continuous(initialValue: T) -> (I, SignalMulti<T>) {
		return (input, signal.continuous(initialValue: initialValue))
	}
	
	public func continuous() -> (I, SignalMulti<T>) {
		return (input, signal.continuous())
	}
	
	public func continuousWhileActive() -> (I, SignalMulti<T>) {
		return (input, signal.continuousWhileActive())
	}
	
	public func playback() -> (I, SignalMulti<T>) {
		return (input, signal.playback())
	}
	
	public func cacheUntilActive() -> (I, SignalMulti<T>) {
		return (input, signal.playback())
	}
	
	public func multicast() -> (I, SignalMulti<T>) {
		return (input, signal.playback())
	}
	
	public func capture() -> (I, SignalCapture<T>) {
		return (input, signal.capture())
	}
	
	public func customActivation(initialValues: Array<T> = [], context: Exec = .direct, updater: @escaping (_ cachedValues: inout Array<T>, _ cachedError: inout Error?, _ incoming: Result<T>) -> Void) -> (I, SignalMulti<T>) {
		return (input, signal.customActivation(initialValues: initialValues, context: context, updater: updater))
	}
}

// Implementation of SignalExtensions.swift
extension SignalChannel {
	public func subscribeValues(context: Exec = .direct, handler: @escaping (T) -> Void) -> (I, SignalEndpoint<T>) {
		return (input, signal.subscribeValues(context: context, handler: handler))
	}
	
	public func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) -> I {
		signal.subscribeValuesAndKeepAlive(context: context, handler: handler)
		return input
	}
	
	public func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<I, T> {
		return nextStage(signal.stride(count: count, initialSkip: initialSkip))
	}
	
	public func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergeSet<U>) -> ()) -> SignalChannel<I, U> {
		return nextStage(signal.transformFlatten(closePropagation: closePropagation, context: context, processor))
	}
	
	public func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergeSet<U>) -> ()) -> SignalChannel<I, U> {
		return nextStage(signal.transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor))
	}
	
	public func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> SignalChannel<I, (Int, T?)> {
		return nextStage(signal.valueDurations(closePropagation: closePropagation, context: context, duration: duration))
	}
	
	public func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, (Int, T?)> {
		return nextStage(signal.valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration))
	}
	
	public func join(to: SignalMergeSet<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) throws -> I {
		try signal.join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
		return input
	}
	
	public func cancellableJoin(to: SignalMergeSet<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) throws -> (I, Cancellable) {
		return try (input, signal.cancellableJoin(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate))
	}
		
	public func join(to: SignalCollector<T>) -> I {
		signal.join(to: to)
		return input
	}
	
	public func cancellableJoin(to: SignalCollector<T>) -> (I, Cancellable) {
		return (input, signal.cancellableJoin(to: to))
	}
	
	public func pollingEndpoint() -> (I, SignalPollingEndpoint<T>) {
		return (input, SignalPollingEndpoint(signal: signal))
	}
}

// Implementation of SignalReactive.swift
extension SignalChannel {
	public func buffer<U>(boundaries: Signal<U>) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(boundaries: boundaries))
	}
	
	public func buffer<U>(windows: Signal<Signal<U>>) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(windows: windows))
	}
	
	public func buffer(count: UInt, skip: UInt) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(count: count, skip: skip))
	}
	
	public func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(interval: interval, count: count, continuous: continuous, context: context))
	}
	
	public func buffer(count: UInt) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(count: count, skip: count))
	}
	
	public func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, [T]> {
		return nextStage(signal.buffer(interval: interval, timeshift: timeshift, context: context))
	}
	
	public func filterMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> U?) -> SignalChannel<I, U> {
		return nextStage(signal.filterMap(context: context, processor))
	}
	
	public func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) -> SignalChannel<I, U> {
		return nextStage(signal.filterMap(initialState: initialState, context: context, processor))
	}
	
	public func failableMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U) -> SignalChannel<I, U> {
		return nextStage(signal.failableMap(context: context, processor))
	}
	
	public func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) throws -> U) -> SignalChannel<I, U> {
		return nextStage(signal.failableMap(initialState: initialState, context: context, processor))
	}
	
	public func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U?) -> SignalChannel<I, U> {
		return nextStage(signal.failableFilterMap(context: context, processor))
	}
	
	public func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) throws -> SignalChannel<I, U> {
		return nextStage(signal.failableFilterMap(initialState: initialState, context: context, processor))
	}
	
	public func flatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return nextStage(signal.flatMap(context: context, processor))
	}
	
	public func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return nextStage(signal.flatMapFirst(context: context, processor))
	}
	
	public func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return nextStage(signal.flatMapLatest(context: context, processor))
	}
	
	public func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, U> {
		return nextStage(signal.flatMap(initialState: initialState, context: context, processor))
	}
	
	public func concatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<I, U> {
		return nextStage(signal.concatMap(context: context, processor))
	}
	
	public func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<I, (U, Signal<T>)> {
		return nextStage(signal.groupBy(context: context, processor))
	}
	
	public func map<U>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<I, U> {
		return nextStage(signal.map(context: context, processor))
	}
	
	public func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> U) -> SignalChannel<I, U> {
		return nextStage(signal.map(initialState: initialState, context: context, processor))
	}
	
	public func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, T) -> U) -> SignalChannel<I, U> {
		return nextStage(signal.scan(initialState: initialState, context: context, processor))
	}
	
	public func window<U>(boundaries: Signal<U>) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(boundaries: boundaries))
	}
	
	public func window<U>(windows: Signal<Signal<U>>) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(windows: windows))
	}
	
	public func window(count: UInt, skip: UInt) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(count: count, skip: skip))
	}
	
	public func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(interval: interval, count: count, continuous: continuous, context: context))
	}
	
	public func window(count: UInt) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(count: count, skip: count))
	}
	
	public func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, Signal<T>> {
		return nextStage(signal.window(interval: interval, timeshift: timeshift, context: context))
	}
	
	public func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalChannel<I, T> {
		return nextStage(signal.debounce(interval: interval, flushOnClose: flushOnClose, context: context))
	}
	
	public func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return nextStage(signal.throttleFirst(interval: interval, context: context))
	}
}

extension SignalChannel where T: Hashable {
	public func distinct() -> SignalChannel<I, T> {
		return nextStage(signal.distinct())
	}
	
	public func distinctUntilChanged() -> SignalChannel<I, T> {
		return nextStage(signal.distinctUntilChanged())
	}
}

extension SignalChannel {
	public func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (T, T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.distinctUntilChanged(context: context, comparator: comparator))
	}
	
	public func elementAt(_ index: UInt) -> SignalChannel<I, T> {
		return nextStage(signal.elementAt(index))
	}
	
	public func filter(context: Exec = .direct, matching: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.filter(context: context, matching: matching))
	}
	
	public func ofType<U>(_ type: U.Type) -> SignalChannel<I, U> {
		return nextStage(signal.ofType(type))
	}
	
	public func first(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return nextStage(signal.first(context: context, matching: matching))
	}
	
	public func single(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return nextStage(signal.single(context: context, matching: matching))
	}
	
	public func ignoreElements() -> SignalChannel<I, T> {
		return nextStage(signal.ignoreElements())
	}
	
	public func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalChannel<I, S.Iterator.Element> {
		return nextStage(signal.ignoreElements(endWith: endWith))
	}
	
	public func last(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<I, T> {
		return nextStage(signal.last(context: context, matching: matching))
	}
	
	public func sample(_ trigger: Signal<()>) -> SignalChannel<I, T> {
		return nextStage(signal.sample(trigger))
	}
	
	public func sampleCombine<U>(_ trigger: Signal<U>) -> SignalChannel<I, (T, U)> {
		return nextStage(signal.sampleCombine(trigger))
	}
	
	public func skip(_ count: Int) -> SignalChannel<I, T> {
		return nextStage(signal.skip(count))
	}
	
	public func skipLast(_ count: Int) -> SignalChannel<I, T> {
		return nextStage(signal.skipLast(count))
	}
	
	public func take(_ count: Int) -> SignalChannel<I, T> {
		return nextStage(signal.take(count))
	}
	
	public func takeLast(_ count: Int) -> SignalChannel<I, T> {
		return nextStage(signal.takeLast(count))
	}
}


extension SignalChannel {
	
	public func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (T, U) -> V) -> SignalChannel<I, V> {
		return nextStage(signal.combineLatest(second: second, context: context, processor))
	}
	
	public func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (T, U, V) -> W) -> SignalChannel<I, W> {
		return nextStage(signal.combineLatest(second: second, third: third, context: context, processor))
	}
	
	public func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (T, U, V, W) -> X) -> SignalChannel<I, X> {
		return nextStage(signal.combineLatest(second: second, third: third, fourth: fourth, context: context, processor))
	}
	
	public func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (T, U, V, W, X) -> Y) -> SignalChannel<I, Y> {
		return nextStage(signal.combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor))
	}
	
	public func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, U)) -> X) -> SignalChannel<I, X> {
		return nextStage(signal.join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor))
	}
	
	public func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, Signal<U>)) -> X) -> SignalChannel<I, X> {
		return nextStage(signal.groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor))
	}
	
	public func mergeWith(_ sources: Signal<T>...) -> SignalChannel<I, T> {
		return nextStage(signal.mergeWith(sources: sources))
	}
	
	public func mergeWith(sources: [Signal<T>]) -> SignalChannel<I, T> {
		return nextStage(signal.mergeWith(sources: sources))
	}
	
	public func startWith<S: Sequence>(_ sequence: S) -> SignalChannel<I, T> where S.Iterator.Element == T {
		return nextStage(signal.startWith(sequence))
	}
	
	public func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<I, T> where U.Iterator.Element == T {
		return nextStage(signal.endWith(sequence, conditional: conditional))
	}
	
	public func zip<U>(second: Signal<U>) -> SignalChannel<I, (T, U)> {
		return nextStage(signal.zip(second: second))
	}
	
	public func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalChannel<I, (T, U, V)> {
		return nextStage(signal.zip(second: second, third: third))
	}
	
	public func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalChannel<I, (T, U, V, W)> {
		return nextStage(signal.zip(second: second, third: third, fourth: fourth))
	}
	
	public func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalChannel<I, (T, U, V, W, X)> {
		return nextStage(signal.zip(second: second, third: third, fourth: fourth, fifth: fifth))
	}
	
	public func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalChannel<I, T> where S.Iterator.Element == T {
		return nextStage(signal.catchError(context: context, recover: recover))
	}
}

extension SignalChannel {
	public func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<T>?) -> SignalChannel<I, T> {
		return nextStage(signal.catchError(context: context, recover: recover))
	}
	
	public func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalChannel<I, T> {
		return nextStage(signal.retry(initialState, context: context, shouldRetry: shouldRetry))
	}
	
	public func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return nextStage(signal.retry(count: count, delayInterval: delayInterval, context: context))
	}
	
	public func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, T) -> DispatchTimeInterval) -> SignalChannel<I, T> {
		return nextStage(signal.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset))
	}
	
	public func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<I, T> {
		return nextStage(signal.delay(interval: interval, context: context))
	}
	
	public func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (T) -> Signal<U>) -> SignalChannel<I, T> {
		return nextStage(signal.delay(closePropagation: closePropagation, context: context, offset: offset))
	}
	
	public func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<I, T> {
		return nextStage(signal.delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset))
	}
	
	public func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<I, T> {
		return nextStage(signal.onActivate(context: context, handler: handler))
	}
	
	public func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<I, T> {
		return nextStage(signal.onDeactivate(context: context, handler: handler))
	}
	
	public func onResult(context: Exec = .direct, handler: @escaping (Result<T>) -> ()) -> SignalChannel<I, T> {
		return nextStage(signal.onResult(context: context, handler: handler))
	}
	
	public func onValue(context: Exec = .direct, handler: @escaping (T) -> ()) -> SignalChannel<I, T> {
		return nextStage(signal.onValue(context: context, handler: handler))
	}
	
	public func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalChannel<I, T> {
		return nextStage(signal.onError(context: context, handler: handler))
	}
	
	public func materialize() -> SignalChannel<I, Result<T>> {
		return nextStage(signal.materialize())
	}
}


extension SignalChannel {
	
	public func timeInterval(context: Exec = .direct) -> SignalChannel<I, Double> {
		return nextStage(signal.timeInterval(context: context))
	}
	
	public func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<I, T> {
		return nextStage(signal.timeout(interval: interval, resetOnValue: resetOnValue, context: context))
	}
	
	public func timestamp(context: Exec = .direct) -> SignalChannel<I, (T, DispatchTime)> {
		return nextStage(signal.timestamp(context: context))
	}
}


extension SignalChannel {
	
	public func all(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<I, Bool> {
		return nextStage(signal.all(context: context, test: test))
	}
	
	public func some(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<I, Bool> {
		return nextStage(signal.some(context: context, test: test))
	}
}

extension SignalChannel where T: Equatable {
	
	public func contains(value: T) -> SignalChannel<I, Bool> {
		return nextStage(signal.contains(value: value))
	}
}

extension SignalChannel {
	
	public func defaultIfEmpty(value: T) -> SignalChannel<I, T> {
		return nextStage(signal.defaultIfEmpty(value: value))
	}
	
	public func switchIfEmpty(alternate: Signal<T>) -> SignalChannel<I, T> {
		return nextStage(signal.switchIfEmpty(alternate: alternate))
	}
}

extension SignalChannel where T: Equatable {
	
	public func sequenceEqual(to: Signal<T>) -> SignalChannel<I, Bool> {
		return nextStage(signal.sequenceEqual(to: to))
	}
}

extension SignalChannel {
	
	public func skipUntil<U>(_ other: Signal<U>) -> SignalChannel<I, T> {
		return nextStage(signal.skipUntil(other))
	}
	
	public func skipWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.skipWhile(context: context, condition: condition))
	}
	
	public func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.skipWhile(initialState: initial, context: context, condition: condition))
	}
	
	public func takeUntil<U>(_ other: Signal<U>) -> SignalChannel<I, T> {
		return nextStage(signal.takeUntil(other))
	}
	
	public func takeWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.takeWhile(context: context, condition: condition))
	}
	
	public func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<I, T> {
		return nextStage(signal.takeWhile(initialState: initial, context: context, condition: condition))
	}
	
	public func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, T) -> V) -> SignalChannel<I, U> {
		return nextStage(signal.foldAndFinalize(initial, context: context, finalize: finalize, fold: fold))
	}
}

extension SignalChannel where T: BinaryInteger {
	
	public func average() -> SignalChannel<I, T> {
		return nextStage(signal.average())
	}
}

extension SignalChannel {
	
	public func concat(_ other: Signal<T>) -> SignalChannel<I, T> {
		return nextStage(signal.concat(other))
	}
	
	public func count() -> SignalChannel<I, Int> {
		return nextStage(signal.count())
	}
}

extension SignalChannel where T: Comparable {
	
	public func min() -> SignalChannel<I, T> {
		return nextStage(signal.min())
	}
	
	public func max() -> SignalChannel<I, T> {
		return nextStage(signal.max())
	}
}

extension SignalChannel {
	
	public func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, T) -> U) -> SignalChannel<I, U> {
		return nextStage(signal.reduce(initial, context: context, fold: fold))
	}
}

extension SignalChannel where T: Numeric {
	
	public func sum() -> SignalChannel<I, T> {
		return nextStage(signal.sum())
	}
}

// Implementation of Signal.swift
extension SignalInput {
	public static func subscribeAndKeepAlive(context: Exec = .direct, handler: @escaping (Result<T>) -> Bool) -> SignalInput<T> {
		return Signal<T>.channel().subscribeAndKeepAlive(context: context, handler: handler)
	}
	
	public static func join(to: SignalInput<T>) throws -> SignalInput<T> {
		return try Signal<T>.channel().join(to: to)
	}
	
	public static func join(to: SignalInput<T>, onError: @escaping (SignalJunction<T>, Error, SignalInput<T>) -> ()) throws -> SignalInput<T> {
		return try Signal<T>.channel().join(to: to, onError: onError)
	}
	
	public static func transform<U>(context: Exec = .direct, handler: @escaping (Result<T>, SignalNext<U>) -> Void) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().transform(context: context, handler: handler)
	}
	
	public static func transform<S, U>(initialState: S, context: Exec = .direct, handler: @escaping (inout S, Result<T>, SignalNext<U>) -> Void) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().transform(initialState: initialState, context: context, handler: handler)
	}
	
	public static func combine<U, V>(second: Signal<U>, context: Exec = .direct, handler: @escaping (EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<SignalInput<T>, V> {
		return Signal<T>.channel().combine(second: second, context: context, handler: handler)
	}
	
	public static func combine<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<SignalInput<T>, W> {
		return Signal<T>.channel().combine(second: second, third: third, context: context, handler: handler)
	}
	
	public static func combine<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<SignalInput<T>, X> {
		return Signal<T>.channel().combine(second: second, third: third, fourth: fourth, context: context, handler: handler)
	}
	
	public static func combine<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<SignalInput<T>, Y> {
		return Signal<T>.channel().combine(second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler)
	}
	
	public static func combine<S, U, V>(initialState: S, second: Signal<U>, context: Exec = .direct, handler: @escaping (inout S, EitherResult2<T, U>, SignalNext<V>) -> Void) -> SignalChannel<SignalInput<T>, V> {
		return Signal<T>.channel().combine(initialState: initialState, second: second, context: context, handler: handler)
	}
	
	public static func combine<S, U, V, W>(initialState: S, second: Signal<U>, third: Signal<V>, context: Exec = .direct, handler: @escaping (inout S, EitherResult3<T, U, V>, SignalNext<W>) -> Void) -> SignalChannel<SignalInput<T>, W> {
		return Signal<T>.channel().combine(initialState: initialState, second: second, third: third, context: context, handler: handler)
	}
	
	public static func combine<S, U, V, W, X>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, handler: @escaping (inout S, EitherResult4<T, U, V, W>, SignalNext<X>) -> Void) -> SignalChannel<SignalInput<T>, X> {
		return Signal<T>.channel().combine(initialState: initialState, second: second, third: third, fourth: fourth, context: context, handler: handler)
	}
	
	public static func combine<S, U, V, W, X, Y>(initialState: S, second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, handler: @escaping (inout S, EitherResult5<T, U, V, W, X>, SignalNext<Y>) -> Void) -> SignalChannel<SignalInput<T>, Y> {
		return Signal<T>.channel().combine(initialState: initialState, second: second, third: third, fourth: fourth, fifth: fifth, context: context, handler: handler)
	}
}

// Implementation of SignalExtensions.swift
extension SignalInput {
	public static func subscribeValuesAndKeepAlive(context: Exec = .direct, handler: @escaping (ValueType) -> Bool) -> SignalInput<T> {
		return Signal<T>.channel().subscribeValuesAndKeepAlive(context: context, handler: handler)
	}
	
	public static func stride(count: Int, initialSkip: Int = 0) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().stride(count: count, initialSkip: initialSkip)
	}
	
	public static func transformFlatten<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (T, SignalMergeSet<U>) -> ()) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().transformFlatten(closePropagation: closePropagation, context: context, processor)
	}
	
	public static func transformFlatten<S, U>(initialState: S, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, _ processor: @escaping (inout S, T, SignalMergeSet<U>) -> ()) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().transformFlatten(initialState: initialState, closePropagation: closePropagation, context: context, processor)
	}
	
	public static func valueDurations<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, (Int, T?)> {
		return Signal<T>.channel().valueDurations(closePropagation: closePropagation, context: context, duration: duration)
	}
	
	public static func valueDurations<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, duration: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<SignalInput<T>, (Int, T?)> {
		return Signal<T>.channel().valueDurations(initialState: initialState, closePropagation: closePropagation, context: context, duration: duration)
	}
	
	public static func join(to: SignalMergeSet<T>, closePropagation: SignalClosePropagation = .none, removeOnDeactivate: Bool = false) throws -> SignalInput<T> {
		return try Signal<T>.channel().join(to: to, closePropagation: closePropagation, removeOnDeactivate: removeOnDeactivate)
	}
	
	public static func join(to: SignalCollector<T>) -> SignalInput<T> {
		return Signal<T>.channel().join(to: to)
	}
}

// Implementation of SignalReactive.swift
extension SignalInput {
	public static func buffer<U>(boundaries: Signal<U>) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(boundaries: boundaries)
	}
	
	public static func buffer<U>(windows: Signal<Signal<U>>) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(windows: windows)
	}
	
	public static func buffer(count: UInt, skip: UInt) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(count: count, skip: skip)
	}
	
	public static func buffer(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(interval: interval, count: count, continuous: continuous, context: context)
	}
	
	public static func buffer(count: UInt) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(count: count, skip: count)
	}
	
	public static func buffer(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<SignalInput<T>, [T]> {
		return Signal<T>.channel().buffer(interval: interval, timeshift: timeshift, context: context)
	}
	
	public static func filterMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> U?) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().filterMap(context: context, processor)
	}
	
	public static func filterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().filterMap(initialState: initialState, context: context, processor)
	}
	
	public static func failableMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().failableMap(context: context, processor)
	}
	
	public static func failableMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) throws -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().failableMap(initialState: initialState, context: context, processor)
	}
	
	public static func failableFilterMap<U>(context: Exec = .direct, _ processor: @escaping (T) throws -> U?) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().failableFilterMap(context: context, processor)
	}
	
	public static func failableFilterMap<S, U>(initialState: S, context: Exec = .direct, _ processor: @escaping (inout S, T) -> U?) throws -> SignalChannel<SignalInput<T>, U> {
		return try Signal<T>.channel().failableFilterMap(initialState: initialState, context: context, processor)
	}
	
	public static func flatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().flatMap(context: context, processor)
	}
	
	public static func flatMapFirst<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().flatMapFirst(context: context, processor)
	}
	
	public static func flatMapLatest<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().flatMapLatest(context: context, processor)
	}
	
	public static func flatMap<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().flatMap(initialState: initialState, context: context, processor)
	}
	
	public static func concatMap<U>(context: Exec = .direct, _ processor: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().concatMap(context: context, processor)
	}
	
	public static func groupBy<U: Hashable>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<SignalInput<T>, (U, Signal<T>)> {
		return Signal<T>.channel().groupBy(context: context, processor)
	}
	
	public static func map<U>(context: Exec = .direct, _ processor: @escaping (T) -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().map(context: context, processor)
	}
	
	public static func map<U, V>(initialState: V, context: Exec = .direct, _ processor: @escaping (inout V, T) -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().map(initialState: initialState, context: context, processor)
	}
	
	public static func scan<U>(initialState: U, context: Exec = .direct, _ processor: @escaping (U, T) -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().scan(initialState: initialState, context: context, processor)
	}
	
	public static func window<U>(boundaries: Signal<U>) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(boundaries: boundaries)
	}
	
	public static func window<U>(windows: Signal<Signal<U>>) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(windows: windows)
	}
	
	public static func window(count: UInt, skip: UInt) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(count: count, skip: skip)
	}
	
	public static func window(interval: DispatchTimeInterval, count: Int = Int.max, continuous: Bool = true, context: Exec = .direct) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(interval: interval, count: count, continuous: continuous, context: context)
	}
	
	public static func window(count: UInt) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(count: count, skip: count)
	}
	
	public static func window(interval: DispatchTimeInterval, timeshift: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<SignalInput<T>, Signal<T>> {
		return Signal<T>.channel().window(interval: interval, timeshift: timeshift, context: context)
	}
	
	public static func debounce(interval: DispatchTimeInterval, flushOnClose: Bool = true, context: Exec = .direct) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().debounce(interval: interval, flushOnClose: flushOnClose, context: context)
	}
	
	public static func throttleFirst(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().throttleFirst(interval: interval, context: context)
	}
}

extension SignalInput where T: Hashable {
	public static func distinct() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().distinct()
	}
	
	public static func distinctUntilChanged() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().distinctUntilChanged()
	}
}

extension SignalInput {
	public static func distinctUntilChanged(context: Exec = .direct, comparator: @escaping (T, T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().distinctUntilChanged(context: context, comparator: comparator)
	}
	
	public static func elementAt(_ index: UInt) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().elementAt(index)
	}
	
	public static func filter(context: Exec = .direct, matching: @escaping (T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().filter(context: context, matching: matching)
	}
	
	public static func ofType<U>(_ type: U.Type) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().ofType(type)
	}
	
	public static func first(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().first(context: context, matching: matching)
	}
	
	public static func single(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().single(context: context, matching: matching)
	}
	
	public static func ignoreElements() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().ignoreElements()
	}
	
	public static func ignoreElements<S: Sequence>(endWith: @escaping (Error) -> (S, Error)?) -> SignalChannel<SignalInput<T>, S.Iterator.Element> {
		return Signal<T>.channel().ignoreElements(endWith: endWith)
	}
	
	public static func last(context: Exec = .direct, matching: @escaping (T) -> Bool = { _ in true }) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().last(context: context, matching: matching)
	}
	
	public static func sample(_ trigger: Signal<()>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().sample(trigger)
	}
	
	public static func sampleCombine<U>(_ trigger: Signal<U>) -> SignalChannel<SignalInput<T>, (T, U)> {
		return Signal<T>.channel().sampleCombine(trigger)
	}
	
	public static func skip(_ count: Int) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().skip(count)
	}
	
	public static func skipLast(_ count: Int) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().skipLast(count)
	}
	
	public static func take(_ count: Int) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().take(count)
	}
	
	public static func takeLast(_ count: Int) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().takeLast(count)
	}
}


extension SignalInput {
	
	public static func combineLatest<U, V>(second: Signal<U>, context: Exec = .direct, _ processor: @escaping (T, U) -> V) -> SignalChannel<SignalInput<T>, V> {
		return Signal<T>.channel().combineLatest(second: second, context: context, processor)
	}
	
	public static func combineLatest<U, V, W>(second: Signal<U>, third: Signal<V>, context: Exec = .direct, _ processor: @escaping (T, U, V) -> W) -> SignalChannel<SignalInput<T>, W> {
		return Signal<T>.channel().combineLatest(second: second, third: third, context: context, processor)
	}
	
	public static func combineLatest<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, context: Exec = .direct, _ processor: @escaping (T, U, V, W) -> X) -> SignalChannel<SignalInput<T>, X> {
		return Signal<T>.channel().combineLatest(second: second, third: third, fourth: fourth, context: context, processor)
	}
	
	public static func combineLatest<U, V, W, X, Y>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>, context: Exec = .direct, _ processor: @escaping (T, U, V, W, X) -> Y) -> SignalChannel<SignalInput<T>, Y> {
		return Signal<T>.channel().combineLatest(second: second, third: third, fourth: fourth, fifth: fifth, context: context, processor)
	}
	
	public static func join<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, U)) -> X) -> SignalChannel<SignalInput<T>, X> {
		return Signal<T>.channel().join(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor)
	}
	
	public static func groupJoin<U, V, W, X>(withRight: Signal<U>, leftEnd: @escaping (T) -> Signal<V>, rightEnd: @escaping (U) -> Signal<W>, context: Exec = .direct, _ processor: @escaping ((T, Signal<U>)) -> X) -> SignalChannel<SignalInput<T>, X> {
		return Signal<T>.channel().groupJoin(withRight: withRight, leftEnd: leftEnd, rightEnd: rightEnd, context: context, processor)
	}
	
	public static func mergeWith(_ sources: Signal<T>...) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().mergeWith(sources: sources)
	}
	
	public static func mergeWith(sources: [Signal<T>]) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().mergeWith(sources: sources)
	}
	
	public static func startWith<S: Sequence>(_ sequence: S) -> SignalChannel<SignalInput<T>, T> where S.Iterator.Element == T {
		return Signal<T>.channel().startWith(sequence)
	}
	
	public static func endWith<U: Sequence>(_ sequence: U, conditional: @escaping (Error) -> Error? = { e in e }) -> SignalChannel<SignalInput<T>, T> where U.Iterator.Element == T {
		return Signal<T>.channel().endWith(sequence, conditional: conditional)
	}
	
	public static func zip<U>(second: Signal<U>) -> SignalChannel<SignalInput<T>, (T, U)> {
		return Signal<T>.channel().zip(second: second)
	}
	
	public static func zip<U, V>(second: Signal<U>, third: Signal<V>) -> SignalChannel<SignalInput<T>, (T, U, V)> {
		return Signal<T>.channel().zip(second: second, third: third)
	}
	
	public static func zip<U, V, W>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>) -> SignalChannel<SignalInput<T>, (T, U, V, W)> {
		return Signal<T>.channel().zip(second: second, third: third, fourth: fourth)
	}
	
	public static func zip<U, V, W, X>(second: Signal<U>, third: Signal<V>, fourth: Signal<W>, fifth: Signal<X>) -> SignalChannel<SignalInput<T>, (T, U, V, W, X)> {
		return Signal<T>.channel().zip(second: second, third: third, fourth: fourth, fifth: fifth)
	}
	
	public static func catchError<S: Sequence>(context: Exec = .direct, recover: @escaping (Error) -> (S, Error)) -> SignalChannel<SignalInput<T>, T> where S.Iterator.Element == T {
		return Signal<T>.channel().catchError(context: context, recover: recover)
	}
}

extension SignalInput {
	public static func catchError(context: Exec = .direct, recover: @escaping (Error) -> Signal<T>?) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().catchError(context: context, recover: recover)
	}
	
	public static func retry<U>(_ initialState: U, context: Exec = .direct, shouldRetry: @escaping (inout U, Error) -> DispatchTimeInterval?) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().retry(initialState, context: context, shouldRetry: shouldRetry)
	}
	
	public static func retry(count: Int, delayInterval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().retry(count: count, delayInterval: delayInterval, context: context)
	}
	
	public static func delay<U>(initialState: U, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout U, T) -> DispatchTimeInterval) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset)
	}
	
	public static func delay(interval: DispatchTimeInterval, context: Exec = .direct) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().delay(interval: interval, context: context)
	}
	
	public static func delay<U>(closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (T) -> Signal<U>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().delay(closePropagation: closePropagation, context: context, offset: offset)
	}
	
	public static func delay<U, V>(initialState: V, closePropagation: SignalClosePropagation = .none, context: Exec = .direct, offset: @escaping (inout V, T) -> Signal<U>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().delay(initialState: initialState, closePropagation: closePropagation, context: context, offset: offset)
	}
	
	public static func onActivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().onActivate(context: context, handler: handler)
	}
	
	public static func onDeactivate(context: Exec = .direct, handler: @escaping () -> ()) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().onDeactivate(context: context, handler: handler)
	}
	
	public static func onResult(context: Exec = .direct, handler: @escaping (Result<T>) -> ()) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().onResult(context: context, handler: handler)
	}
	
	public static func onValue(context: Exec = .direct, handler: @escaping (T) -> ()) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().onValue(context: context, handler: handler)
	}
	
	public static func onError(context: Exec = .direct, handler: @escaping (Error) -> ()) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().onError(context: context, handler: handler)
	}
	
	public static func materialize() -> SignalChannel<SignalInput<T>, Result<T>> {
		return Signal<T>.channel().materialize()
	}
}


extension SignalInput {
	
	public static func timeInterval(context: Exec = .direct) -> SignalChannel<SignalInput<T>, Double> {
		return Signal<T>.channel().timeInterval(context: context)
	}
	
	public static func timeout(interval: DispatchTimeInterval, resetOnValue: Bool = true, context: Exec = .direct) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().timeout(interval: interval, resetOnValue: resetOnValue, context: context)
	}
	
	public static func timestamp(context: Exec = .direct) -> SignalChannel<SignalInput<T>, (T, DispatchTime)> {
		return Signal<T>.channel().timestamp(context: context)
	}
}


extension SignalInput {
	
	public static func all(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<SignalInput<T>, Bool> {
		return Signal<T>.channel().all(context: context, test: test)
	}
	
	public static func some(context: Exec = .direct, test: @escaping (T) -> Bool) -> SignalChannel<SignalInput<T>, Bool> {
		return Signal<T>.channel().some(context: context, test: test)
	}
}

extension SignalInput where T: Equatable {
	
	public static func contains(value: T) -> SignalChannel<SignalInput<T>, Bool> {
		return Signal<T>.channel().contains(value: value)
	}
}

extension SignalInput {
	
	public static func defaultIfEmpty(value: T) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().defaultIfEmpty(value: value)
	}
	
	public static func switchIfEmpty(alternate: Signal<T>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().switchIfEmpty(alternate: alternate)
	}
}

extension SignalInput where T: Equatable {
	
	public static func sequenceEqual(to: Signal<T>) -> SignalChannel<SignalInput<T>, Bool> {
		return Signal<T>.channel().sequenceEqual(to: to)
	}
}

extension SignalInput {
	
	public static func skipUntil<U>(_ other: Signal<U>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().skipUntil(other)
	}
	
	public static func skipWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().skipWhile(context: context, condition: condition)
	}
	
	public static func skipWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().skipWhile(initialState: initial, context: context, condition: condition)
	}
	
	public static func takeUntil<U>(_ other: Signal<U>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().takeUntil(other)
	}
	
	public static func takeWhile(context: Exec = .direct, condition: @escaping (T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().takeWhile(context: context, condition: condition)
	}
	
	public static func takeWhile<U>(initialState initial: U, context: Exec = .direct, condition: @escaping (inout U, T) -> Bool) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().takeWhile(initialState: initial, context: context, condition: condition)
	}
	
	public static func foldAndFinalize<U, V>(_ initial: V, context: Exec = .direct, finalize: @escaping (V) -> U?, fold: @escaping (V, T) -> V) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().foldAndFinalize(initial, context: context, finalize: finalize, fold: fold)
	}
}

extension SignalInput where T: BinaryInteger {
	
	public static func average() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().average()
	}
}

extension SignalInput {
	
	public static func concat(_ other: Signal<T>) -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().concat(other)
	}
	
	public static func count() -> SignalChannel<SignalInput<T>, Int> {
		return Signal<T>.channel().count()
	}
}

extension SignalInput where T: Comparable {
	
	public static func min() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().min()
	}
	
	public static func max() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().max()
	}
}

extension SignalInput {
	
	public static func reduce<U>(_ initial: U, context: Exec = .direct, fold: @escaping (U, T) -> U) -> SignalChannel<SignalInput<T>, U> {
		return Signal<T>.channel().reduce(initial, context: context, fold: fold)
	}
}

extension SignalInput where T: Numeric {
	
	public static func sum() -> SignalChannel<SignalInput<T>, T> {
		return Signal<T>.channel().sum()
	}
}

