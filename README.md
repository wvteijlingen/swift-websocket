# swift-websocket

## Usage

```swift
// Initialize a new WebSocket
let webSocket = WebSocket(url: URL(string: "wss://ws.ifelse.io")!)

// Connect it
try await webSocket.connect()

// Send something
try await webSocket.send("Hello world")

// Read something
for try await message in webSocket.messages {
    // As string
    print("Received message: \(String(data: message, encoding: .utf8)")
    
    // As decoded JSON
    
    let model = try JSONDecoder().decode(Foo.self, from: message)
}

// Disconnect it
try webSocket.disconnect()
```
