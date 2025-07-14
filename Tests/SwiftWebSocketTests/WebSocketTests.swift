import Foundation
import Testing
@testable import SwiftWebSocket

struct WebSocketTests {
    private let webSocket = WebSocket(url: URL(string: "wss://echo.websocket.org")!)

    @Test
    func connect() async throws {
        var stateEvents: [WebSocket.StateChangedEvent] = []
        var stateEventsFinished = false

        Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
            stateEventsFinished = true
        }

        try await webSocket.connect()
        #expect(await webSocket.state == .connected)
        #expect(stateEvents == [.connecting, .connected])
        #expect(!stateEventsFinished)
    }

    @Test
    func connectWhenAlreadyConnected() async throws {
        try await webSocket.connect()

        await #expect(throws: WebSocketError.self) {
            try await webSocket.connect()
        }
    }

    @Test
    func disconnect() async throws {
        var stateEvents: [WebSocket.StateChangedEvent] = []
        var stateEventsFinished = false

        Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
            stateEventsFinished = true
        }

        try await webSocket.connect()
        try await webSocket.disconnect(closeCode: .normalClosure)

        #expect(await webSocket.state == .disconnected)
        #expect(stateEvents == [.connecting, .connected, .disconnected(closeCode: .normalClosure, reason: nil)])
        #expect(stateEventsFinished)
    }

    @Test
    func disconnectWhenNotConnected() async throws {
        await #expect(throws: WebSocketError.self) {
            try await webSocket.disconnect(closeCode: .normalClosure)
        }
    }

    @Test
    func disconnectWithCloseCodeAndReason() async throws {
        var stateEvents: [WebSocket.StateChangedEvent] = []
        var stateEventsFinished = false

        Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
            stateEventsFinished = true
        }

        try await webSocket.connect()
        try await webSocket.disconnect(closeCode: .goingAway, reason: "See you later")

        #expect(await webSocket.state == .disconnected)
        #expect(stateEvents == [.connecting, .connected, .disconnected(closeCode: .goingAway, reason: "See you later")])
        #expect(stateEventsFinished)
    }

    @Test
    func sendString() async throws {
        let stringToSend = "Hello world"

        try await webSocket.connect()
        try await webSocket.send(stringToSend)

        let message = try await webSocket.messages.first { element in
            switch element {
            case .string(let string): string == stringToSend
            default: false
            }
        }

        #expect(message != nil)
    }

    @Test
    func sendData() async throws {
        let dataToSend = "Hello world".data(using: .utf8)!

        try await webSocket.connect()
        try await webSocket.send(dataToSend)

        let message = try await webSocket.messages.first { element in
            switch element {
            case .data(let data): data == dataToSend
            default: false
            }
        }

        #expect(message != nil)
    }

    @Test
    func sendCodable() async throws {
        struct CodableModel: Codable, Equatable {
            let foo: String
        }

        let valueToSend = CodableModel(foo: "fooValue")

        try await webSocket.connect()
        try await webSocket.send(valueToSend, encoder: JSONEncoder())

        let message = try await webSocket.messages
            .first { element in
                switch element {
                case .data: true
                default: false
                }
            }
            .flatMap { message in
                try message.decode(CodableModel.self, decoder: JSONDecoder())
            }

        #expect(message == valueToSend)
    }

    @Test
    func sendWhenNotConnected() async throws {
        await #expect(throws: WebSocketError.self) {
            try await webSocket.send("Hello world")
        }

        await #expect(throws: WebSocketError.self) {
            try await webSocket.send("Hello world".data(using: .utf8)!)
        }
    }
}
