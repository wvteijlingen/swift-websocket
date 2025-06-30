import Foundation
import Combine

public enum WebSocketError: Error {
    case alreadyConnectedOrConnecting
    case notConnected
    case cannotParseMessageAsJSON(String)
    case invalidMessage(Error)
}

extension WebSocket {
    public enum State: Equatable {
        /// The socket is initialized and ready to connect
        case notConnected
        /// The socket is in the process of connecting
        case connecting
        /// The socket is connected
        case connected
        /// The socket is disconnected after being connected
        case disconnected
    }

    public enum StateChangedEvent: Equatable {
        /// The socket is in the process of connecting
        case connecting
        /// The socket is connected
        case connected
        /// The socket is disconnected after being connected
        case disconnected(closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?)
    }

    public enum Heartbeats {
        case disabled
        case enabled(every: Duration, data: Data)
    }

    public enum Message {
        /// A string message
        case string(String)
        /// A data message
        case data(Data)
        /// A message that could not be parsed
        case invalid(Error)

        /// Decodes the message into an instance of the specified type.
        ///
        /// If the message is a data message, the data will be used as-is. If the message is a string message,
        /// the string will be converted to data using UTF-8 before decoding it.
        func decode<T, Decoder>(
            _ type: T.Type,
            decoder: Decoder = JSONDecoder()
        ) throws -> T where T: Decodable, Decoder: TopLevelDecoder, Decoder.Input == Data {
            switch self {
            case .string(let string):
                guard let data = string.data(using: .utf8) else {
                    throw WebSocketError.cannotParseMessageAsJSON(string)
                }
                return try decoder.decode(T.self, from: data)
            case .data(let data):
                return try decoder.decode(T.self, from: data)
            case .invalid(let error):
                throw WebSocketError.invalidMessage(error)
            }
        }
    }
}

extension ReconnectableWebSocket {
    enum ConnectEvent {
        case initial
        case reconnect(error: Error)
    }
}
