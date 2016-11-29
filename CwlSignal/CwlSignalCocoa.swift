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

import Foundation

/// Instances of `SignalActionTarget` can be used as the "target" of Cocoa "target-action" events and will emit the
open class SignalActionTarget<T: AnyObject>: NSObject {
	private let signalInput: SignalInput<T>
	
	/// The `signal` emits the actions received
	private(set) public var signal: Signal<T>
	
	public override init() {
		(self.signalInput, self.signal) = Signal<T>.createPair()

		super.init()
		
		// Have the signal deliberately capture self to keep alive until the signal closes (since targets are typically weakly held by the sender)
		self.signal = self.signal.map { (v: T) -> T in
			withExtendedLifetime(self) {}
			return v
		}
	}
	
	/// Receiver function for the target-action events
	///
	/// - Parameter sender: typical target-action "sender" parameter
	@objc public func action(_ sender: AnyObject) {
		signalInput.send(value: sender as! T)
	}
	
	/// Convenience accessor for `#selector(SignalActionTarget<T>.action(_:))`
	public var selector: Selector { return #selector(SignalActionTarget<T>.action(_:)) }
}

/// Like `SignalActionTarget` but with a second action method connected to the same target. Useful for situations like NSTableView targets which send single-click and double-click to the same target.
open class SignalDoubleActionTarget<T: AnyObject>: SignalActionTarget<T> {
	private let secondInput: SignalInput<T>
	private let secondSignal: Signal<T>

	public override init() {
		(self.secondInput, self.secondSignal) = Signal<T>.createPair { $0.multicast() }
		super.init()
	}
	@objc public func secondAction(_ sender: AnyObject) {
		secondInput.send(value: sender as! T)
	}
	public var secondSelector: Selector { return #selector(SignalDoubleActionTarget.secondAction(_:)) }
}

public enum SignalObservingError: Error {
	case UnexpectedObservationState
}

/// Observe a property via key-value-observing and emit the changes as a Signal
///
/// - Parameters:
///   - target: will have `addObserver(_:forKeyPath:options:context:)` invoked on it
///   - keyPath: passed to `addObserver(_:forKeyPath:options:context:)`
///   - initial: if true, NSKeyValueObservingOptions.initial is included in the options passed to `addObserver(_:forKeyPath:options:context:)`
/// - Returns: a signal which emits the observation results
public func signalObserving(target: NSObject, keyPath: String, initial: Bool = true) -> Signal<Any> {
	var observer: KeyValueObserver?
	return Signal<Any>.generate { [weak target] (input: SignalInput<Any>?) -> Void in
		guard let i = input, let t = target else {
			observer = nil
			return
		}
		let options = NSKeyValueObservingOptions.new.union(initial ? NSKeyValueObservingOptions.initial : NSKeyValueObservingOptions())
		observer = KeyValueObserver(target: t, keyPath: keyPath, options: options, callback: { (change, reason) -> Void in
			switch (reason, change[NSKeyValueChangeKey.newKey]) {
			case (.targetDeleted, _): i.close()
			case (_, .some(let v)): i.send(value: v)
			default: i.send(error: SignalObservingError.UnexpectedObservationState)
			}
		})
		withExtendedLifetime(observer) {}
	}
}

/// Observe a notification on the
///
/// - Parameters:
///   - center: the NotificationCenter where addObserver will be invoked (`NotificationCenter.default` is the default)
///   - name: the Notification.Name to observer (nil is default)
///   - object: the object to observer (nil is default)
/// - Returns: a signal which emits the observation results
public func signalFromNotifications(center: NotificationCenter = NotificationCenter.default, name: Notification.Name? = nil, object: AnyObject? = nil) -> Signal<Notification> {
	var observerObject: NSObjectProtocol?
	return Signal<Notification>.generate { input in
		if let i = input {
			observerObject = center.addObserver(forName: name, object: object, queue: nil) { n in
				i.send(value: n)
			}
		} else {
			if let o = observerObject {
				NotificationCenter.default.removeObserver(o)
			}
		}
	}
}

extension Signal where T: AnyObject {
	/// Attaches a SignalEndpoint that applies all values to a target NSObject using key value coding via the supplied keyPath. The property must match the runtime type of the Signal signal values or a precondition failure will be raised.
	///
	/// - Parameters:
	///   - context: the execution context where the setting will occur
	///   - target: the object upon which `setValue(_:forKeyPath:)` will be invoked
	///   - keyPath: passed to `setValue(_:forKeyPath:)`
	/// - Returns: the `SignalEnpoint` created by this action (releasing the endpoint will cease any further setting)
	public func kvcSetter(context: Exec, target: NSObject, keyPath: String) -> SignalEndpoint<T> {
		var filterType: AnyClass? = nil
		if let propertyName = keyPath.cString(using: String.Encoding.utf8) {
			let property = class_getProperty(type(of: target), propertyName)
			if let p = property, let attrs = String(validatingUTF8: property_getAttributes(p))?.components(separatedBy: ","), let objAttr = attrs.first(where: { $0.hasPrefix("T@") }), let classType = NSClassFromString(objAttr.substring(from: objAttr.index(objAttr.startIndex, offsetBy: 2)).trimmingCharacters(in: CharacterSet(charactersIn:"\""))) {
				filterType = classType
			}
		}

		weak var weakTarget: NSObject? = target
		return subscribeValues(context: context) { (value: ValueType) -> Void in
			switch (filterType, value) {
			case (.some(let ft), let v as NSObjectProtocol) where v.isKind(of: ft): fallthrough
			case (.none, _): weakTarget?.setValue(value, forKeyPath: keyPath)
			default: preconditionFailure("kvc setter signal type \(T.self) failed to match property type \(filterType)")
			}
		}
	}
}
