//
//  CwlTransformations.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2018/09/09.
//  Copyright © 2018 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

public extension Date {
	/// A convenience for Date that allows string transformations in a functional transformation aesthetic
	func localizedString(dateStyle dstyle: DateFormatter.Style = .none, timeStyle tstyle: DateFormatter.Style = .none) -> String {
		return DateFormatter.localizedString(from: self, dateStyle: dstyle, timeStyle: tstyle)
	}
}

extension String {
	/// A convenience that makes localized formatting a transformation on the format string
	func lFormat(_ args: CVarArg...) -> String {
		return String(format: self, locale: .current, arguments: args)
	}
}
