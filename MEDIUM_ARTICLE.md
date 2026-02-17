# Building OpenClaw: A Production-Ready iOS Voice AI Assistant with ElevenLabs and Push Notifications

*A deep dive into building a real-time voice conversation app with SwiftUI, WebRTC, and server-side push notifications*

---

## Introduction

Voice interfaces are transforming how we interact with AI. While chatbots have dominated the landscape, there's something fundamentally different about having a real conversation with an AI that listens and responds naturally.

In this article, I'll walk you through **OpenClaw**, a production-ready iOS app that enables real-time voice conversations with AI agents powered by ElevenLabs' Conversational AI. We'll cover:

- **Architecture decisions** for building voice-first iOS apps
- **Real-time audio streaming** with WebRTC and LiveKit
- **Elegant UI/UX patterns** for voice interfaces in SwiftUI
- **Server-side push notifications** via Apple Push Notification service (APNs)
- **Security best practices** for credential management

Whether you're building your first voice app or looking to enhance an existing one, this guide provides practical insights from a real implementation.

---

## The Vision

**[DIAGRAM 1: App Overview]**
```
Create a visual showing:
- iPhone with OpenClaw app
- Animated orb in center
- Message bubbles showing conversation
- Connection to cloud (ElevenLabs)
- Push notification coming in

Style: Modern, dark theme with coral/orange accents
Colors: Background #141110, Coral #D97366, Orange #E68C59
```

OpenClaw was built with three core principles:

1. **Voice-first interaction** - Speaking should be as natural as having a conversation
2. **Minimal friction** - One tap to start talking
3. **Proactive AI** - The agent can reach out via notifications, not just respond

---

## Architecture Overview

OpenClaw follows a clean **MVVM (Model-View-ViewModel)** architecture with clear separation of concerns. Here's how the pieces fit together:

**[DIAGRAM 2: Architecture Layers]**
```
Create a layered architecture diagram:

┌─────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                    │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │ ConversationView│  │   SettingsView  │              │
│  │  • OrbVisualizer│  │  • Credentials  │              │
│  │  • MessageBubbles│ │  • Preferences  │              │
│  │  • Controls     │  │  • Notifications│              │
│  └────────┬────────┘  └────────┬────────┘              │
└───────────┼────────────────────┼───────────────────────┘
            │                    │
┌───────────▼────────────────────▼───────────────────────┐
│                   VIEW MODEL LAYER                      │
│  ┌─────────────────────────────────────────────────┐   │
│  │         ConversationViewModel                    │   │
│  │  • State management  • Message handling          │   │
│  │  • Error handling    • UI state binding          │   │
│  └─────────────────────┬───────────────────────────┘   │
└────────────────────────┼───────────────────────────────┘
                         │
┌────────────────────────▼───────────────────────────────┐
│                    SERVICE LAYER                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │Conversation  │ │  Keychain    │ │   Network    │   │
│  │  Manager     │ │  Manager     │ │   Monitor    │   │
│  └──────┬───────┘ └──────────────┘ └──────────────┘   │
│         │                                               │
│  ┌──────▼───────┐ ┌──────────────┐ ┌──────────────┐   │
│  │   Token      │ │    Audio     │ │    Push      │   │
│  │  Service     │ │   Session    │ │ Notification │   │
│  └──────────────┘ └──────────────┘ └──────────────┘   │
└────────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼───────────────────────────────┐
│                   EXTERNAL SERVICES                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │  ElevenLabs  │ │   LiveKit    │ │    Apple     │   │
│  │     SDK      │ │   (WebRTC)   │ │    APNs      │   │
│  └──────────────┘ └──────────────┘ └──────────────┘   │
└────────────────────────────────────────────────────────┘

Use coral/orange for key components, dark surfaces for containers
```

### Key Design Decisions

**1. Singleton Services with Published State**

Rather than passing dependencies through constructors, critical services like `ConversationManager` and `PushNotificationManager` are singletons that publish their state:

```swift
@MainActor
final class ConversationManager: ObservableObject {
    static let shared = ConversationManager()

    @Published private(set) var state: AppConversationState = .idle
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var agentState: AgentMode = .listening
}
```

This allows any view to observe state changes without prop drilling.

**2. Actor-Based Concurrency for Thread Safety**

For services that handle network operations, we use Swift's actor model:

```swift
actor GatewayNotificationService {
    static let shared = GatewayNotificationService()

    private var isRegistered = false
    private var lastRegisteredToken: String?

    func registerDevice(token: String) async {
        // Thread-safe by design
    }
}
```

**3. Keychain for Sensitive Data**

API keys and credentials never touch UserDefaults:

```swift
final class KeychainManager {
    enum KeychainItem: String {
        case agentId = "com.openclaw.agentId"
        case apiKey = "com.openclaw.apiKey"
        case gatewayHookToken = "com.openclaw.hookToken"
    }

    func save(_ item: KeychainItem, value: String) throws {
        // Secure storage implementation
    }
}
```

---

## The Voice Conversation Engine

The heart of OpenClaw is the `ConversationManager`, which wraps the ElevenLabs SDK and manages the entire conversation lifecycle.

**[DIAGRAM 3: Conversation Flow]**
```
Create a sequence diagram showing:

User                App               ElevenLabs          LiveKit
 │                   │                    │                  │
 │  Tap Start        │                    │                  │
 │──────────────────►│                    │                  │
 │                   │                    │                  │
 │                   │  Fetch Token       │                  │
 │                   │───────────────────►│                  │
 │                   │                    │                  │
 │                   │  JWT Token         │                  │
 │                   │◄───────────────────│                  │
 │                   │                    │                  │
 │                   │  WebSocket Connect (JWT)              │
 │                   │───────────────────────────────────────►
 │                   │                    │                  │
 │                   │  Room Connected    │                  │
 │                   │◄───────────────────────────────────────
 │                   │                    │                  │
 │  Speak            │                    │                  │
 │ ═══════════════► │  Audio Stream (WebRTC)                │
 │                   │═══════════════════════════════════════►
 │                   │                    │                  │
 │                   │                    │  Process Audio   │
 │                   │                    │◄═════════════════│
 │                   │                    │                  │
 │                   │                    │  Generate Response
 │                   │                    │═════════════════►│
 │                   │                    │                  │
 │  Hear Response    │  Audio Stream (WebRTC)                │
 │ ◄═══════════════ │◄═══════════════════════════════════════
 │                   │                    │                  │

Style: Use coral arrows for user actions, orange for AI responses
```

### Starting a Conversation

The conversation can start in two modes: **public** (agent ID only) or **private** (requires API key):

```swift
func startConversation() async throws {
    guard state == .idle || state.isEndedOrError else { return }

    state = .connecting

    let agentId = try keychainManager.getAgentId()

    let config = ConversationConfig()
    conversation = try await ElevenLabs.startConversation(
        agentId: agentId,
        config: config
    )

    setupConversationBindings()
    state = .active
}
```

For private agents, we first fetch a signed JWT token:

```swift
func startPrivateConversation() async throws {
    state = .connecting

    let agentId = try keychainManager.getAgentId()
    let apiKey = try keychainManager.getElevenLabsApiKey()

    // Fetch conversation token from ElevenLabs API
    let token = try await TokenService.shared.fetchToken(
        agentId: agentId,
        apiKey: apiKey
    )

    let config = ConversationConfig()
    conversation = try await ElevenLabs.startConversation(
        conversationToken: token,
        config: config
    )

    setupConversationBindings()
    state = .active
}
```

### Reactive State Bindings

The SDK publishes state changes via Combine, which we observe and republish:

```swift
private func setupConversationBindings() {
    guard let conversation else { return }

    // Map SDK state to app state
    conversation.$state
        .receive(on: DispatchQueue.main)
        .sink { [weak self] sdkState in
            switch sdkState {
            case .active: self?.state = .active
            case .ended(let reason): self?.state = .ended("\(reason)")
            case .error(let err): self?.state = .error(err.localizedDescription)
            case .idle: self?.state = .idle
            case .connecting: self?.state = .connecting
            @unknown default: break
            }
        }
        .store(in: &cancellables)

    // Observe agent speaking/listening state
    conversation.$agentState
        .receive(on: DispatchQueue.main)
        .sink { [weak self] sdkAgentState in
            switch sdkAgentState {
            case .listening: self?.agentState = .listening
            case .speaking: self?.agentState = .speaking
            case .thinking: self?.agentState = .listening
            @unknown default: break
            }
        }
        .store(in: &cancellables)
}
```

---

## Building the Voice UI

Voice interfaces require different UI patterns than traditional apps. Users need constant feedback about what's happening, without overwhelming visual elements.

**[DIAGRAM 4: UI Components]**
```
Create an annotated screenshot/mockup showing:

┌─────────────────────────────────────────┐
│  ← OpenClaw                         ⚙️  │  ← Navigation bar
├─────────────────────────────────────────┤
│  ● Connected                            │  ← Status indicator
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────┐       │
│  │ How can I help you today?   │       │  ← Agent message
│  └─────────────────────────────┘       │
│                                         │
│            ┌─────────────────────────┐ │
│            │ What's the weather like?│ │  ← User message
│            └─────────────────────────┘ │
│                                         │
│  ┌─────────────────────────────┐       │
│  │ It's currently 72°F and    │       │
│  │ sunny in San Francisco...   │       │
│  └─────────────────────────────┘       │
│                                         │
├─────────────────────────────────────────┤
│           ○ Speaking                    │  ← Agent state
│                                         │
│              ╭────────╮                 │
│            ╭─┤  ◉◉◉   ├─╮              │  ← Animated orb
│            │ │  ◉◉◉   │ │              │
│            ╰─┤  ◉◉◉   ├─╯              │
│              ╰────────╯                 │
│                                         │
│     ⌨️         🔴          🎤          │  ← Controls
│   keyboard    stop        mute          │
│                                         │
└─────────────────────────────────────────┘

Colors:
- Background: #141110 (dark charcoal)
- User bubble: #D97366 (coral)
- Agent bubble: #1E1C1A (surface)
- Orb: Gradient coral to orange
- Controls: #2D2A28 (elevated surface)
```

### The Animated Orb Visualizer

The orb is the visual centerpiece, providing ambient feedback about the conversation state:

```swift
struct OrbVisualizerView: View {
    let agentState: AgentMode
    let isConnected: Bool

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6
    @State private var innerRotation: Double = 0
    @State private var outerRotation: Double = 0

    var body: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(gradientColor.opacity(0.3), lineWidth: 2)
                    .scaleEffect(scale + CGFloat(i) * 0.2)
                    .opacity(opacity - Double(i) * 0.15)
                    .rotationEffect(.degrees(outerRotation + Double(i) * 30))
            }

            // Middle animated ring with angular gradient
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [gradientColor, gradientColor.opacity(0.3), gradientColor],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .scaleEffect(scale * 0.85)
                .rotationEffect(.degrees(innerRotation))

            // Core orb with radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: orbColors,
                        center: .center,
                        startRadius: 5,
                        endRadius: 50
                    )
                )
                .scaleEffect(scale * 0.7)
                .shadow(color: gradientColor.opacity(0.6), radius: 20)
        }
    }
}
```

The animation adapts based on the agent's state:

```swift
private func updateAnimations(for state: AgentMode) {
    switch state {
    case .speaking:
        // Fast, energetic pulse when speaking
        withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
            scale = 1.15
            opacity = 0.9
        }
    case .listening:
        // Slow, calm pulse when listening
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            scale = 1.0
            opacity = 0.6
        }
    }
}
```

### Color Theme System

OpenClaw uses a warm, dark color palette inspired by Anthropic's design language:

```swift
extension Color {
    // Brand colors
    static let anthropicCoral = Color(red: 0.85, green: 0.45, blue: 0.40)  // #D97366
    static let anthropicOrange = Color(red: 0.90, green: 0.55, blue: 0.35) // #E68C59

    // Background (warm dark tones)
    static let backgroundDark = Color(red: 0.08, green: 0.07, blue: 0.06)   // #141110

    // Surfaces
    static let surfacePrimary = Color(red: 0.14, green: 0.13, blue: 0.12)   // #231F1E
    static let surfaceSecondary = Color(red: 0.18, green: 0.16, blue: 0.15) // #2D2926

    // Text
    static let textPrimary = Color(red: 0.95, green: 0.93, blue: 0.90)      // #F2EDE6
    static let textSecondary = Color(red: 0.70, green: 0.66, blue: 0.62)    // #B3A89E

    // Status
    static let statusConnected = Color(red: 0.45, green: 0.75, blue: 0.55)  // Sage green
    static let statusConnecting = anthropicOrange
    static let statusDisconnected = Color(red: 0.85, green: 0.40, blue: 0.40)
}
```

**[DIAGRAM 5: Color Palette]**
```
Create a color palette visualization:

BRAND COLORS
┌────────────┐  ┌────────────┐
│  Coral     │  │  Orange    │
│  #D97366   │  │  #E68C59   │
└────────────┘  └────────────┘

BACKGROUNDS
┌────────────┐  ┌────────────┐  ┌────────────┐
│  Dark      │  │  Surface 1 │  │  Surface 2 │
│  #141110   │  │  #231F1E   │  │  #2D2926   │
└────────────┘  └────────────┘  └────────────┘

TEXT
┌────────────┐  ┌────────────┐  ┌────────────┐
│  Primary   │  │  Secondary │  │  Tertiary  │
│  #F2EDE6   │  │  #B3A89E   │  │  #807770   │
└────────────┘  └────────────┘  └────────────┘

STATUS
┌────────────┐  ┌────────────┐  ┌────────────┐
│  Connected │  │ Connecting │  │Disconnected│
│  #73BF8C   │  │  #E68C59   │  │  #D96666   │
└────────────┘  └────────────┘  └────────────┘
```

---

## Push Notifications: Making AI Proactive

One of OpenClaw's most powerful features is the ability for the AI agent to *initiate* contact via push notifications. This transforms the relationship from reactive (user asks, AI responds) to proactive (AI reaches out when relevant).

**[DIAGRAM 6: Push Notification Architecture]**
```
Create a system architecture diagram:

┌─────────────────────────────────────────────────────────────────────┐
│                        iOS DEVICE                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    OpenClaw App                              │   │
│  │  ┌──────────────────┐    ┌──────────────────────────────┐  │   │
│  │  │ PushNotification │    │ GatewayNotificationService   │  │   │
│  │  │    Manager       │───►│ • Register device token      │  │   │
│  │  │ • Permissions    │    │ • Handle registration        │  │   │
│  │  │ • Token handling │    └────────────┬─────────────────┘  │   │
│  │  └──────────────────┘                 │                     │   │
│  └───────────────────────────────────────┼─────────────────────┘   │
└──────────────────────────────────────────┼─────────────────────────┘
                                           │
                              HTTPS POST   │  Device Token
                              /hooks/ios-device
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      OPENCLAW GATEWAY (DGX Spark)                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                iOS Push Notifications Plugin                 │   │
│  │  ┌──────────────────┐    ┌──────────────────────────────┐  │   │
│  │  │    index.ts      │    │      apns-notifier.ts        │  │   │
│  │  │ • Plugin entry   │    │ • HTTP/2 client              │  │   │
│  │  │ • Tool: send_ios │───►│ • JWT authentication         │  │   │
│  │  │   _notification  │    │ • Payload formatting         │  │   │
│  │  └──────────────────┘    └────────────┬─────────────────┘  │   │
│  └───────────────────────────────────────┼─────────────────────┘   │
└──────────────────────────────────────────┼─────────────────────────┘
                                           │
                              HTTP/2 POST  │  JWT + Payload
                              /3/device/{token}
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     APPLE PUSH NOTIFICATION SERVICE                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  api.push.apple.com / api.sandbox.push.apple.com            │   │
│  │  • Validates JWT signature                                   │   │
│  │  • Routes to device                                          │   │
│  │  • Handles offline queueing                                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘

Color: Gateway in coral, APNs in orange, iOS app in dark surface
```

### iOS Side: Registering for Notifications

The `PushNotificationManager` handles all notification-related concerns:

```swift
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var permissionStatus: NotificationPermissionStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .provisional]
            )

            permissionStatus = granted ? .authorized : .denied

            if granted {
                await registerForRemoteNotifications()
                registerNotificationCategories()
            }

            return granted
        } catch {
            return false
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        // Convert token data to hex string
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token

        // Register with OpenClaw Gateway
        Task {
            await GatewayNotificationService.shared.registerDevice(token: token)
        }
    }
}
```

We also register custom notification categories for rich interactions:

```swift
private func registerNotificationCategories() {
    let replyAction = UNTextInputNotificationAction(
        identifier: "REPLY_ACTION",
        title: "Reply",
        options: [],
        textInputButtonTitle: "Send",
        textInputPlaceholder: "Type a message..."
    )

    let startChatAction = UNNotificationAction(
        identifier: "START_CHAT_ACTION",
        title: "Start Voice Chat",
        options: [.foreground]
    )

    let messageCategory = UNNotificationCategory(
        identifier: "OPENCLAW_MESSAGE",
        actions: [replyAction, startChatAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )

    UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
}
```

### Server Side: The Gateway Plugin

The OpenClaw Gateway plugin sends notifications via APNs using HTTP/2 and JWT authentication.

**Critical Implementation Detail**: APNs *requires* HTTP/2. The standard Node.js `https` module uses HTTP/1.1 and will fail with cryptic errors.

```typescript
// apns-notifier.ts - HTTP/2 Implementation
import * as http2 from "http2";
import * as crypto from "crypto";
import * as fs from "fs";

export class ApnsNotifier {
    private keyPath: string;
    private keyId: string;
    private teamId: string;
    private bundleId: string;
    private sandbox: boolean;
    private cachedToken: string | null = null;
    private tokenExpiry: number = 0;

    async send(deviceToken: string, payload: NotificationPayload): Promise<void> {
        const host = this.sandbox
            ? "api.sandbox.push.apple.com"
            : "api.push.apple.com";

        const apnsPayload = {
            aps: {
                alert: { title: payload.title, body: payload.body },
                badge: payload.badge,
                sound: payload.sound ?? "default",
            },
        };

        const body = JSON.stringify(apnsPayload);
        const token = this.getAuthToken();

        return new Promise((resolve, reject) => {
            // HTTP/2 is REQUIRED by APNs
            const client = http2.connect(`https://${host}`);

            client.on("error", (err) => {
                reject(new Error(`HTTP/2 connection error: ${err.message}`));
            });

            const req = client.request({
                ":method": "POST",
                ":path": `/3/device/${deviceToken}`,
                "authorization": `bearer ${token}`,
                "apns-topic": this.bundleId,
                "apns-push-type": "alert",
                "apns-priority": "10",
                "content-type": "application/json",
            });

            // Handle response...
            req.write(body);
            req.end();
        });
    }
}
```

### JWT Authentication for APNs

APNs uses ES256-signed JWTs for authentication. The tricky part is converting the DER-encoded signature to raw format:

```typescript
private getAuthToken(): string {
    const now = Math.floor(Date.now() / 1000);

    // Cache tokens for efficiency (valid for 1 hour)
    if (this.cachedToken && now < this.tokenExpiry - 600) {
        return this.cachedToken;
    }

    const privateKey = fs.readFileSync(this.keyPath, "utf8");
    const header = { alg: "ES256", kid: this.keyId };
    const payload = { iss: this.teamId, iat: now };

    const encodedHeader = Buffer.from(JSON.stringify(header)).toString("base64url");
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");

    const signatureInput = `${encodedHeader}.${encodedPayload}`;
    const sign = crypto.createSign("SHA256");
    sign.update(signatureInput);
    const signature = sign.sign(privateKey);

    // Convert DER to raw signature format
    const rawSignature = this.derToRaw(signature);
    const encodedSignature = rawSignature.toString("base64url");

    this.cachedToken = `${signatureInput}.${encodedSignature}`;
    this.tokenExpiry = now + 3600;

    return this.cachedToken;
}

private derToRaw(derSignature: Buffer): Buffer {
    // DER format: 0x30 [length] 0x02 [r-length] [r] 0x02 [s-length] [s]
    let offset = 2;
    if (derSignature[1] & 0x80) {
        offset += derSignature[1] & 0x7f;
    }

    const rLength = derSignature[offset + 1];
    const rStart = offset + 2;
    let r = derSignature.subarray(rStart, rStart + rLength);

    const sOffset = rStart + rLength;
    const sLength = derSignature[sOffset + 1];
    const sStart = sOffset + 2;
    let s = derSignature.subarray(sStart, sStart + sLength);

    // Normalize to 32 bytes each
    if (r.length > 32) r = r.subarray(r.length - 32);
    if (s.length > 32) s = s.subarray(s.length - 32);

    const rawSignature = Buffer.alloc(64);
    r.copy(rawSignature, 32 - r.length);
    s.copy(rawSignature, 64 - s.length);

    return rawSignature;
}
```

---

## Lessons Learned

Building OpenClaw taught us several important lessons:

### 1. Let the SDK Manage Audio

Initially, we tried to configure `AVAudioSession` ourselves, which conflicted with LiveKit's audio management:

```swift
// DON'T DO THIS - conflicts with LiveKit
func configureForVoiceChat() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [...])
    try session.setActive(true)
}
```

**Solution**: Let the ElevenLabs SDK (which uses LiveKit internally) handle audio session configuration.

### 2. HTTP/2 is Mandatory for APNs

APNs does not support HTTP/1.1. Using the standard `https` module in Node.js will fail with:

```
Parse Error: Expected HTTP/, RTSP/ or ICE/
```

**Solution**: Always use the `http2` module for APNs communication.

### 3. Deduplicate Messages from the SDK

The ElevenLabs SDK sometimes emits duplicate messages. We handle this by deduplicating based on content and role:

```swift
conversation.$messages
    .receive(on: DispatchQueue.main)
    .sink { [weak self] sdkMessages in
        var seen = Set<String>()
        var uniqueMessages: [ConversationMessage] = []

        for msg in sdkMessages {
            let key = "\(msg.role)-\(msg.content)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueMessages.append(ConversationMessage(
                    id: msg.id,
                    source: msg.role == .user ? .user : .ai,
                    message: msg.content
                ))
            }
        }

        self?.messages = uniqueMessages
    }
    .store(in: &cancellables)
```

### 4. Auto-Register on App Launch

If the user has already granted notification permissions, register for remote notifications immediately:

```swift
func checkPermissionStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()

    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        permissionStatus = .authorized
        // Critical: Register even if already authorized
        await registerForRemoteNotifications()
    case .denied:
        permissionStatus = .denied
    case .notDetermined:
        permissionStatus = .notDetermined
    @unknown default:
        break
    }
}
```

---

## Performance Considerations

**[DIAGRAM 7: Performance Metrics]**
```
Create a dashboard-style visualization:

┌─────────────────────────────────────────────────────────────────┐
│                    PERFORMANCE METRICS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Connection Time          Audio Latency          Battery Impact  │
│  ┌─────────────┐         ┌─────────────┐        ┌─────────────┐ │
│  │   ~1.5s     │         │  ~200ms     │        │    Low      │ │
│  │  to active  │         │  round-trip │        │   WebRTC    │ │
│  │  state      │         │             │        │  efficient  │ │
│  └─────────────┘         └─────────────┘        └─────────────┘ │
│                                                                  │
│  Memory Usage            Network                App Size         │
│  ┌─────────────┐         ┌─────────────┐        ┌─────────────┐ │
│  │   ~80MB     │         │  ~50kbps    │        │   ~25MB     │ │
│  │  during     │         │  average    │        │  installed  │ │
│  │  active call│         │  streaming  │        │             │ │
│  └─────────────┘         └─────────────┘        └─────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Tips for Production

1. **Cache JWT tokens** - They're valid for 1 hour, no need to regenerate every request
2. **Use sandbox for development** - `api.sandbox.push.apple.com` is more forgiving
3. **Monitor network state** - Gracefully handle connectivity changes
4. **Lazy-load settings** - Only fetch credentials when needed

---

## Conclusion

OpenClaw demonstrates that building a production-quality voice AI assistant for iOS is achievable with modern tools and frameworks. The combination of:

- **ElevenLabs' Conversational AI** for natural voice interactions
- **SwiftUI** for declarative, reactive UI
- **HTTP/2 and APNs** for proactive notifications
- **Clean architecture** for maintainability

...creates a foundation for voice-first AI experiences.

**[DIAGRAM 8: Summary]**
```
Create a final summary visual:

┌─────────────────────────────────────────────────────────────────┐
│                        OPENCLAW                                  │
│                 Voice AI for iOS                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐ │
│   │  Voice   │    │  Modern  │    │  Push    │    │  Secure  │ │
│   │   AI     │    │    UI    │    │  Notify  │    │ Storage  │ │
│   │          │    │          │    │          │    │          │ │
│   │ElevenLabs│    │ SwiftUI  │    │   APNs   │    │ Keychain │ │
│   │  WebRTC  │    │ Animated │    │  HTTP/2  │    │   JWT    │ │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘ │
│                                                                  │
│   github.com/acidoom/OpenClaw-app                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Style: Coral/orange gradient banner, dark cards
```

The full source code is available on GitHub. I hope this deep dive helps you build your own voice AI experiences!

---

## Resources

- [OpenClaw GitHub Repository](https://github.com/acidoom/OpenClaw-app)
- [ElevenLabs Conversational AI Documentation](https://elevenlabs.io/docs/conversational-ai)
- [Apple Push Notification Service Documentation](https://developer.apple.com/documentation/usernotifications)
- [LiveKit iOS SDK](https://docs.livekit.io/client-sdk-swift)

---

*Have questions or feedback? Feel free to open an issue on GitHub or reach out on Twitter.*
