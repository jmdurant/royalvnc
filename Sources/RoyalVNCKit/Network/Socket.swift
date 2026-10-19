#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

#if canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#endif

/// The descriptor stays open until the last operation releases this object. Cancellation
/// shuts it down, avoiding descriptor reuse races with an operation already in progress.
final class Socket: @unchecked Sendable {
    let addressInfo: AddressInfo
#if canImport(WinSDK)
    private typealias NativeSocket = SOCKET
#else
    private typealias NativeSocket = Int32
#endif
    private let nativeSocket: NativeSocket
#if canImport(Glibc) || canImport(Android) || canImport(WinSDK)
    private let lock = Spinlock()
#else
    private let lock = NSLock()
#endif
    private var cancelled = false

    init(addressInfo: AddressInfo) throws(Errors) {
        // Keep ownership local until configuration has succeeded. A fully initialized
        // class runs deinit when its initializer throws, so assigning the stored
        // descriptor before configuration could otherwise close a failed socket twice.
        let descriptor = socket(addressInfo.family, addressInfo.socktype, addressInfo.protocol)
#if canImport(WinSDK)
        guard descriptor != INVALID_SOCKET else {
            throw .socketCreationFailed(underlyingErrorCode: WSAGetLastError())
        }
#else
        guard descriptor >= 0 else {
            throw .socketCreationFailed(underlyingErrorCode: errno)
        }
#endif
        var ownsDescriptor = true
        defer {
            if ownsDescriptor {
#if canImport(WinSDK)
                closesocket(descriptor)
#else
                close(descriptor)
#endif
            }
        }
#if canImport(WinSDK)
        var nonblocking: u_long = 1
        guard ioctlsocket(descriptor, FIONBIO, &nonblocking) == 0 else {
            throw .socketCreationFailed(underlyingErrorCode: WSAGetLastError())
        }
#else
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw .socketCreationFailed(underlyingErrorCode: errno)
        }
#if canImport(Darwin)
        var noSigPipe: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                         socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw .socketCreationFailed(underlyingErrorCode: errno)
        }
#endif
#endif
        self.addressInfo = addressInfo
        self.nativeSocket = descriptor
        ownsDescriptor = false
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
#if canImport(WinSDK)
        _ = shutdown(nativeSocket, SD_BOTH)
#else
        _ = shutdown(nativeSocket, Int32(SHUT_RDWR))
#endif
    }

    private func checkCancellation() throws(Errors) {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw .cancelled }
    }

    private var lastError: Int32 {
#if canImport(WinSDK)
        WSAGetLastError()
#else
        errno
#endif
    }

    private func isRetryable(_ code: Int32) -> Bool {
#if canImport(WinSDK)
        code == WSAEWOULDBLOCK || code == WSAEINTR || code == WSAEINPROGRESS
#else
        code == EAGAIN || code == EWOULDBLOCK || code == EINTR || code == EINPROGRESS
#endif
    }

    /// Poll in bounded intervals so cancellation works even for a pending connect.
    private func wait(writing: Bool, deadline: DispatchTime? = nil) throws(Errors) {
        while true {
            try checkCancellation()
            var milliseconds: Int32 = 50
            if let deadline {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline.uptimeNanoseconds else { throw .timedOut }
                milliseconds = Int32(min(50, max(1, (deadline.uptimeNanoseconds - now) / 1_000_000)))
            }
#if canImport(WinSDK)
            var descriptor = WSAPOLLFD(fd: nativeSocket,
                                       events: Int16(writing ? POLLWRNORM : POLLRDNORM), revents: 0)
            let result = WSAPoll(&descriptor, 1, milliseconds)
#else
            var descriptor = pollfd(fd: nativeSocket, events: Int16(writing ? POLLOUT : POLLIN), revents: 0)
            let result = poll(&descriptor, 1, milliseconds)
#endif
            try checkCancellation()
            if result > 0 { return }
            if result < 0, !isRetryable(lastError) { throw .operationFailed(underlyingErrorCode: lastError) }
        }
    }

    func connect(deadline: DispatchTime? = nil) throws(Errors) {
        try checkCancellation()
        if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds {
            throw .timedOut
        }
        let result: Int32
#if canImport(Glibc)
        result = Glibc.connect(nativeSocket, addressInfo.addr, addressInfo.addrlen)
#elseif canImport(Android)
        result = Android.connect(nativeSocket, addressInfo.addr!, addressInfo.addrlen)
#elseif canImport(Darwin)
        result = Darwin.connect(nativeSocket, addressInfo.addr, addressInfo.addrlen)
#elseif canImport(WinSDK)
        result = WinSDK.connect(nativeSocket, addressInfo.addr, Int32(addressInfo.addrlen))
#endif
        if result < 0 {
            let code = lastError
            guard isRetryable(code) else { throw .connectFailed(underlyingErrorCode: code) }
            try wait(writing: true, deadline: deadline)
            var error: Int32 = 0
#if canImport(WinSDK)
            var length = Int32(MemoryLayout<Int32>.size)
            let optionResult = withUnsafeMutablePointer(to: &error) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<Int32>.size) {
                    getsockopt(nativeSocket, SOL_SOCKET, SO_ERROR, $0, &length)
                }
            }
#else
            var length = socklen_t(MemoryLayout<Int32>.size)
            let optionResult = getsockopt(nativeSocket, SOL_SOCKET, SO_ERROR, &error, &length)
#endif
            guard optionResult == 0 else { throw .connectFailed(underlyingErrorCode: lastError) }
            guard error == 0 else { throw .connectFailed(underlyingErrorCode: error) }
        }
        try checkCancellation()
    }

    func receive(buffer: inout [UInt8]) throws(Errors) -> Int {
        while true {
            try wait(writing: false)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Int(recv(nativeSocket, bytes.baseAddress!.assumingMemoryBound(to: CChar.self), .init(bytes.count), 0))
            }
            if count >= 0 { return count }
            let code = lastError
            if !isRetryable(code) { throw .operationFailed(underlyingErrorCode: code) }
        }
    }

    func sendAll(buffer: [UInt8]) throws(Errors) {
        var offset = 0
        while offset < buffer.count {
            try wait(writing: true)
            let count = buffer.withUnsafeBytes { bytes -> Int in
#if canImport(Glibc) || canImport(Android)
                let flags = Int32(MSG_NOSIGNAL)
#else
                let flags: Int32 = 0
#endif
                return Int(send(nativeSocket, bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: CChar.self),
                                .init(min(bytes.count - offset, Int(Int32.max))), flags))
            }
            if count > 0 { offset += count; continue }
            if count == 0 { throw .connectionClosed }
            let code = lastError
            if !isRetryable(code) { throw .operationFailed(underlyingErrorCode: code) }
        }
        try checkCancellation()
    }

    deinit {
#if canImport(WinSDK)
        closesocket(nativeSocket)
#else
        close(nativeSocket)
#endif
    }
}

extension Socket {
    enum Errors: LocalizedError {
        case socketCreationFailed(underlyingErrorCode: Int32?)
        case connectFailed(underlyingErrorCode: Int32)
        case operationFailed(underlyingErrorCode: Int32)
        case cancelled
        case timedOut
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed(let code): "Socket creation failed (\(code.map(String.init) ?? "N/A"))"
            case .connectFailed(let code): "Connect failed (\(code))"
            case .operationFailed(let code): "Socket operation failed (\(code))"
            case .cancelled: "Connection cancelled"
            case .timedOut: "Connection timed out"
            case .connectionClosed: "Connection closed"
            }
        }
    }
}
