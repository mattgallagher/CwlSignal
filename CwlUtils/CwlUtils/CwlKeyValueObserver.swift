//
//  CwlKeyValueObserver.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
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

public class KeyValueObserver: NSObject {
	public typealias Callback = (_ change: [NSKeyValueChangeKey: Any], _ reason: CallbackReason) -> Void
	private var callback: Callback?
	private var tailObserver: KeyValueObserver?
	private let key: String
	private let tailPath: String?
	private let options: NSKeyValueObservingOptions
	
	// Our "deletionBlock" is called to notify us that the target is being deallocated (so we can remove the key value observation before a warning is logged) and this happens during the target's "objc_destructinstance" function. At this point, a `weak` var will be `nil` and an `unowned` will trigger a `_swift_abortRetainUnowned` failure.
	// So we're left with `Unmanaged`. Careful cancellation before the target is deallocated is necessary to ensure we don't access an invalid memory location.
	private var target: Unmanaged<NSObject>
	
	public enum CallbackReason {
		case valueChanged
		case pathChanged
		case cancelled
		case targetDeleted
	}
	
    public init(target: NSObject, keyPath: String, options: NSKeyValueObservingOptions, callback: @escaping Callback) {
		self.callback = callback
		self.target = Unmanaged.passUnretained(target)
		self.options = options
		
		// Look for "." indicating a key path
		var range = keyPath.range(of: ".", options: NSString.CompareOptions(), range: nil, locale: nil)

		// If we have a collection operator, consider the next path component as part of this key
		if let r = range, keyPath.hasPrefix("@") {
			range = keyPath.range(of: ".", options: NSString.CompareOptions(), range: keyPath.index(after: r.lowerBound)..<keyPath.endIndex, locale: nil)
		}
		
		// Set the key and tailPath based on whether we detected multiple path components
		if let r = range {
			self.key = keyPath.substring(to: r.lowerBound)
			self.tailPath = keyPath.substring(from: keyPath.index(after: r.lowerBound))
		} else {
			self.key = keyPath
			
			// If we're observing a weak property, add an observer on self to the target to detect when it may be set to nil without going through the property setter
			var p: String? = nil
			if let propertyName = keyPath.cString(using: String.Encoding.utf8) {
				let property = class_getProperty(type(of: target), propertyName)
				// Look for both the "id" and "weak" attributes.
				if property != nil, let attributes = String(validatingUTF8: property_getAttributes(property))?.components(separatedBy: ","), attributes.filter({ $0.hasPrefix("T@") || $0 == "W" }).count == 2 {
					p = "self"
				}
			}
			self.tailPath = p
		}

		super.init()
		
		// Detect if the target is deleted
		let deletionBlock = OnDelete() { [weak self] () -> Void in
			self?.cancel(.targetDeleted)
			return
		}
		objc_setAssociatedObject(target, Unmanaged.passUnretained(self).toOpaque(), deletionBlock, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)

		// Start observing the target
		if key != "self" {
			var currentOptions = options
			if !isObservingTail {
				currentOptions = NSKeyValueObservingOptions.new.union(options.intersection(NSKeyValueObservingOptions.prior))
			}
			
			target.addObserver(self, forKeyPath: key, options: currentOptions, context: Unmanaged.passUnretained(self).toOpaque())
		}
		
		// Start observing the value of the target
		if tailPath != nil {
			updateTailObserver(target.value(forKeyPath: self.key) as? NSObject, isInitial: true)
		}
	}
	
	deinit {
		cancel()
	}
	
	private func updateTailObserver(_ onValue: NSObject?, isInitial: Bool) {
		tailObserver?.cancel()
		tailObserver = nil

		if let _ = callback, let tp = tailPath, let currentValue = onValue {
			let currentOptions = isInitial ? self.options : self.options.subtracting(NSKeyValueObservingOptions.initial)
			self.tailObserver = KeyValueObserver(target: currentValue, keyPath: tp, options: currentOptions, callback: self.tailCallback)
		}
	}
	
	private var isObservingTail: Bool {
		return tailPath == nil || tailPath == "self"
	}
	
	private var needsWeakTailObserver: Bool {
		return tailPath == "self"
	}
	
	private func tailCallback(_ change: [NSKeyValueChangeKey: Any], reason: CallbackReason) {
		switch reason {
		case .cancelled:
			return
		case .targetDeleted:
			updateTailObserver(nil, isInitial: false)
			callback?(change, self.isObservingTail ? .valueChanged : .pathChanged)
		default:
			callback?(change, reason)
		}
	}
	
	private func targetValue() -> Any? {
		if let t = tailObserver, !isObservingTail {
			return t.targetValue()
		} else {
			return target.takeUnretainedValue().value(forKeyPath: key)
		}
	}
	
	private func updateTailObserverGivenChangeDictionary(_ change: [NSKeyValueChangeKey: Any]) {
		if let newValue = change[NSKeyValueChangeKey.newKey] as? NSObject {
			let value: NSObject? = newValue == NSNull() ? nil : newValue
			updateTailObserver(value, isInitial: false)
		} else {
			updateTailObserver(targetValue() as? NSObject, isInitial: false)
		}
	}
	
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context != Unmanaged.passUnretained(self).toOpaque() {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
		
		guard let c = change else {
			assertionFailure("Expected change dictionary")
			return
		}
		
		if self.isObservingTail {
			callback?(c, .valueChanged)
			if needsWeakTailObserver {
				updateTailObserverGivenChangeDictionary(c)
			}
		} else {
			var transmittedChange: [NSKeyValueChangeKey: Any] = [:]
			if !options.intersection(NSKeyValueObservingOptions.old).isEmpty {
				transmittedChange[NSKeyValueChangeKey.oldKey] = tailObserver?.targetValue() ?? NSNull()
			}
			if let _ = c[NSKeyValueChangeKey.notificationIsPriorKey] as? Bool {
				transmittedChange[NSKeyValueChangeKey.notificationIsPriorKey] = true
			}
			updateTailObserverGivenChangeDictionary(c)
			if !options.intersection(NSKeyValueObservingOptions.new).isEmpty {
				transmittedChange[NSKeyValueChangeKey.newKey] = tailObserver?.targetValue() ?? NSNull()
			}
			callback?(transmittedChange, .pathChanged)
		}
	}

	public func cancel() {
		cancel(.cancelled)
	}

	private func cancel(_ reason: CallbackReason) {
		if let c = callback {
			// Flag as inactive
			callback = nil

			// Remove the observations from this object
			if key != "self" {
				target.takeUnretainedValue().removeObserver(self, forKeyPath: key, context: Unmanaged.passUnretained(self).toOpaque())
			}
			objc_setAssociatedObject(target, Unmanaged.passUnretained(self).toOpaque(), nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN);

			// Remove tail observers
			updateTailObserver(nil, isInitial: false)
			
			// Send notifications
			if reason != .cancelled {
				c([NSKeyValueChangeKey.kindKey: NSKeyValueChange.setting.rawValue, NSKeyValueChangeKey.newKey: NSNull()], reason)
			}
		}
	}
}
