import Foundation
import XCTest
import Combine
@testable import SwiftWebSocket

final class WebSocketTests: XCTestCase {
    private var webSocket: WebSocket!

    override func setUp() async throws {
        webSocket = WebSocket(url: URL(string: "wss://ws.ifelse.io")!)
    }

    override func tearDown() async throws {
        try? webSocket.disconnect()
    }

    func test_connect_connects() async throws {
        try! await webSocket.connect()
    }

    func test_disconnect() async throws {
        try await webSocket.connect()

        XCTAssertEqual(webSocket.state, .connected)

        try webSocket.disconnect()

        try await Task.sleep(for: .seconds(1))

        XCTAssertEqual(webSocket.state, .disconnected)
    }

    func test_sendString() async throws {
        try await webSocket.connect()
        try await webSocket.send("Hello world")

        let message = try await webSocket.messages.first { element in
            element == "Hello world".data(using: .utf8)
        }

        XCTAssertNotNil(message)
    }

    func test_sendData() async throws {
        let data = "Hello world".data(using: .utf8)!

        try await webSocket.connect()
        try await webSocket.send(data)

        let message = try await webSocket.messages.first { element in
            element == data
        }

        XCTAssertNotNil(message)
    }
}
