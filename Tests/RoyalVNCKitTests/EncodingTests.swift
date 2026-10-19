import Foundation
import XCTest
@testable import RoyalVNCKit

final class EncodingTests: XCTestCase {
    private let color: [UInt8] = [0x33, 0x22, 0x11, 0]

    private func connection() -> VNCConnection {
        VNCConnection(settings: .init(isDebugLoggingEnabled: false, hostname: "localhost", port: 5900,
                                     isShared: true, isScalingEnabled: false, useDisplayLink: false,
                                     inputMode: .none, isClipboardRedirectionEnabled: false,
                                     colorDepth: .depth24Bit, frameEncodings: .default),
                      logger: VNCPrintLogger())
    }

    private func framebuffer() throws -> VNCFramebuffer {
        try VNCFramebuffer(logger: VNCPrintLogger(), size: .init(width: 4, height: 4),
                           screens: [], pixelFormat: .init(depth: 24),
                           allocator: VNCFramebufferMallocAllocator())
    }

    func testRegistryMatchesWireEncodingIdentifiers() throws {
        let connection = connection()
        for (identifier, decoder) in connection.encodings {
            XCTAssertEqual(identifier, decoder.encodingType, "Decoder registered for the wrong wire identifier")
        }
        for encoding in VNCFrameEncodingType.defaultFrameEncodings + [.raw, .copyRect] {
            XCTAssertNotNil(connection.encodings[encoding.rawValue])
        }
    }

    func testEveryAdvertisedFrameEncodingDecodesFragmentedUpdates() async throws {
        // Deflate fixtures produced with Python zlib.compressobj + Z_SYNC_FLUSH.
        // Zlib contains four BGRX pixels; ZRLE contains a solid tile (1) and one BGR pixel.
        let zlib = Array(Data(base64Encoded: "eJwyVhJkMEbCAAAAAP//")!)
        let zrle = Array(Data(base64Encoded: "eJxiNFYSBAAAAP//")!)
        let fixtures: [(VNCFrameEncodingType, [UInt8])] = [
            (.raw, Array(repeating: color, count: 4).flatMap { $0 }),
            (.copyRect, [0, 0, 0, 0]),
            (.rre, [0, 0, 0, 1] + [0, 0, 0, 0] + color + [0, 0, 0, 0, 0, 2, 0, 2]),
            (.coRRE, [0, 0, 0, 1] + [0, 0, 0, 0] + color + [0, 0, 2, 2]),
            (.hextile, [14] + [0, 0, 0, 0] + color + [1, 0, 0x11]),
            (.zlib, lengthPrefix(zlib)),
            (.zrle, lengthPrefix(zrle)),
            (.tight, [0x80, 0x11, 0x22, 0x33])
        ]
        XCTAssertEqual(Set(fixtures.map { $0.0 }), Set(VNCFrameEncodingType.defaultFrameEncodings + [.raw, .copyRect]))

        for (encoding, body) in fixtures {
            let framebuffer = try framebuffer()
            if encoding == .copyRect {
                var pixel = Data(color)
                framebuffer.fill(region: .init(x: 0, y: 0, width: 2, height: 2), withPixel: &pixel)
            }
            // A second rectangle ensures the first decoder consumed exactly its wire payload.
            let packet = [UInt8]([0, 0, 2])
                + header(x: 2, y: 2, width: 2, height: 2, encoding: encoding)
                + body
                + header(x: 0, y: 3, width: 1, height: 1, encoding: .raw)
                + [0x66, 0x55, 0x44, 0]
            let reader = FragmentedEncodingReader(packet)
            let update = try await VNCProtocol.FramebufferUpdate.receive(
                connection: reader, framebuffer: framebuffer, encodings: connection().encodings,
                logger: VNCPrintLogger())
            XCTAssertEqual(update.rectangles.count, 2, "\(encoding)")
            XCTAssertEqual(reader.remaining, 0, "\(encoding) left unread bytes")
            let pixels = framebuffer.surfaceAddress.assumingMemoryBound(to: UInt8.self)
            for y in 2..<4 {
                for x in 2..<4 {
                    let offset = (y * 4 + x) * 4
                    XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels + offset, count: 3)),
                                   Array(color.prefix(3)), "\(encoding) pixel \(x),\(y)")
                }
            }
            XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels + 3 * 4 * 4, count: 3)), [0x66, 0x55, 0x44])
            XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels + 2 * 4, count: 3)), [0, 0, 0],
                           "\(encoding) modified pixels outside the rectangle")
        }
    }

    func testTruncatedRawAndCoRREUpdatesThrow() async throws {
        for encoding: VNCFrameEncodingType in [.raw, .coRRE] {
            let body: [UInt8] = encoding == .raw
                ? Array(repeating: color, count: 4).flatMap { $0 }
                : [0, 0, 0, 1] + [0, 0, 0, 0] + color + [0, 0, 2, 2]
            let reader = FragmentedEncodingReader([0, 0, 1]
                + header(x: 2, y: 2, width: 2, height: 2, encoding: encoding) + body.dropLast())
            do {
                _ = try await VNCProtocol.FramebufferUpdate.receive(
                    connection: reader, framebuffer: framebuffer(), encodings: connection().encodings,
                    logger: VNCPrintLogger())
                XCTFail("\(encoding) accepted a truncated rectangle")
            } catch FragmentedEncodingReader.EndOfInput.truncated {
                // Expected: a short server message must not be treated as a complete frame.
            }
        }
    }

    private func lengthPrefix(_ bytes: [UInt8]) -> [UInt8] {
        let count = UInt32(bytes.count)
        return [UInt8(count >> 24), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)] + bytes
    }

    private func header(x: UInt16, y: UInt16, width: UInt16, height: UInt16,
                        encoding: VNCFrameEncodingType) -> [UInt8] {
        let geometry = [x, y, width, height].flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }
        let id = UInt32(encoding.rawValue.rawValue)
        return geometry + [UInt8(id >> 24), UInt8((id >> 16) & 255), UInt8((id >> 8) & 255), UInt8(id & 255)]
    }
}

private final class FragmentedEncodingReader: NetworkConnectionReading {
    enum EndOfInput: Error { case truncated }
    private let bytes: [UInt8]
    private var offset = 0
    var remaining: Int { bytes.count - offset }

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard remaining >= minimumLength else { throw EndOfInput.truncated }
        // Exercise the actual readBuffered aggregation with tiny network fragments.
        let length = min(remaining, maximumLength, max(minimumLength, 1))
        defer { offset += length }
        return Data(bytes[offset..<(offset + length)])
    }
}
