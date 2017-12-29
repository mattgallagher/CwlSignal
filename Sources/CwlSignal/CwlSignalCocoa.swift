//
//  CwlSignalCocoa.swift
//  CwlSignal
//
//  Created by Matt Gallagher on 11/2/16.
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

/// Instances of `SignalActionTarget` can be used as the "target" of Cocoa "target-action" events and the result will be emitted as a signal.
/// Instance of this class are owned by the output `signal` so if you're holding onto the signal, you can drop references to this class itself.
open class SignalActionTarget: NSObject, SignalInterface {
	private var signalInput: SignalInput<Any?>? = nil
	
	// Ownership note: we are owned by the output signal so we only weakly retain it.
	private weak var signalOutput: SignalMulti<Any?>? = nil
	
	/// The `signal` emits the actions received
	public var signal: Signal<Any?> {
		// If there's a current signal output, return it
		if let so = signalOutput {
			return so
		}
		
		// Otherwise, create a new one
			// Instead of using a `continuous` transform, use a `customActivation` to do the same thing while capturing `self` so that we're owned by the signal.
		let (i, internalSignal) = Signal<Any?>.create()
		let s = internalSignal.customActivation { (b: inout Array<Any?>, e: inout Error?, r: Result<Any?>) in
			withExtendedLifetime(self) {}
			switch r {
			case .success(let v):
				b.removeAll(keepingCapacity: true)
				b.append(v)
			case .failure(let err):
				e = err
			}
		}
		self.signalInput = i
		self.signalOutput = s
		return s
	}
	
	/// Receiver function for the target-action events
	///
	/// - Parameter sender: typical target-action "sender" parameter
	@IBAction public func cwlSignalAction(_ sender: Any?) {
		_ = signalInput?.send(value: sender)
	}
	
	/// Convenience accessor for `#selector(SignalActionTarget<Value>.cwlSignalAction(_:))`
	public var selector: Selector { return #selector(SignalActionTarget.cwlSignalAction(_:)) }
}

/// Like `SignalActionTarget` but with a second action method connected to the same target. Useful for situations like NSTableView targets which send single-click and double-click to the same target.
open class SignalDoubleActionTarget: SignalActionTarget {
	private var secondInput: SignalInput<Any?>? = nil
	private weak var secondOutput: SignalMulti<Any?>? = nil

	/// The `signal` emits the actions received
	public var secondSignal: SignalMulti<Any?> {
		// If there's a current signal output, return it
		if let so = secondOutput {
			return so
		}
		
		// Otherwise, create a new one
		let (i, internalSignal) = Signal<Any?>.create()
		let s = internalSignal.customActivation { (b: inout Array<Any?>, e: inout Error?, r: Result<Any?>) in
			withExtendedLifetime(self) {}
			switch r {
			case .success(let v):
				b.removeAll(keepingCapacity: true)
				b.append(v)
			case .failure(let err):
				e = err
			}
		}
		self.secondInput = i
		self.secondOutput = s
		return s
	}

	/// Receiver function for "secondary" target-action events
	///
	/// - Parameter sender: typical target-action "sender" parameter
	@IBAction public func cwlSignalSecondAction(_ sender: Any?) {
		_ = secondInput?.send(value: sender)
	}
	
	/// Convenience accessor for `#selector(SignalDoubleActionTarget<Value>.cwlSignalSecondAction(_:))`
	public var secondSelector: Selector { return #selector(SignalDoubleActionTarget.cwlSignalSecondAction(_:)) }
}

/// This enum contains errors that might be emitted by `signalKeyValueObserving`
///
/// - missingChangeDictionary: the observation failed to supply a change dictionary
public enum SignalObservingError: Error {
	case missingChangeDictionary
}

/// Observe a property via key-value-observing and emit the changes as a Signal<OutputValue> on the condition that the emitted `Any` value can be dynamically cast (`as?`) to `OutputValue`
///
/// - Parameters:
///   - source: will have `addObserver(_:forKeyPath:options:context:)` invoked on it
///   - keyPath: passed to `addObserver(_:forKeyPath:options:context:)`
///   - initial: if true, NSKeyValueObservingOptions.initial is included in the options passed to `addObserver(_:forKeyPath:options:context:)`
/// - Returns: a signal which emits the observation results that match the expected type
extension Signal {
	public static func keyValueObserving(_ source: NSObject, keyPath: String, initial: Bool = true) -> Signal<OutputValue> {
		var observer: KeyValueObserver?
		return Signal<OutputValue>.generate { [weak source] (input: SignalInput<OutputValue>?) -> Void in
			guard let i = input, let s = source else {
				observer = nil
				return
			}
			let options = NSKeyValueObservingOptions.new.union(initial ? NSKeyValueObservingOptions.initial : NSKeyValueObservingOptions())
			observer = KeyValueObserver(source: s, keyPath: keyPath, options: options, callback: { (change, reason) -> Void in
				switch (reason, change[NSKeyValueChangeKey.newKey]) {
				case (.sourceDeleted, _): i.close()
				case (_, .some(let v)):
					if let t = v as? OutputValue {
						i.send(value: t)
					}
				default: i.send(error: SignalObservingError.missingChangeDictionary)
				}
			})
			withExtendedLifetime(observer) {}
		}
	}
}
@available(*, deprecated, message: "Use Signal.keyValueObserving")
public func signalKeyValueObserving(_ source: NSObject, keyPath: String, initial: Bool = true) -> Signal<Any> {
	return Signal.keyValueObserving(source, keyPath: keyPath, initial: initial)
}

extension Signal where OutputValue == Notification {
	/// Observe a notification
	///
	/// - Parameters:
	///   - center: the NotificationCenter where addObserver will be invoked (`NotificationCenter.default` is the default)
	///   - name: the Notification.Name to observer (nil is default)
	///   - object: the object to observer (nil is default)
	/// - Returns: a signal which emits the observation results
	public static func notifications(from center: NotificationCenter = NotificationCenter.default, name: Notification.Name? = nil, object: AnyObject? = nil) -> Signal<OutputValue> {
		var observerObject: NSObjectProtocol?
		return Signal<Notification>.generate { [weak object] input in
			if let o = observerObject {
				NotificationCenter.default.removeObserver(o)
			}
			if let i = input {
				observerObject = center.addObserver(forName: name, object: object, queue: nil) { n in
					i.send(value: n)
				}
			}
		}
	}
}

@available(*, deprecated, message: "Use Signal<Notification>.notifications")
public func signalFromNotifications(center: NotificationCenter = NotificationCenter.default, name: Notification.Name? = nil, object: AnyObject? = nil) -> Signal<Notification> {
	return Signal.notifications(from: center, name: name, object: object)
}

extension Signal {
	/// Attaches a SignalEndpoint that applies all values to a target NSObject using key value coding via the supplied keyPath. The property must match the runtime type of the Signal signal values or a precondition failure will be raised.
	///
	/// - Parameters:
	///   - context: the execution context where the setting will occur
	///   - target: the object upon which `setValue(_:forKeyPath:)` will be invoked
	///   - keyPath: passed to `setValue(_:forKeyPath:)`
	/// - Returns: the `SignalEnpoint` created by this action (releasing the endpoint will cease any further setting)
	public func kvcSetter(context: Exec, target: NSObject, keyPath: String) -> SignalEndpoint<OutputValue> {
		return subscribeValues(context: context) { [weak target] (value: OutputValue) -> Void in
			target?.setValue(value, forKeyPath: keyPath)
		}
	}
}
