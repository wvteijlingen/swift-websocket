import Foundation
import Combine

actor ReconnectableWebSocket {
    /// A stream of messages received by the socket.
    ///
    /// This stream will never finish.
    public let messages: AsyncStream<WebSocket.Message>
    
    /// A stream of changes to the socket state.
    ///
    /// This stream will never finish.
    public let stateEvents: AsyncStream<WebSocket.StateChangedEvent>

    var state: WebSocket.State { webSocket?.state ?? .notConnected }

    private let connector: () -> URLRequest
    private let urlSession: URLSession
    private let heartbeats: WebSocket.Heartbeats

    private let messagesContinuation: AsyncStream<WebSocket.Message>.Continuation
    private var stateEventsContinuation: AsyncStream<WebSocket.StateChangedEvent>.Continuation
    private var streamTask: Task<Void, Error>?

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
    ///                every time the web WebSocket reconnects.
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
    
    /// Connects the WebSocket.
    ///
    /// - Throws WebSocketError.alreadyConnectedOrConnecting when the socket is already connected or connecting.
    public func connect() async throws {
        let urlRequest = self.connector()
        let webSocket = WebSocket(request: urlRequest, urlSession: urlSession, heartbeats: heartbeats)
        self.webSocket = webSocket

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
    ) throws {
        guard let webSocket = webSocket else {
            throw WebSocketError.notConnected
        }

        try webSocket.disconnect(closeCode: closeCode, reason: reason)
    }

    private func handleConnect(of webSocket: WebSocket) {
        streamTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                for try await message in webSocket.messages {
                    messagesContinuation.yield(message)
                }
            } catch {
                await handleDisconnect(withError: error)
            }

            for try await state in webSocket.stateEvents {
                await stateEventsContinuation.yield(state)
            }
        }
    }

    private func handleDisconnect(withError error: Error) {
        webSocket = nil
        streamTask?.cancel()
        streamTask = nil
    }
}
