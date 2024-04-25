//
//  NTExtensions.swift
//
//
//  Created by Cole M on 4/25/24.
//

import Foundation
import BSON
import NIOCore
import NIOFoundationCompat
import NIOConcurrencyHelpers



extension NIOLock: Sendable {
    @inlinable
    public func withSendableLock<T: Sendable>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }
    
    @inlinable
    public func withSendableAsyncLock<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try await body()
    }
}


extension BSONDecoder {
    enum Errors: Error, Sendable {
        case nilData
    }
    public func decodeString<T: Codable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = Data(base64Encoded: string) else { throw Errors.nilData }
        let buffer = ByteBuffer(data: data)
        return try decode(type, from: Document(buffer: buffer))
    }

    public func decodeData<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let buffer = ByteBuffer(data: data)
        return try decode(type, from: Document(buffer: buffer))
    }

    public func decodeBuffer<T: Codable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        return try decode(type, from: Document(buffer: buffer))
    }
}

extension BSONEncoder {
    public func encodeString<T: Codable>(_ encodable: T) throws -> String {
        try encode(encodable).makeData().base64EncodedString()
    }

    public func encodeData<T: Codable>(_ encodable: T) throws -> Data {
        try encode(encodable).makeData()
    }
}
