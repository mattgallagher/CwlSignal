//
//  CwlCaseNameCodable.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 9/3/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation

private struct EmptyKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
	typealias Key = K
	
	var codingPath: [CodingKey] { return [] }
	var allKeys: [K] { return [] }
	
	func contains(_ key: K) -> Bool {
		return false
	}
	
	private func keyNotFoundError(_ key: K) -> Error {
		return DecodingError.keyNotFound(key, DecodingError.Context.init(codingPath: [], debugDescription: "EmptyKeyedDecodingContainer contains no values"))
	}
	
	func decodeNil(forKey key: K) throws -> Bool { throw keyNotFoundError(key) }
	func decode(_ type: Bool.Type, forKey key: K) throws -> Bool { throw keyNotFoundError(key) }
	func decode(_ type: String.Type, forKey key: K) throws -> String { throw keyNotFoundError(key) }
	func decode(_ type: Double.Type, forKey key: K) throws -> Double { throw keyNotFoundError(key) }
	func decode(_ type: Float.Type, forKey key: K) throws -> Float { throw keyNotFoundError(key) }
	func decode(_ type: Int.Type, forKey key: K) throws -> Int { throw keyNotFoundError(key) }
	func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 { throw keyNotFoundError(key) }
	func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 { throw keyNotFoundError(key) }
	func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 { throw keyNotFoundError(key) }
	func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 { throw keyNotFoundError(key) }
	func decode(_ type: UInt.Type, forKey key: K) throws -> UInt { throw keyNotFoundError(key) }
	func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 { throw keyNotFoundError(key) }
	func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 { throw keyNotFoundError(key) }
	func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 { throw keyNotFoundError(key) }
	func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 { throw keyNotFoundError(key) }
	func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : Decodable { throw keyNotFoundError(key) }
	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey { throw keyNotFoundError(key)	}
	func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer { throw keyNotFoundError(key) }
	func superDecoder() throws -> Decoder { fatalError() }
	func superDecoder(forKey key: K) throws -> Decoder { throw keyNotFoundError(key) }
}

public extension KeyedDecodingContainer {
	static func empty() -> KeyedDecodingContainer<K> {
		return KeyedDecodingContainer<K>(EmptyKeyedDecodingContainer())
	}
}

/// A protocol that enums with associated values can adopt to help in implementing Codable conformance.
/// The downside is that there are some runtime enforced requirements:
///  1. the `CaseName` associated type must be raw constructible from each of the case names in `CaseNameCodable`
///  2. the `decode(from:)` method must validly construct each `CaseNameCodable`
/// NOTE: the encoded value will be `nil` if the associated value has no contents or there is no associated value. In these cases, you shouldn't attempt to read the value.
public protocol CaseNameCodable: Codable {
	associatedtype CaseName: CaseNameDecoder where CaseName.AssociatedEnum == Self
}

public protocol CaseNameDecoder: Codable, CodingKey, RawRepresentable where RawValue == String {
	associatedtype AssociatedEnum
	func decode(from container: KeyedDecodingContainer<Self>) throws -> AssociatedEnum
}

public extension CaseNameCodable {
	private func caseName(from mirror: Mirror) -> CaseName {
		let label = mirror.children.first?.label ?? String(describing: self)
		guard let key = CaseName(rawValue: label) else {
			fatalError("Unable to find a CaseName for \(self) matching \(label)")
		}
		return key
	}
	
	var caseName: CaseName {
		return caseName(from: Mirror(reflecting: self))
	}
	
	func encode(to encoder: Encoder) throws {
		let mirror = Mirror(reflecting: self)
		let key = caseName(from: mirror)
		var container = encoder.container(keyedBy: CaseName.self)
		if let value = mirror.children.first?.value as? Encodable {
			try container.encode(EncodableWrapper(value: value), forKey: key)
		} else {
			try container.encodeNil(forKey: key)
		}
	}
	
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CaseName.self)
		guard let key = container.allKeys.first else {
			throw DecodingError.dataCorrupted(DecodingError.Context.init(codingPath: decoder.codingPath, debugDescription: "Missing enum key"))
		}
		self = try key.decode(from: container)
	}
}

private struct EncodableWrapper: Encodable {
	let value: Encodable
	
	func encode(to encoder: Encoder) throws {
		try value.encode(to: encoder)
	}
}
