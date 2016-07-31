//
//  CwlDispatch.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/07/29.
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

extension DispatchQueue {
	// Similar to `sync` but returning a value from inside the mutex.
	public func access<T>(block: () throws -> T) rethrows -> T {
		var t: T?
		try sync {
			try t = block()
		}
		return t!
	}
}

public extension DispatchSource {
	// An overload of timer that immediately sets the handler and schedules the timer
	public class func timer(interval: DispatchTimeInterval, queue: DispatchQueue, handler: () -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.timer(queue: queue)
		result.setEventHandler(handler: handler)
		result.scheduleOneshot(deadline: DispatchTime.now() + interval)
		result.resume()
		return result
	}
	
	// An overload of timer that always uses the default global queue (because it is intended to enter the appropriate mutex as a separate step) and passes a user-supplied Int to the handler function to allow ignoring callbacks if cancelled or rescheduled before mutex acquisition.
	public class func timer<T>(interval: DispatchTimeInterval, parameter: T, handler:
		(T) -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.timer(queue: DispatchQueue.global())
		result.scheduleOneshot(interval: interval, parameter: parameter, handler: handler)
		result.resume()
		return result
	}
}

public extension DispatchSourceTimer {
	// An overload of scheduleOneshot that updates the handler function with a new user-supplied Int when it changes the expiry deadline
	public func scheduleOneshot<T>(interval: DispatchTimeInterval, parameter: T, handler:
		(T) -> Void) {
		suspend()
		setEventHandler { handler(parameter) }
		scheduleOneshot(deadline: DispatchTime.now() + interval)
		resume()
	}
}
