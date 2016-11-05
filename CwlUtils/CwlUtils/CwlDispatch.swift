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

public extension DispatchSource {
	// An overload of timer that immediately sets the handler and schedules the timer
	public class func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue, handler: @escaping () -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.makeTimerSource(queue: queue)
		result.setEventHandler(handler: handler)
		result.scheduleOneshot(deadline: DispatchTime.now() + interval, leeway: leeway)
		result.resume()
		return result
	}
	
	// An overload of timer that always uses the default global queue (because it is intended to enter the appropriate mutex as a separate step) and passes a user-supplied Int to the handler function to allow ignoring callbacks if cancelled or rescheduled before mutex acquisition.
	public class func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue = DispatchQueue.global(), handler: @escaping (T) -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.makeTimerSource(queue: queue)
		result.scheduleOneshot(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		result.resume()
		return result
	}

	// An overload of timer that immediately sets the handler and schedules the timer
	public class func repeatingTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue = DispatchQueue.global(), handler: @escaping () -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.makeTimerSource(queue: queue)
		result.setEventHandler(handler: handler)
		result.scheduleRepeating(deadline: DispatchTime.now() + interval, interval: interval, leeway: leeway)
		result.resume()
		return result
	}
	
	// An overload of timer that always uses the default global queue (because it is intended to enter the appropriate mutex as a separate step) and passes a user-supplied Int to the handler function to allow ignoring callbacks if cancelled or rescheduled before mutex acquisition.
	public class func repeatingTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), queue: DispatchQueue = DispatchQueue.global(), handler: @escaping (T) -> Void) -> DispatchSourceTimer {
		let result = DispatchSource.makeTimerSource(queue: queue)
		result.scheduleRepeating(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		result.resume()
		return result
	}
}

public extension DispatchSourceTimer {
	// An overload of scheduleOneshot that updates the handler function with a new user-supplied parameter when it changes the expiry deadline
	public func scheduleOneshot<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) {
		suspend()
		setEventHandler { handler(parameter) }
		scheduleOneshot(deadline: DispatchTime.now() + interval, leeway: leeway)
		resume()
	}
	
	// An overload of scheduleOneshot that updates the handler function with a new user-supplied parameter when it changes the expiry deadline
	public func scheduleRepeating<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) {
		suspend()
		setEventHandler { handler(parameter) }
		scheduleRepeating(deadline: DispatchTime.now() + interval, interval: interval, leeway: leeway)
		resume()
	}
}

public extension DispatchTime {
	public func since(_ previous: DispatchTime) -> DispatchTimeInterval {
		return .nanoseconds(Int(uptimeNanoseconds - previous.uptimeNanoseconds))
	}
}

public extension DispatchTimeInterval {
	public static func fromSeconds(_ seconds: Double) -> DispatchTimeInterval {
		return .nanoseconds(Int(seconds * Double(NSEC_PER_SEC)))
	}

	public func toSeconds() -> Double {
		switch self {
		case .seconds(let t): return Double(t)
		case .milliseconds(let t): return (1.0 / Double(NSEC_PER_MSEC)) * Double(t)
		case .microseconds(let t): return (1.0 / Double(NSEC_PER_USEC)) * Double(t)
		case .nanoseconds(let t): return (1.0 / Double(NSEC_PER_SEC)) * Double(t)
		}
	}

	public func toNanoseconds() -> Int {
		switch self {
		case .seconds(let t): return Int(NSEC_PER_SEC) * t
		case .milliseconds(let t): return Int(NSEC_PER_MSEC) * t
		case .microseconds(let t): return Int(NSEC_PER_USEC) * t
		case .nanoseconds(let t): return t
		}
	}
}
