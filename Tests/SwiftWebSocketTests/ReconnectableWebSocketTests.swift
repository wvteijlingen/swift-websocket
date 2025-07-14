//
//  ReconnectableWebSocketTests.swift
//  SwiftWebSocket
//
//  Created by Ward van Teijlingen on 14/07/2025.
//

import Foundation
import Testing
@testable import SwiftWebSocket

struct ReconnectableWebSocketTests {
    private var webSocket = ReconnectableWebSocket {
        URLRequest(url: URL(string: "wss://echo.websocket.org")!)
    }

    @Test
    func connect() async throws {
        var stateEvents: [WebSocket.StateChangedEvent] = []

        let task = Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
        }

        try await webSocket.connect()
        try await Task.sleep(for: .seconds(1))

        #expect(await webSocket.state == .connected)
        #expect(stateEvents == [.connecting, .connected])
        
        task.cancel()
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

        let task = Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
        }

        try await webSocket.connect()
        try await webSocket.disconnect(closeCode: .normalClosure, reason: nil)
        try await Task.sleep(for: .seconds(1))

        #expect(await webSocket.state == .disconnected)
        #expect(stateEvents == [.connecting, .connected, .disconnected(closeCode: .normalClosure, reason: nil)])

        task.cancel()
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

        let task = Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
        }

        try await webSocket.connect()
        try await webSocket.disconnect(closeCode: .goingAway, reason: "See you later")
        try await Task.sleep(for: .seconds(1))

        #expect(await webSocket.state == .disconnected)
        #expect(stateEvents == [.connecting, .connected, .disconnected(closeCode: .goingAway, reason: "See you later")])

        task.cancel()
    }

    @Test
    func reconnect() async throws {
        var stateEvents: [WebSocket.StateChangedEvent] = []

        let task = Task {
            for await event in webSocket.stateEvents {
                stateEvents.append(event)
            }
        }

        try await webSocket.connect()
        try await webSocket.disconnect(closeCode: .normalClosure, reason: nil)
        try await webSocket.connect()
        try await Task.sleep(for: .seconds(1))

        #expect(await webSocket.state == .connected)
        #expect(stateEvents == [
            .connecting,
            .connected,
            .disconnected(closeCode: .normalClosure, reason: nil),
            .connecting,
            .connected
        ])

        task.cancel()
    }

    @Test
    func sendString() async throws {
        let stringToSend = "Hello world"

        try await webSocket.connect()
        try await webSocket.send(stringToSend)

        let message = await webSocket.messages.first { element in
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

        let message = await webSocket.messages.first { element in
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
