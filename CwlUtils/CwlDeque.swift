//
//  CwlDeque.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/09/13.
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

let DequeOverAllocateFactor = 2
let DequeDownsizeTriggerFactor = 16
let DequeDefaultMinimumCapacity = 0

public struct Deque<T>: RandomAccessCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral, CustomDebugStringConvertible {
	public typealias Index = Int
	public typealias Indices = CountableRange<Int>
	public typealias Element = T
	
	var buffer: DequeBuffer<T>? = nil
	let minCapacity: Int
	
	public init() {
		self.minCapacity = DequeDefaultMinimumCapacity
	}
	
	public init(minCapacity: Int) {
		self.minCapacity = minCapacity
	}
	
	public init(arrayLiteral: T...) {
		self.minCapacity = DequeDefaultMinimumCapacity
		replaceSubrange(0..<0, with: arrayLiteral)
	}
	
	public var debugDescription: String {
		var result = "\(type(of: self))(["
		var iterator = makeIterator()
		if let n = iterator.next() {
			debugPrint(n, terminator: "", to: &result)
			while let n = iterator.next() {
				result += ", "
				debugPrint(n, terminator: "", to: &result)
			}
		}
		result += "])"
		return result
	}
	
	public subscript(_ at: Index) -> T {
		get {
			if let b = buffer {
				return b.withUnsafeMutablePointers { header, body -> T in
					precondition(at < header.pointee.count)
					var offset = header.pointee.offset + at
					if offset >= header.pointee.capacity {
						offset -= header.pointee.capacity
					}
					return body[offset]
				}
			} else {
				preconditionFailure("Index beyond end of queue")
			}
		}
	}
	
	public var startIndex: Index {
		return 0
	}
	
	public var endIndex: Index {
		if let b = buffer {
			return b.withUnsafeMutablePointerToHeader { header -> Int in
				return header.pointee.count
			}
		}
		
		return 0
	}
	
	public mutating func append(_ newElement: T) {
		if let b = buffer {
			let done = b.withUnsafeMutablePointers { header, body -> Bool in
				if header.pointee.capacity >= header.pointee.count + 1 {
					var index = header.pointee.offset + header.pointee.count
					if index > header.pointee.capacity {
						index -= header.pointee.capacity
					}
					body.advanced(by: index).initialize(to: newElement)
					header.pointee.count += 1
					return true
				}
				return false
			}
			if done {
				return
			}
		}
		
		let index = endIndex
		return replaceSubrange(index..<index, with: CollectionOfOne(newElement))
	}
	
	public mutating func insert(_ newElement: T, at: Int) {
		if let b = buffer {
			let done = b.withUnsafeMutablePointers { header, body -> Bool in
				if at == 0, header.pointee.capacity >= header.pointee.count + 1 {
					var index = header.pointee.offset - 1
					if index < 0 {
						index += header.pointee.capacity
					}
					body.advanced(by: index).initialize(to: newElement)
					header.pointee.count += 1
					header.pointee.offset = index
					return true
				}
				return false
			}
			if done {
				return
			}
		}
		
		return replaceSubrange(at..<at, with: CollectionOfOne(newElement))
	}
	
	public mutating func remove(at: Int) {
		if let b = buffer {
			let done = b.withUnsafeMutablePointerToHeader { header -> Bool in
				if at == header.pointee.count - 1 {
					header.pointee.count -= 1
					return true
				} else if at == 0, header.pointee.count > 0 {
					header.pointee.offset += 1
					if header.pointee.offset >= header.pointee.capacity {
						header.pointee.offset -= header.pointee.capacity
					}
					header.pointee.count -= 1
					return true
				}
				return false
			}
			if done {
				return
			}
		}
		
		return replaceSubrange(at...at, with: EmptyCollection())
	}
	
	fileprivate static func deinitialize(range: CountableRange<Int>, header: UnsafeMutablePointer<DequeHeader>, body: UnsafeMutablePointer<T>) {
		let splitRange = Deque.indices(forRange: range, header: header)
		body.advanced(by: splitRange.low.startIndex).deinitialize(count: splitRange.low.count)
		body.advanced(by: splitRange.high.startIndex).deinitialize(count: splitRange.high.count)
	}

	fileprivate static func moveInitialize(sourceRange: CountableRange<Int>, destinationRange: CountableRange<Int>, sourceHeader: UnsafeMutablePointer<DequeHeader>, destinationHeader: UnsafeMutablePointer<DequeHeader>, sourceBody: UnsafeMutablePointer<T>, destinationBody: UnsafeMutablePointer<T>) {
		let sourceSplitRange = Deque.indices(forRange: sourceRange, header: sourceHeader)
		let destinationSplitRange = Deque.indices(forRange: destinationRange, header: destinationHeader)
		destinationBody.advanced(by: destinationSplitRange.low.startIndex).moveInitialize(from: sourceBody.advanced(by: sourceSplitRange.low.startIndex), count: sourceSplitRange.low.count)
		destinationBody.advanced(by: destinationSplitRange.high.startIndex).moveInitialize(from: sourceBody.advanced(by: sourceSplitRange.high.startIndex), count: sourceSplitRange.high.count)
	}

	fileprivate static func copyInitialize(sourceRange: CountableRange<Int>, destinationRange: CountableRange<Int>, sourceHeader: UnsafeMutablePointer<DequeHeader>, destinationHeader: UnsafeMutablePointer<DequeHeader>, sourceBody: UnsafeMutablePointer<T>, destinationBody: UnsafeMutablePointer<T>) {
		let sourceSplitRange = Deque.indices(forRange: sourceRange, header: sourceHeader)
		let destinationSplitRange = Deque.indices(forRange: destinationRange, header: destinationHeader)
		destinationBody.advanced(by: destinationSplitRange.low.startIndex).initialize(from: sourceBody.advanced(by: sourceSplitRange.low.startIndex), count: sourceSplitRange.low.count)
		destinationBody.advanced(by: destinationSplitRange.high.startIndex).initialize(from: sourceBody.advanced(by: sourceSplitRange.high.startIndex), count: sourceSplitRange.high.count)
	}

	fileprivate static func indices(forRange: CountableRange<Int>, header: UnsafeMutablePointer<DequeHeader>) -> (low: CountableRange<Int>, high: CountableRange<Int>) {
		let limit = header.pointee.capacity - header.pointee.offset
		if forRange.startIndex >= limit {
			return (low: (forRange.startIndex - limit)..<(forRange.endIndex - limit), high: (forRange.endIndex - limit)..<(forRange.endIndex - limit))
		} else if forRange.endIndex > limit {
			return (low: (forRange.startIndex + header.pointee.offset)..<header.pointee.capacity, high: 0..<(forRange.endIndex - limit))
		}
		return (low: (forRange.startIndex + header.pointee.offset)..<(forRange.endIndex + header.pointee.offset), high: (forRange.endIndex + header.pointee.offset)..<(forRange.endIndex + header.pointee.offset))
	}
	
	private static func mutateWithoutReallocate<C>(info: DequeMutationInfo, elements newElements: C, header: UnsafeMutablePointer<DequeHeader>, body: UnsafeMutablePointer<T>) where C: Collection, C.Iterator.Element == T {
		if info.removed > 0 {
			Deque.deinitialize(range: info.start..<(info.start + info.removed), header: header, body: body)
		}

		if info.removed != info.inserted {
			if info.start < header.pointee.count - (info.start + info.removed) {
				let oldOffset = header.pointee.offset
				header.pointee.offset -= info.inserted - info.removed
				if header.pointee.offset < 0 {
					header.pointee.offset += header.pointee.capacity
				} else if header.pointee.offset >= header.pointee.count {
					header.pointee.offset -= header.pointee.capacity
				}
				let delta = oldOffset - header.pointee.offset
				if info.start != 0 {
					Deque.moveInitialize(sourceRange: delta..<(info.start + delta), destinationRange: 0..<info.start, sourceHeader: header, destinationHeader: header, sourceBody: body, destinationBody: body)
				}
			} else {
				if (info.start + info.removed) != header.pointee.count {
					Deque.moveInitialize(sourceRange: (info.start + info.removed)..<header.pointee.count, destinationRange: (info.start + info.inserted)..<(header.pointee.count - info.removed + info.inserted), sourceHeader: header, destinationHeader: header, sourceBody: body, destinationBody: body)
				}
			}
			header.pointee.count = header.pointee.count - info.removed + info.inserted
		}
		
		if info.inserted == 1, let e = newElements.first {
			if info.start >= header.pointee.capacity - header.pointee.offset {
				body.advanced(by: info.start - header.pointee.capacity + header.pointee.offset).initialize(to: e)
			} else {
				body.advanced(by: header.pointee.offset + info.start).initialize(to: e)
			}
		} else if info.inserted > 0 {
			let inserted = Deque.indices(forRange: info.start..<(info.start + info.inserted), header: header)
			var iterator = newElements.makeIterator()
			for i in inserted.low {
				if let n = iterator.next() {
					body.advanced(by: i).initialize(to: n)
				}
			}
			for i in inserted.high {
				if let n = iterator.next() {
					body.advanced(by: i).initialize(to: n)
				}
			}
		}
	}

	private mutating func reallocateAndMutate<C>(info: DequeMutationInfo, elements newElements: C, header: UnsafeMutablePointer<DequeHeader>?, body: UnsafeMutablePointer<T>?, deletePrevious: Bool) where C: Collection, C.Iterator.Element == T {
		if info.newCount == 0 {
			// Let the regular deallocation handle the deinitialize
			buffer = nil
		} else {
			let newCapacity: Int
			let oldCapacity = header?.pointee.capacity ?? 0
			if info.newCount > oldCapacity || info.newCount <= oldCapacity / DequeDownsizeTriggerFactor {
				newCapacity = Swift.max(minCapacity, info.newCount * DequeOverAllocateFactor)
			} else {
				newCapacity = oldCapacity
			}
			
			let newBuffer = DequeBuffer<T>.create(capacity: newCapacity, count: info.newCount)
			if let headerPtr = header, let bodyPtr = body {
				if deletePrevious, info.removed > 0 {
					Deque.deinitialize(range: info.start..<(info.start + info.removed), header: headerPtr, body: bodyPtr)
				}

				newBuffer.withUnsafeMutablePointers { newHeader, newBody in
					if info.start != 0 {
						if deletePrevious {
							Deque.moveInitialize(sourceRange: 0..<info.start, destinationRange: 0..<info.start, sourceHeader: headerPtr, destinationHeader: newHeader, sourceBody: bodyPtr, destinationBody: newBody)
						} else {
							Deque.copyInitialize(sourceRange: 0..<info.start, destinationRange: 0..<info.start, sourceHeader: headerPtr, destinationHeader: newHeader, sourceBody: bodyPtr, destinationBody: newBody)
						}
					}
					
					let oldCount = header?.pointee.count ?? 0
					if info.start + info.removed != oldCount {
						if deletePrevious {
							Deque.moveInitialize(sourceRange: (info.start + info.removed)..<oldCount, destinationRange: (info.start + info.inserted)..<info.newCount, sourceHeader: headerPtr, destinationHeader: newHeader, sourceBody: bodyPtr, destinationBody: newBody)
						} else {
							Deque.copyInitialize(sourceRange: (info.start + info.removed)..<oldCount, destinationRange: (info.start + info.inserted)..<info.newCount, sourceHeader: headerPtr, destinationHeader: newHeader, sourceBody: bodyPtr, destinationBody: newBody)
						}
					}
				}
				
				// Make sure the old buffer doesn't deinitialize when it deallocates.
				if deletePrevious {
					headerPtr.pointee.count = 0
				}
			}

			if info.inserted > 0 {
				// Insert the new subrange
				newBuffer.withUnsafeMutablePointerToElements { body in
					body.advanced(by: info.start).initialize(from: newElements)
				}
			}

			buffer = newBuffer
		}
	}

	public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C: Collection, C.Iterator.Element == T {
		precondition(subrange.lowerBound >= 0, "Subrange lowerBound is negative")
		
		if isKnownUniquelyReferenced(&buffer), let b = buffer {
			b.withUnsafeMutablePointers { header, body in
				let info = DequeMutationInfo(subrange: subrange, previousCount: header.pointee.count, insertedCount: numericCast(newElements.count))
				if info.newCount <= header.pointee.capacity && (info.newCount < minCapacity || info.newCount > header.pointee.capacity / DequeDownsizeTriggerFactor) {
					Deque.mutateWithoutReallocate(info: info, elements: newElements, header: header, body: body)
				} else {
					reallocateAndMutate(info: info, elements: newElements, header: header, body: body, deletePrevious: true)
				}
			}
		} else if let b = buffer {
			b.withUnsafeMutablePointers { header, body in
				let info = DequeMutationInfo(subrange: subrange, previousCount: header.pointee.count, insertedCount: numericCast(newElements.count))
				reallocateAndMutate(info: info, elements: newElements, header: header, body: body, deletePrevious: false)
			}
		} else {
			let info = DequeMutationInfo(subrange: subrange, previousCount: 0, insertedCount: numericCast(newElements.count))
			reallocateAndMutate(info: info, elements: newElements, header: nil, body: nil, deletePrevious: true)
		}
	}
}

final class DequeBuffer<T>: ManagedBuffer<DequeHeader, T> {
	class func create(capacity: Int, count: Int) -> DequeBuffer<T> {
		let p = ManagedBufferPointer<DequeHeader, T>(bufferClass: self, minimumCapacity: capacity) { buffer, capacityFunction in
			DequeHeader(offset: 0, count: count, capacity: capacity)
		}
			
		return unsafeDowncast(p.buffer, to: DequeBuffer<T>.self)
	}
	deinit {
		withUnsafeMutablePointers { header, body in
			Deque<T>.deinitialize(range: 0..<header.pointee.count, header: header, body: body)
		}
	}
}

struct DequeHeader {
	var offset: Int
	var count: Int
	var capacity: Int
}

struct DequeMutationInfo {
	let start: Int
	let removed: Int
	let inserted: Int
	let newCount: Int
	
	init(subrange: Range<Int>, previousCount: Int, insertedCount: Int) {
		precondition(subrange.upperBound <= previousCount, "Subrange upperBound is out of range")

		self.start = subrange.lowerBound
		self.removed = subrange.count
		self.inserted = insertedCount
		self.newCount = previousCount - self.removed + self.inserted
	}
}
