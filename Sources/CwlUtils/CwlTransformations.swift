//
//  CwlTransformations.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2018/09/09.
//  Copyright © 2018 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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
