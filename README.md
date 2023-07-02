# swift-websocket

swift-websocket is an async/await wrapper around `URLSessionWebSocketTask`. It exposes a modern Swift API,
such as emitting incoming messages through an `AsyncThrowingStream`.

## Usage

```swift
// Initialize a new WebSocket
let webSocket = WebSocket(url: URL(string: "wss://ws.ifelse.io")!)

// Connect it
try await webSocket.connect()

// Send something
try await webSocket.send("Hello world")
try await webSocket.send(Data())
try await webSocket.send(encodableModel, encoder: JSONEncoder())

// Read something
for try await message in webSocket.messages {
    // As string
    print("Received message: \(String(data: message, encoding: .utf8))")
    
    // As JSON
    let decodableModel = try JSONDecoder().decode(Foo.self, from: message)
}

// Disconnect it
try webSocket.disconnect()
```
