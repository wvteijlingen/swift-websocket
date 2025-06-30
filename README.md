# swift-websocket

SwiftWebSocket is an async/await wrapper around `URLSessionWebSocketTask`. It exposes a modern Swift API,
such as emitting incoming messages through async streams.

## Usage

SwiftWebsocket exposes two types: `WebSocket` and `ReconnectableWebSocket`.
The main difference is that `WebSocket` can only connect once. After it becomes disconnected, you cannot reconnect it.

### ReconnectableWebSocket

```swift
// Initialize a new WebSocket or ReconnectableWebSocket
let webSocket = WebSocket(url: URL(string: "wss://echo.websocket.org")!)
let webSocket = ReconnectableWebSocket {
    // This closure gets called every time the socket will connect,
    // allowing you to provide a new URLRequest used for each connection attempt.
    URLRequest(url: URL(string: "wss://echo.websocket.org")!)
}

// Connect the socket
try await webSocket.connect()

// Send a message
try await webSocket.send("Hello world")
try await webSocket.send(Data())
try await webSocket.send(encodableModel, encoder: JSONEncoder())

// Receive a message
for try await message in webSocket.messages {
    // As String or Data
    switch message {
    case .string(let string):
        print("Received message: \(string)")
    case .data:
        print("Received data")
    case .invalid:
        print("Received an unparsable message")
    }
    
    // As a decodable type
    let decodableModel = try message.decode(Foo.self)
}

// Observe state changes
for try await event in webSocket.stateEvents {
    switch event {
    case .connecting:
        print("The WebSocket is connecting...")
    case .connected:
        print("The WebSocket is connected")
    case .disconnected(let closeCode, let reason):
        print("The WebSocket is disconnected")
    }
}

// Disconnect the socket
try webSocket.disconnect()
```

### Heartbeats

Both `WebSocket` and `ReconnectableWebSocket` support sending heartbeats at regular intervals.
Depending on the behaviour of the server, this can useful to keep a socket connection open for longer periods of time.

To enable heartbeats, provide a value for the `heartbeats` parameter of the socket intializer:

```swift
let heartbeatData = "heartbeat".data(using: .utf8)!

let webSocket = WebSocket(
    url: URL(string: "wss://echo.websocket.org")!,
    heartbeats: .enabled(every: .seconds(5), data: heartbeatData)
)
```