import Foundation
import Combine

public class WebSocket {
    private(set) var state: State = .notConnected

    /// A stream of messages received by the socket.
    ///
    /// This stream will finish when the socket disconnects as expected,
    /// or throws when the socket disconnects due to an error.
    public let messages: AsyncThrowingStream<Message, Error>

    /// A stream of changes to the socket state.
    ///
    /// This stream will finish after the socket disconnects.
    public let stateEvents: AsyncStream<StateChangedEvent>

    private let socketTask: URLSessionWebSocketTask
    private var socketTaskDelegate: SocketTaskDelegate?

    private let messagesContinuation: AsyncThrowingStream<Message, Error>.Continuation
    private let stateEventsContinuation: AsyncStream<StateChangedEvent>.Continuation
    private let heartbeats: Heartbeats
    private var heartbeatTask: Task<Void, Error>?

    /// Initializes a new WebSocket.
    ///
    /// - Parameters:
    ///   - request: The URLRequest used for connecting the WebSocket.
    ///   - urlSession: The URLSession used for connect the WebSocket.
    ///   - heartbeats: Whether to send heartbeats after connecting.
    public init(
        request: URLRequest,
        urlSession: URLSession = URLSession.shared,
        heartbeats: Heartbeats = .disabled
    ) {
        let (messagesStream, messagesContinuation) = AsyncThrowingStream.makeStream(
            of: Message.self,
            throwing: Error.self
        )
        self.messages = messagesStream
        self.messagesContinuation = messagesContinuation

        let (stateEvents, stateEventsContinuation) = AsyncStream.makeStream(of: StateChangedEvent.self)
        self.stateEvents = stateEvents
        self.stateEventsContinuation = stateEventsContinuation

        self.socketTask = urlSession.webSocketTask(with: request)
        self.heartbeats = heartbeats
    }

    public convenience init(
        url: URL,
        urlSession: URLSession = URLSession.shared,
        heartbeats: Heartbeats = .disabled
    ) {
        self.init(request: URLRequest(url: url), urlSession: urlSession, heartbeats: heartbeats)
    }

    deinit {
        try? disconnect()
    }

    // MARK: - Connecting / Disconnecting

    /// Connects the WebSocket. You may only call this once per instance.
    ///
    /// After the WebSocket disconnects, it can no longer be connected. If you want to establish a new connection
    /// you must create a new WebSocket instance.
    ///
    /// - Throws WebSocketError.alreadyConnectedOrConnecting when the socket is already connected or connecting.
    public func connect() async throws {
        guard state == .notConnected else {
            throw WebSocketError.alreadyConnectedOrConnecting
        }

        state = .connecting
        stateEventsContinuation.yield(.connecting)

        try await withCheckedThrowingContinuation { continuation in
            let delegate = SocketTaskDelegate { _ in
                self.handleConnect()
                continuation.resume()

            } onWebSocketTaskDidClose: { closeCode, reason in
                self.handleDisconnect(withError: nil, closeCode: closeCode, reason: reason)

            } onWebSocketTaskDidCompleteWithError: { error in
                if let error {
                    if case .connecting = self.state {
                        continuation.resume(throwing: error)
                    } else {
                        self.handleDisconnect(withError: error, closeCode: nil, reason: nil)
                    }
                }
            }

            self.socketTaskDelegate = delegate
            socketTask.delegate = delegate

            socketTask.resume()
        }
    }
    
    /// Disconnects the WebSocket.
    ///  
    /// After the WebSocket disconnects, it can no longer be connected. If you want to establish a new connection
    /// you must create a new WebSocket instance.
    ///
    /// - Parameters:
    ///   - closeCode: A close code that indicates the reason for closing the connection.
    ///   - reason: Optional further information to explain the closing.
    ///
    /// - Throws WebSocketError.notConnected when the WebSocket is not connected.
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: String? = nil) throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        messagesContinuation.finish()

        socketTask.cancel(with: closeCode, reason: reason?.data(using: .utf8))
        socketTaskDelegate = nil
    }

    // MARK: - Sending Data

    /// Sends the given encodable `value` through the WebSocket.
    ///
    /// - Parameters:
    ///   - value: The encodable value that is sent through the websocket.
    ///   - encoder: The encoder used to encode the value.
    ///
    /// - Throws WebSocketError.notConnected when the `send` method is called before the WebSocket is connected.
    public func send<Encoder>(
        _ value: any Encodable,
        encoder: Encoder
    ) async throws where Encoder: TopLevelEncoder, Encoder.Output == Data {
        let data = try encoder.encode(value)
        try await send(.data(data))
    }
    
    /// Sends the given `string` through the websocket.
    ///
    /// - Throws WebSocketError.notConnected when the `send` method is called before the WebSocket is connected.
    public func send(_ string: String) async throws {
        try await send(.string(string))
    }

    /// Sends the given `data` through the WebSocket.
    ///
    /// - Throws WebSocketError.notConnected when the `send` method is called before the WebSocket is connected.
    public func send(_ data: Data) async throws {
        try await send(.data(data))
    }

    // MARK: - Heartbeats

    /// Start sending a heartbeat at regular intervals.
    ///
    /// - Parameters:
    ///   - heartbeat: The heartbeat data to send.
    ///   - interval: The interval between heartbeats.
    private func startHeartbeats(sending heartbeat: Data, every interval: Duration) {
        heartbeatTask?.cancel()

        heartbeatTask = Task {
            if Task.isCancelled { return }

            try await send(heartbeat)

            try await Task.sleep(for: interval)

            startHeartbeats(sending: heartbeat, every: interval)
        }
    }

    /// Stop sending heartbeats.
    private func stopHeartbeats() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Private

    private func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socketTask.send(message) { error in
                if let error {
                    continuation.resume(with: .failure(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func receive() {
        socketTask.receive { [weak self] result in
            switch result {
            case .success(.data(let data)):
                self?.messagesContinuation.yield(.data(data))
                self?.receive()

            case .success(.string(let string)):
                self?.messagesContinuation.yield(.string(string))
                self?.receive()

            case .failure(let error):
                self?.messagesContinuation.yield(.invalid(error))
                self?.receive()

            default:
                break
            }
        }
    }

    private func handleConnect() {
        state = .connected
        stateEventsContinuation.yield(.connected)

        receive()

        switch heartbeats {
        case .disabled:
            break
        case .enabled(let interval, let data):
            startHeartbeats(sending: data, every: interval)
        }
    }

    private func handleDisconnect(
        withError error: Error?,
        closeCode: URLSessionWebSocketTask.CloseCode?,
        reason: Data?
    ) {
        state = .disconnected
        stateEventsContinuation.yield(.disconnected(
            closeCode: closeCode,
            reason: reason.flatMap { String(data: $0, encoding: .utf8) }
        ))
        stateEventsContinuation.finish()

        messagesContinuation.finish(throwing: error)
        socketTaskDelegate = nil
        stopHeartbeats()
    }
}

private class SocketTaskDelegate: NSObject, URLSessionWebSocketDelegate {
    private let onWebSocketTaskDidOpen: (_ protocol: String?) -> Void
    private let onWebSocketTaskDidClose: (_ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void
    private let onWebSocketTaskDidCompleteWithError: (_ error: Error?) -> Void

    init(
        onWebSocketTaskDidOpen: @escaping (_: String?) -> Void,
        onWebSocketTaskDidClose: @escaping (_: URLSessionWebSocketTask.CloseCode, _: Data?) -> Void,
        onWebSocketTaskDidCompleteWithError: @escaping (_: Error?) -> Void
    ) {
        self.onWebSocketTaskDidOpen = onWebSocketTaskDidOpen
        self.onWebSocketTaskDidClose = onWebSocketTaskDidClose
        self.onWebSocketTaskDidCompleteWithError = onWebSocketTaskDidCompleteWithError
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        onWebSocketTaskDidOpen(proto)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onWebSocketTaskDidClose(closeCode, reason)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onWebSocketTaskDidCompleteWithError(error)
    }
}
