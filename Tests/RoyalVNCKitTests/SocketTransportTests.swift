import XCTest
import Foundation
import Dispatch
@testable import RoyalVNCKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

#if !os(Windows)
final class SocketTransportTests: XCTestCase {
    func testCallbacksRemainOrderedOnConcurrentTargetQueue() async throws {
        let server = try LoopbackServer()
        let release = DispatchSemaphore(value: 0)
        server.accept { _ in _ = release.wait(timeout: .now() + 5) }
        defer { release.signal() }
        let connection = SocketNetworkConnection(settings: .init(connectionTimeout: 2, host: "127.0.0.1", port: server.port))
        let ready = expectation(description: "Ready delivered")
        let cancelled = expectation(description: "Cancelled delivered")
        let lock = NSLock()
        var notifications: [String] = []
        var activeCallbacks = 0
        connection.setStatusUpdateHandler { status in
            lock.lock()
            activeCallbacks += 1
            XCTAssertEqual(activeCallbacks, 1)
            lock.unlock()
            let name: String
            switch status {
            case .preparing: name = "preparing"; usleep(30_000)
            case .ready: name = "ready"
            case .cancelled: name = "cancelled"
            default: return XCTFail("Unexpected status")
            }
            lock.lock()
            notifications.append(name)
            activeCallbacks -= 1
            lock.unlock()
            if name == "ready" { ready.fulfill() }
            if name == "cancelled" { cancelled.fulfill() }
        }
        connection.start(queue: DispatchQueue(label: "Concurrent.status", attributes: .concurrent))
        await fulfillment(of: [ready], timeout: 2)
        connection.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(notifications, ["preparing", "ready", "cancelled"])
    }

    func testCancellationSuppressesQueuedReadyCallback() async throws {
        let server = try LoopbackServer()
        let queue = DispatchQueue(label: "Suspended.ready")
        queue.suspend()
        let cancelled = expectation(description: "Cancellation delivered")
        let connection = SocketNetworkConnection(settings: .init(connectionTimeout: 2, host: "127.0.0.1", port: server.port))
        connection.setStatusUpdateHandler { status in
            if case .cancelled = status { cancelled.fulfill() }
            else { XCTFail("Stale nonterminal callback delivered after cancellation") }
        }
        connection.start(queue: queue)
        let deadline = DispatchTime.now() + .seconds(2)
        while !connection.isReady, DispatchTime.now() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(connection.isReady)
        connection.cancel()
        queue.resume()
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testRemovedHandlerDoesNotReceiveQueuedCallbacks() async throws {
        let queue = DispatchQueue(label: "Suspended.status")
        queue.suspend()
        let noCallbacks = expectation(description: "Removed handler is not called")
        noCallbacks.isInverted = true
        let entered = expectation(description: "Resolver entered")
        let release = DispatchSemaphore(value: 0)
        let connection = SocketNetworkConnection(
            settings: .init(connectionTimeout: 2, host: "127.0.0.1", port: 1),
            resolveAddress: { host, port in
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
                return try AddressInfo(host: host, port: port)
            })
        connection.setStatusUpdateHandler { _ in noCallbacks.fulfill() }
        connection.start(queue: queue)
        await fulfillment(of: [entered], timeout: 1)
        connection.cancel()
        connection.setStatusUpdateHandler(nil)
        queue.resume()
        release.signal()
        await fulfillment(of: [noCallbacks], timeout: 0.1)
    }

    func testFragmentedReceiveHonorsMinimumLength() async throws {
        let server = try LoopbackServer()
        server.accept { client in
            _ = [UInt8(1)].withUnsafeBytes { send(client, $0.baseAddress, 1, 0) }
            usleep(30_000)
            _ = [UInt8(2), 3, 4].withUnsafeBytes { send(client, $0.baseAddress, 3, 0) }
        }
        let connection = try await connected(to: server.port)
        defer { connection.cancel() }
        let data = try await connection.read(minimumLength: 4, maximumLength: 4)
        XCTAssertEqual(data, Data([1, 2, 3, 4]))
    }

    func testCancellationUnblocksReadAndRemainsTerminal() async throws {
        let server = try LoopbackServer()
        let release = DispatchSemaphore(value: 0)
        server.accept { _ in _ = release.wait(timeout: .now() + 5) }
        defer { release.signal() }
        let connection = try await connected(to: server.port)
        let finished = expectation(description: "Pending read exits")
        let task = Task {
            do {
                _ = try await connection.read(minimumLength: 1, maximumLength: 1)
                XCTFail("Cancelled read succeeded")
            } catch { }
            finished.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(30)) { connection.cancel() }
        await fulfillment(of: [finished], timeout: 2)
        await task.value
        connection.start(queue: .global())
        if case .cancelled = connection.status {} else { XCTFail("Cancellation was not terminal") }
    }

    func testTaskCancellationUnblocksWriteUnderBackpressure() async throws {
        let server = try LoopbackServer()
        let release = DispatchSemaphore(value: 0)
        server.accept { _ in _ = release.wait(timeout: .now() + 5) }
        defer { release.signal() }
        let connection = try await connected(to: server.port)
        defer { connection.cancel() }
        let finished = expectation(description: "Blocked write exits")
        let task = Task {
            do {
                try await connection.write(data: Data(repeating: 42, count: 16 * 1024 * 1024))
                XCTFail("Cancelled write succeeded")
            } catch { }
            finished.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) { task.cancel() }
        await fulfillment(of: [finished], timeout: 2)
        connection.cancel()
        await task.value
        if case .cancelled = connection.status {} else { XCTFail("Task cancellation did not cancel connection") }
    }

    func testEOFBeforeMinimumFailsConnection() async throws {
        let server = try LoopbackServer()
        server.accept { client in
            _ = [UInt8(1)].withUnsafeBytes { send(client, $0.baseAddress, 1, 0) }
        }
        let connection = try await connected(to: server.port)
        do {
            _ = try await connection.read(minimumLength: 2, maximumLength: 2)
            XCTFail("Truncated stream succeeded")
        } catch { }
        if case .failed = connection.status {} else { XCTFail("EOF did not fail connection") }
    }

    func testExpiredConnectDeadlineIsRejected() throws {
        let server = try LoopbackServer()
        let socket = try Socket(addressInfo: AddressInfo(host: "127.0.0.1", port: server.port))
        XCTAssertThrowsError(try socket.connect(deadline: .now() - .seconds(1))) { error in
            guard case Socket.Errors.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testReadDoesNotBlockRequestWrite() async throws {
        let server = try LoopbackServer()
        server.accept { client in
            var byte: UInt8 = 0
            if recv(client, &byte, 1, 0) == 1 { _ = send(client, &byte, 1, 0) }
        }
        let connection = try await connected(to: server.port)
        defer { connection.cancel() }
        let finished = expectation(description: "Read and write complete")
        let read = Task {
            do {
                let data = try await connection.read(minimumLength: 1, maximumLength: 1)
                XCTAssertEqual(data, Data([42]))
            } catch { XCTFail("Read failed: \(error)") }
            finished.fulfill()
        }
        // Start a pending receive before sending the request it depends on.
        try await Task.sleep(nanoseconds: 30_000_000)
        try await connection.write(data: Data([42]))
        await fulfillment(of: [finished], timeout: 2)
        connection.cancel()
        await read.value
    }

    func testLargeWriteSendsEveryByte() async throws {
        let server = try LoopbackServer()
        let payload = Data((0..<(8 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
        let received = expectation(description: "Server receives full payload")
        server.accept { client in
            // Let the sender fill its kernel buffer before draining it.
            usleep(100_000)
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while data.count < payload.count {
                let count = recv(client, &buffer, buffer.count, 0)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            XCTAssertEqual(data, payload)
            received.fulfill()
        }
        let connection = try await connected(to: server.port)
        defer { connection.cancel() }
        try await connection.write(data: payload)
        await fulfillment(of: [received], timeout: 5)
    }

    func testConnectionDeadlineIncludesPendingResolution() async throws {
        let entered = expectation(description: "Resolver entered")
        let timedOut = expectation(description: "Deadline reported")
        let release = DispatchSemaphore(value: 0)
        let connection = SocketNetworkConnection(
            settings: .init(connectionTimeout: 1, host: "127.0.0.1", port: 1),
            resolveAddress: { host, port in
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
                return try AddressInfo(host: host, port: port)
            })
        defer { release.signal(); connection.cancel() }
        connection.setStatusUpdateHandler { status in
            if case .failed(let error) = status,
               case Socket.Errors.timedOut = error { timedOut.fulfill() }
        }
        connection.start(queue: DispatchQueue(label: "Timeout.status"))
        await fulfillment(of: [entered, timedOut], timeout: 3)
        release.signal()
        if case .failed = connection.status {} else { XCTFail("Deadline did not fail connection") }
    }

    func testCancellationDuringResolutionCannotBecomeReady() async throws {
        let server = try LoopbackServer()
        let entered = expectation(description: "Resolver entered")
        let exited = expectation(description: "Resolver returned")
        let cancelled = expectation(description: "Cancelled reported")
        let release = DispatchSemaphore(value: 0)
        let connection = SocketNetworkConnection(
            settings: .init(connectionTimeout: 2, host: "127.0.0.1", port: server.port),
            resolveAddress: { host, port in
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
                defer { exited.fulfill() }
                return try AddressInfo(host: host, port: port)
            })
        defer { release.signal() }
        connection.setStatusUpdateHandler { status in
            if case .cancelled = status { cancelled.fulfill() }
            if case .ready = status { XCTFail("Cancelled connection became ready") }
        }
        connection.start(queue: DispatchQueue(label: "Cancel.status"))
        await fulfillment(of: [entered], timeout: 1)
        connection.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        release.signal()
        await fulfillment(of: [exited], timeout: 1)
        if case .cancelled = connection.status {} else { XCTFail("Cancellation was not terminal") }
    }

    private func connected(to port: UInt16) async throws -> SocketNetworkConnection {
        let connection = SocketNetworkConnection(settings: .init(connectionTimeout: 2, host: "127.0.0.1", port: port))
        let ready = expectation(description: "Connected")
        connection.setStatusUpdateHandler { status in
            if case .ready = status { ready.fulfill() }
            if case .failed(let error) = status { XCTFail("Connect failed: \(error)") }
        }
        connection.start(queue: DispatchQueue(label: "Test.status"))
        await fulfillment(of: [ready], timeout: 3)
        connection.setStatusUpdateHandler(nil)
        return connection
    }
}

private final class LoopbackServer {
    let descriptor: Int32
    let port: UInt16

    init() throws {
        let descriptor: Int32
#if canImport(Glibc)
        descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
#endif
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 4) == 0 else {
            close(descriptor)
            throw POSIXError(.EIO)
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard result == 0 else { close(descriptor); throw POSIXError(.EIO) }
        self.descriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    func accept(_ body: @escaping (Int32) -> Void) {
        let descriptor = descriptor
        DispatchQueue.global().async {
#if canImport(Darwin)
            let client = Darwin.accept(descriptor, nil, nil)
#elseif canImport(Glibc)
            let client = Glibc.accept(descriptor, nil, nil)
#elseif canImport(Android)
            let client = Android.accept(descriptor, nil, nil)
#endif
            guard client >= 0 else { XCTFail("Accept failed"); return }
            defer { close(client) }
            body(client)
        }
    }

    deinit { close(descriptor) }
}
#endif
