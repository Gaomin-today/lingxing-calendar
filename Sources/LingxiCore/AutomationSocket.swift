import Foundation
import Darwin

public struct AutomationTransportError: Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
}

/// A local, same-user, newline-delimited JSON protocol. There is no network listener.
public enum AutomationSocket {
    public static let maximumRequestBytes = 1_048_576
    public static let maximumResponseBytes = 8_388_608
    public static func defaultPath(preview: Bool = false) -> String {
        "/tmp/lingxi-\(getuid())/\(preview ? "preview" : "main").sock"
    }

    public static func send(_ request: AutomationRequest, path: String = defaultPath(), timeout: TimeInterval = 35) throws -> AutomationResponse {
        let data = try AutomationJSON.encode(request)
        guard data.count <= maximumRequestBytes else { throw AutomationTransportError("request_too_large", "请求超过 1 MiB 上限。") }
        try verifySocket(path)
        let fd = try makeSocket()
        defer { Darwin.close(fd) }
        let deadline = Date().addingTimeInterval(timeout)
        do { try connectSocket(fd, path: path, deadline: deadline) }
        catch let error as AutomationTransportError where error.code == "connection_refused" {
            throw AutomationTransportError("app_not_running", "灵性日历尚未运行，请先打开对应的 Mac 应用。")
        }
        try verifyPeer(fd)
        try writeFrame(data, fd: fd, deadline: deadline)
        let responseData = try readFrame(fd, limit: maximumResponseBytes, deadline: deadline)
        let response: AutomationResponse
        do { response = try AutomationJSON.decode(AutomationResponse.self, from: responseData) }
        catch { throw AutomationTransportError("invalid_response", "应用未返回有效的 JSON 协议响应。") }
        guard response.version == 1, response.requestID == request.requestID else {
            throw AutomationTransportError("invalid_response", "应用返回了不匹配的协议版本或请求编号。")
        }
        return response
    }

    fileprivate static func verifySocket(_ path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { throw AutomationTransportError("app_not_running", "灵性日历尚未运行，请先打开对应的 Mac 应用。") }
            throw posixError("socket_unavailable", "无法检查本机接口")
        }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK, info.st_mode & 0o077 == 0 else {
            throw AutomationTransportError("unsafe_socket", "本机接口的类型、所有者或权限不符合要求。")
        }
    }

    fileprivate static func makeSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket_unavailable", "无法创建本机接口") }
        var noSignal: Int32 = 1
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0 else {
            let error = posixError("socket_unavailable", "无法配置本机接口")
            Darwin.close(fd); throw error
        }
        return fd
    }

    fileprivate static func withAddress<T>(_ path: String, _ operation: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.contains(0), bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AutomationTransportError("invalid_socket_path", "本机接口路径过长或包含无效字符。")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes + [0]) }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try operation($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    fileprivate static func connectSocket(_ fd: Int32, path: String, deadline: Date) throws {
        let result = try withAddress(path) { Darwin.connect(fd, $0, $1) }
        if result == 0 { return }
        if errno != EINPROGRESS {
            if errno == ECONNREFUSED || errno == ENOENT { throw AutomationTransportError("connection_refused", "应用未接听本机接口。") }
            throw posixError("connection_failed", "无法连接本机接口")
        }
        try wait(fd, events: Int16(POLLOUT), deadline: deadline)
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout.size(ofValue: error))
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { throw posixError("connection_failed", "无法读取连接状态") }
        guard error == 0 else {
            if error == ECONNREFUSED || error == ENOENT { throw AutomationTransportError("connection_refused", "应用未接听本机接口。") }
            throw AutomationTransportError("connection_failed", "本机连接失败：\(String(cString: strerror(error)))")
        }
    }

    fileprivate static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
            throw AutomationTransportError("peer_not_allowed", "只允许当前 macOS 用户访问本机接口。")
        }
    }

    fileprivate static func wait(_ fd: Int32, events: Int16, deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw AutomationTransportError("transport_timeout", "本机接口请求超时；写入结果可能尚未返回，请使用相同 request_id 重试。") }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&descriptor, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if result > 0 {
                if descriptor.revents & Int16(POLLNVAL) != 0 { throw AutomationTransportError("connection_closed", "本机连接已关闭。") }
                return // recv/send/getsockopt reports hangup and socket-specific errors.
            }
            if result < 0 && errno != EINTR { throw posixError("transport_error", "等待本机接口失败") }
        }
    }

    fileprivate static func readFrame(_ fd: Int32, limit: Int, deadline: Date) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            try wait(fd, events: Int16(POLLIN), deadline: deadline)
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count == 0 { throw AutomationTransportError("incomplete_request", "连接在完整 JSON 行到达之前关闭。") }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                throw posixError("transport_error", "读取本机接口失败")
            }
            let received = buffer.prefix(count)
            if let newline = received.firstIndex(of: 10) {
                data.append(contentsOf: received.prefix(newline))
                guard data.count <= limit else { throw AutomationTransportError("request_too_large", "JSON 内容超过接口大小上限。") }
                guard received.dropFirst(newline + 1).allSatisfy({ [9, 10, 13, 32].contains($0) }) else {
                    throw AutomationTransportError("invalid_request", "每次连接只接受一条 JSON 请求。")
                }
                return data
            }
            data.append(contentsOf: received)
            guard data.count <= limit else { throw AutomationTransportError("request_too_large", "JSON 内容超过接口大小上限。") }
        }
    }

    fileprivate static func writeFrame(_ data: Data, fd: Int32, deadline: Date) throws {
        var frame = data; frame.append(10)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try wait(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw posixError("transport_error", "写入本机接口失败")
                }
                guard count > 0 else { throw AutomationTransportError("connection_closed", "本机连接已关闭。") }
                offset += count
            }
        }
    }

    fileprivate static func posixError(_ code: String, _ prefix: String) -> AutomationTransportError {
        let value = errno
        return AutomationTransportError(code, "\(prefix)：\(String(cString: strerror(value)))")
    }
}

public final class AutomationSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (AutomationRequest) async -> AutomationResponse
    public let path: String
    private let handler: Handler
    private let mutex = NSLock()
    private var runtime: SocketRuntime?

    public init(path: String = AutomationSocket.defaultPath(), handler: @escaping Handler) {
        self.path = path; self.handler = handler
    }

    /// Throws when another app already owns this endpoint; never replaces an active listener.
    public func start() throws {
        mutex.lock(); defer { mutex.unlock() }
        guard runtime == nil else { return }
        let newRuntime = try SocketRuntime(path: path, handler: handler)
        runtime = newRuntime
        newRuntime.run()
    }

    public func stop() {
        mutex.lock(); let previous = runtime; runtime = nil; mutex.unlock()
        previous?.stop()
    }
    deinit { stop() }
}

private final class SocketRuntime: @unchecked Sendable {
    let path: String
    let fd: Int32
    let lockFD: Int32
    let inode: ino_t
    let handler: AutomationSocketServer.Handler
    let stateLock = NSLock()
    var stopped = false

    init(path: String, handler: @escaping AutomationSocketServer.Handler) throws {
        self.path = path; self.handler = handler
        let directory = (path as NSString).deletingLastPathComponent
        guard directory.hasPrefix("/"), !directory.isEmpty else { throw AutomationTransportError("invalid_socket_path", "本机接口必须使用绝对路径。") }
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw AutomationSocket.posixError("socket_unavailable", "无法创建接口目录") }
        let directoryFD = Darwin.open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw AutomationTransportError("unsafe_socket", "接口目录不可访问或是符号链接。") }
        defer { Darwin.close(directoryFD) }
        var directoryInfo = stat()
        guard fstat(directoryFD, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & S_IFMT == S_IFDIR, fchmod(directoryFD, 0o700) == 0 else {
            throw AutomationTransportError("unsafe_socket", "接口目录必须由当前用户拥有。")
        }
        let ownedLockFD = Darwin.open(path + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard ownedLockFD >= 0 else { throw AutomationTransportError("unsafe_socket", "无法安全打开接口锁文件。") }
        var lockInfo = stat()
        guard fstat(ownedLockFD, &lockInfo) == 0, lockInfo.st_uid == getuid(), lockInfo.st_mode & S_IFMT == S_IFREG,
              lockInfo.st_nlink == 1, fchmod(ownedLockFD, 0o600) == 0 else {
            Darwin.close(ownedLockFD); throw AutomationTransportError("unsafe_socket", "接口锁文件不安全。")
        }
        guard flock(ownedLockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(ownedLockFD); throw AutomationTransportError("app_already_running", "已有灵性日历实例占用这个本机接口。")
        }
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_uid == getuid(), existing.st_mode & S_IFMT == S_IFSOCK else {
                Darwin.close(ownedLockFD); throw AutomationTransportError("unsafe_socket", "接口位置已被其他类型的文件占用。")
            }
            do {
                let probe = try AutomationSocket.makeSocket()
                defer { Darwin.close(probe) }
                do {
                    try AutomationSocket.connectSocket(probe, path: path, deadline: Date().addingTimeInterval(1))
                    throw AutomationTransportError("app_already_running", "已有应用正在接听这个本机接口。")
                } catch let error as AutomationTransportError where error.code == "connection_refused" {
                    guard unlink(path) == 0 || errno == ENOENT else { throw AutomationSocket.posixError("socket_unavailable", "无法清理失效接口") }
                }
            } catch { Darwin.close(ownedLockFD); throw error }
        } else if errno != ENOENT {
            let error = AutomationSocket.posixError("socket_unavailable", "无法检查接口位置")
            Darwin.close(ownedLockFD); throw error
        }
        let listener: Int32
        do { listener = try AutomationSocket.makeSocket() }
        catch { Darwin.close(ownedLockFD); throw error }
        var boundInode: ino_t?
        do {
            guard try AutomationSocket.withAddress(path, { Darwin.bind(listener, $0, $1) }) == 0 else {
                throw AutomationSocket.posixError("socket_unavailable", "无法绑定本机接口")
            }
            var bound = stat()
            if lstat(path, &bound) == 0 { boundInode = bound.st_ino }
            guard chmod(path, 0o600) == 0, Darwin.listen(listener, 16) == 0 else {
                throw AutomationSocket.posixError("socket_unavailable", "无法启动本机接口")
            }
            var created = stat()
            guard lstat(path, &created) == 0 else { throw AutomationSocket.posixError("socket_unavailable", "无法检查新建接口") }
            inode = created.st_ino
        } catch {
            Darwin.close(listener); Darwin.close(ownedLockFD)
            var info = stat()
            if let boundInode, lstat(path, &info) == 0, info.st_ino == boundInode,
               info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK { unlink(path) }
            throw error
        }
        fd = listener; lockFD = ownedLockFD
    }

    func run() {
        DispatchQueue(label: "com.lingxing.calendar.automation", qos: .utility).async { [self] in
            defer {
                removeOwnedSocket()
                Darwin.close(fd)
                flock(lockFD, LOCK_UN); Darwin.close(lockFD)
            }
            while !isStopped {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let available = Darwin.poll(&descriptor, 1, 100)
                guard !isStopped else { break }
                if available <= 0 { continue }
                let connection = Darwin.accept(fd, nil, nil)
                if connection < 0 { continue }
                var noSignal: Int32 = 1
                _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
                _ = fcntl(connection, F_SETFL, O_NONBLOCK)
                _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
                serve(connection)
                Darwin.close(connection)
            }
        }
    }

    var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }
    func stop() {
        stateLock.lock(); stopped = true; stateLock.unlock()
        Darwin.shutdown(fd, SHUT_RDWR)
        removeOwnedSocket()
    }
    func removeOwnedSocket() {
        var current = stat()
        if lstat(path, &current) == 0, current.st_ino == inode, current.st_uid == getuid(), current.st_mode & S_IFMT == S_IFSOCK { unlink(path) }
    }

    func serve(_ connection: Int32) {
        var request: AutomationRequest?
        let response: AutomationResponse
        do {
            try AutomationSocket.verifyPeer(connection)
            let data = try AutomationSocket.readFrame(connection, limit: AutomationSocket.maximumRequestBytes, deadline: Date().addingTimeInterval(3))
            let decoded: AutomationRequest
            do { decoded = try AutomationJSON.decode(AutomationRequest.self, from: data) }
            catch { throw AutomationTransportError("invalid_request", "请求必须是有效的 version/request_id/method/params JSON 对象。") }
            request = decoded
            guard decoded.version == 1 else { throw AutomationTransportError("unsupported_version", "仅支持本机接口协议 version 1。") }
            guard decoded.params.objectValue != nil else { throw AutomationTransportError("invalid_params", "params 必须是 JSON 对象。") }
            let result = ResponseBox()
            let ready = DispatchSemaphore(value: 0)
            let task = Task { [handler] in
                let output = await handler(decoded)
                result.put(output); ready.signal()
            }
            if ready.wait(timeout: .now() + 30) == .timedOut {
                task.cancel()
                throw AutomationTransportError("operation_timeout", "操作尚未返回；写入可能已完成，请保留相同 request_id 重试查询结果。")
            }
            response = result.get() ?? .failure(request: decoded, code: "internal_error", message: "应用未返回操作结果。")
        } catch let error as AutomationTransportError {
            response = .failure(request: request, code: error.code, message: error.message)
        } catch {
            response = .failure(request: request, code: "internal_error", message: "本机接口无法处理这条请求。")
        }
        if let encoded = try? AutomationJSON.encode(response) {
            let outgoing = encoded.count <= AutomationSocket.maximumResponseBytes ? encoded :
                (try? AutomationJSON.encode(AutomationResponse.failure(request: request, code: "response_too_large", message: "结果超过 8 MiB 上限，请缩小查询范围。")))
            if let outgoing { try? AutomationSocket.writeFrame(outgoing, fd: connection, deadline: Date().addingTimeInterval(5)) }
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AutomationResponse?
    func put(_ newValue: AutomationResponse) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> AutomationResponse? { lock.lock(); defer { lock.unlock() }; return value }
}
