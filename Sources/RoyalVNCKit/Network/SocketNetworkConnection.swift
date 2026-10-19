#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

final class SocketNetworkConnection: NetworkConnection, @unchecked Sendable {
    let settings: NetworkConnectionSettings
    private let resolveAddress: (String, UInt16) throws -> AddressInfo
#if canImport(Glibc) || canImport(Android) || canImport(WinSDK)
    private let lock = Spinlock()
#else
    private let lock = NSLock()
#endif
    private var socket: Socket?
    private var queue = DispatchQueue(label: "RoyalVNCKit.Socket.status")
    private let readQueue = DispatchQueue(label: "RoyalVNCKit.Socket.read")
    private let writeQueue = DispatchQueue(label: "RoyalVNCKit.Socket.write")
    private var handler: NetworkConnectionStatusUpdateHandler?
    private var state: NetworkConnectionStatus = .setup
    private var started = false
    private var terminal = false
    private var initializationError: Error?

    var status: NetworkConnectionStatus {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    convenience init(settings: NetworkConnectionSettings) {
        self.init(settings: settings, resolveAddress: { try AddressInfo(host: $0, port: $1) })
    }

    init(settings: NetworkConnectionSettings,
         resolveAddress: @escaping (String, UInt16) throws -> AddressInfo) {
#if os(Windows)
        do {
            try Winsock.intializeWinsock()
        } catch {
            initializationError = error
        }
#endif
        self.settings = settings
        self.resolveAddress = resolveAddress
    }

    func setStatusUpdateHandler(_ handler: NetworkConnectionStatusUpdateHandler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// Caller holds the lock; enqueuing here preserves notification order.
    private func updateStatus(_ status: NetworkConnectionStatus) {
        state = status
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let handler = self.handler
            let shouldDeliver: Bool
            switch status {
            case .cancelled, .failed: shouldDeliver = true
            default: shouldDeliver = !self.terminal
            }
            self.lock.unlock()
            if shouldDeliver { handler?(status) }
        }
    }

    func cancel() {
        lock.lock()
        guard !terminal else { lock.unlock(); return }
        terminal = true
        let socket = self.socket
        self.socket = nil
        updateStatus(.cancelled)
        lock.unlock()
        socket?.cancel()
    }

    private func fail(_ error: Error) {
        lock.lock()
        guard !terminal else { lock.unlock(); return }
        terminal = true
        let socket = self.socket
        self.socket = nil
        updateStatus(.failed(error))
        lock.unlock()
        socket?.cancel()
    }

    func start(queue: DispatchQueue) {
        lock.lock()
        guard !started, !terminal else { lock.unlock(); return }
        started = true
        self.queue = DispatchQueue(label: "RoyalVNCKit.Socket.status", target: queue)
        updateStatus(.preparing)
        lock.unlock()

        if let initializationError {
            fail(initializationError)
            return
        }

        // Timeout includes DNS resolution. getaddrinfo itself cannot be interrupted,
        // but a late result cannot publish a socket or revive a timed-out connection.
        let deadline: DispatchTime? = settings.connectionTimeout > 0
            ? .now() + .seconds(settings.connectionTimeout) : nil
        if let deadline {
            DispatchQueue.global().asyncAfter(deadline: deadline) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                guard !self.terminal, !self.isReadyLocked else { self.lock.unlock(); return }
                self.terminal = true
                let socket = self.socket
                self.socket = nil
                self.updateStatus(.failed(Socket.Errors.timedOut))
                self.lock.unlock()
                socket?.cancel()
            }
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            do {
                let addressInfo = try self.resolveAddress(self.settings.host, self.settings.port)
                self.lock.lock()
                guard !self.terminal else { self.lock.unlock(); return }
                self.lock.unlock()
                let socket = try Socket(addressInfo: addressInfo)
                self.lock.lock()
                guard !self.terminal else { self.lock.unlock(); socket.cancel(); return }
                self.socket = socket
                self.lock.unlock()
                try socket.connect(deadline: deadline)
                self.lock.lock()
                if !self.terminal { self.updateStatus(.ready) }
                self.lock.unlock()
            } catch {
                self.fail(error)
            }
        }
    }

    private var isReadyLocked: Bool {
        if case .ready = state { return true }
        return false
    }

    private func readySocket() throws -> Socket {
        lock.lock()
        defer { lock.unlock() }
        if case .cancelled = state { throw CancellationError() }
        guard isReadyLocked, let socket else {
            throw Socket.Errors.socketCreationFailed(underlyingErrorCode: nil)
        }
        return socket
    }

    deinit { socket?.cancel() }
}

extension SocketNetworkConnection: NetworkConnectionReading {
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard minimumLength >= 0, maximumLength >= minimumLength, maximumLength > 0 else {
            if minimumLength == 0, maximumLength == 0 { return Data() }
            throw VNCError.protocol(.invalidData)
        }
        let socket = try readySocket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                readQueue.async {
                    do {
                        var result = Data()
                        repeat {
                            var buffer = [UInt8](repeating: 0, count: min(maximumLength - result.count, 64 * 1024))
                            let count = try socket.receive(buffer: &buffer)
                            guard count > 0 else { throw Socket.Errors.connectionClosed }
                            result.append(contentsOf: buffer.prefix(count))
                        } while result.count < minimumLength
                        continuation.resume(returning: result)
                    } catch {
                        self.fail(error)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
}

extension SocketNetworkConnection: NetworkConnectionWriting {
    func write(data: Data) async throws {
        let socket = try readySocket()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeQueue.async {
                    do {
                        try socket.sendAll(buffer: Array(data))
                        continuation.resume()
                    } catch {
                        self.fail(error)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { self.cancel() }
    }
}
