import Foundation
import Combine

actor ReconnectableWebSocket {
    /// A stream of messages received by the socket.
    ///
    /// This stream will only finish when ReconnectableWebSocket deinitializes.
    public nonisolated let messages: AsyncStream<WebSocket.Message>
    
    /// A stream of changes to the socket state.
    ///
    /// This stream will only finish when ReconnectableWebSocket deinitializes.
    public nonisolated let stateEvents: AsyncStream<WebSocket.StateChangedEvent>

    var state: WebSocket.State {
        get async {
            await webSocket?.state ?? .notConnected
        }
    }

    private let connector: () -> URLRequest
    private let urlSession: URLSession
    private let heartbeats: WebSocket.Heartbeats

    private let messagesContinuation: AsyncStream<WebSocket.Message>.Continuation
    private var stateEventsContinuation: AsyncStream<WebSocket.StateChangedEvent>.Continuation

    private var messagesTask: Task<Void, Error>?
    private var stateEventsTask: Task<Void, Error>?

    private var webSocket: WebSocket?
    
    /// Create a WebSocket that will automatically reconnect if the connection was lost due to an error.
    ///
    /// Every time the WebSocket will (re)connect, the `connector` closure will be called to obtain a
    /// new `URLRequest` used for (re)connecting the socket.
    ///
    /// - Parameters:
    ///   - urlSession: The URLSession used when connecting the WebSocket.
    ///   - heartbeats: Whether to send heartbeats after connecting.
    ///   - connector: A closure that returns a URLRequest used to connect the WebSocket. This closure will be called
    ///                every time the web WebSocket connects.
    init(
        urlSession: URLSession = URLSession.shared,
        heartbeats: WebSocket.Heartbeats = .disabled,
        connector: @escaping () -> URLRequest,
    ) {
        let (messagesStream, messagesContinuation) = AsyncStream.makeStream(of: WebSocket.Message.self)
        self.messages = messagesStream
        self.messagesContinuation = messagesContinuation

        let (stateEvents, stateEventsContinuation) = AsyncStream.makeStream(of: WebSocket.StateChangedEvent.self)
        self.stateEvents = stateEvents
        self.stateEventsContinuation = stateEventsContinuation

        self.urlSession = urlSession
        self.connector = connector
        self.heartbeats = heartbeats
    }

    deinit {
        messagesContinuation.finish()
        stateEventsContinuation.finish()
    }

    /// Connects the WebSocket.
    ///
    /// - Throws WebSocketError.alreadyConnectedOrConnecting when the socket is already connected or connecting.
    public func connect() async throws {
        let validStates = [WebSocket.State.notConnected, .disconnected]

        guard await validStates.contains(state) else {
            throw WebSocketError.alreadyConnectedOrConnecting
        }

        let urlRequest = self.connector()
        let webSocket = WebSocket(request: urlRequest, urlSession: urlSession, heartbeats: heartbeats)
        self.webSocket = webSocket

        createStreamTasks(for: webSocket)

        try await webSocket.connect()
    }

    /// Disconnects the WebSocket.
    ///
    /// - Parameters:
    ///   - closeCode: A close code that indicates the reason for closing the connection.
    ///   - reason: Optional further information to explain the closing.
    ///
    /// - Throws WebSocketError.notConnected when the WebSocket is not connected.
    public func disconnect(
        closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure,
        reason: String? = nil
    ) async throws {
        guard let webSocket = webSocket else {
            throw WebSocketError.notConnected
        }

        try await webSocket.disconnect(closeCode: closeCode, reason: reason)

        messagesTask?.cancel()
        stateEventsTask?.cancel()
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
        guard await webSocket?.state == .connected else {
            throw WebSocketError.notConnected
        }
        
        let data = try encoder.encode(value)
        try await webSocket?.send(data)
    }

    /// Sends the given `string` through the websocket.
    ///
    /// - Throws WebSocketError.notConnected when the `send` method is called before the WebSocket is connected.
    public func send(_ string: String) async throws {
        guard await webSocket?.state == .connected else {
            throw WebSocketError.notConnected
        }

        try await webSocket?.send(string)
    }

    /// Sends the given `data` through the WebSocket.
    ///
    /// - Throws WebSocketError.notConnected when the `send` method is called before the WebSocket is connected.
    public func send(_ data: Data) async throws {
        guard await webSocket?.state == .connected else {
            throw WebSocketError.notConnected
        }

        try await webSocket?.send(data)
    }

    private func createStreamTasks(for webSocket: WebSocket) {
        messagesTask = Task {
            do {
                for try await message in webSocket.messages {
                    if Task.isCancelled { return }
                    messagesContinuation.yield(message)
                }
            } catch {
                handleDisconnect(withError: error)
            }
        }

        stateEventsTask = Task {
            for try await state in webSocket.stateEvents {
                if Task.isCancelled { return }
                stateEventsContinuation.yield(state)
            }
        }
    }

    private func handleDisconnect(withError error: Error) {
        webSocket = nil
        messagesTask?.cancel()
        messagesTask = nil
        stateEventsTask?.cancel()
        stateEventsTask = nil
    }
}
