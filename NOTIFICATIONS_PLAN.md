# OpenClaw Notifications - Implementation Plan (Revised)

## Executive Summary

This document outlines the implementation plan for adding **push notifications** and **proactive AI outreach** to the OpenClaw iOS app.

**Key Insight**: OpenClaw already has built-in infrastructure for proactive notifications through its **Heartbeat system**, **Webhooks**, and **Broadcast Groups**. We should leverage these existing features rather than building a separate notification backend.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [OpenClaw's Existing Notification Infrastructure](#openclaws-existing-notification-infrastructure)
3. [Implementation Approach](#implementation-approach)
4. [Phase 1: iOS APNs Foundation](#phase-1-ios-apns-foundation)
5. [Phase 2: OpenClaw Gateway Integration](#phase-2-openclaw-gateway-integration)
6. [Phase 3: Heartbeat-Driven Notifications](#phase-3-heartbeat-driven-notifications)
7. [Phase 4: Webhook-Triggered Outreach](#phase-4-webhook-triggered-outreach)
8. [Phase 5: Deep Linking & Actions](#phase-5-deep-linking--actions)
9. [Security Considerations](#security-considerations)
10. [File Changes Summary](#file-changes-summary)

---

## Architecture Overview

### The Right Approach: Leverage OpenClaw Gateway

Instead of building a separate notification service, we should integrate with OpenClaw's existing **Gateway architecture**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      OpenClaw Gateway                                   │
│                                                                         │
│  ┌─────────────────┐    ┌─────────────────────┐                        │
│  │   Heartbeat     │───►│   Agent Turn        │                        │
│  │   (30m cycle)   │    │   (checks urgent)   │                        │
│  └─────────────────┘    └──────────┬──────────┘                        │
│                                    │                                    │
│  ┌─────────────────┐               │                                    │
│  │   Webhooks      │───────────────┤                                    │
│  │   /hooks/agent  │               │                                    │
│  └─────────────────┘               ▼                                    │
│                         ┌─────────────────────┐                        │
│  ┌─────────────────┐    │  Notification       │    ┌─────────────────┐  │
│  │   Cron Jobs     │───►│  Router (NEW)       │───►│  APNs Module    │  │
│  │   (scheduled)   │    │                     │    │  (NEW)          │  │
│  └─────────────────┘    └─────────────────────┘    └────────┬────────┘  │
│                                                              │          │
│  ┌─────────────────────────────────────────────────────────┐│          │
│  │              Device Registry (NEW)                      ││          │
│  │  - iOS device tokens                                    ││          │
│  │  - Stored in Gateway config/database                    ││          │
│  └─────────────────────────────────────────────────────────┘│          │
│                                                              │          │
└──────────────────────────────────────────────────────────────┼──────────┘
                                                               │
                         Tailscale/VPN                         │
                                                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Apple Push Notification Service                      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         iOS Device                                      │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      OpenClaw iOS App                            │   │
│  │                                                                  │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │   │
│  │  │ PushNotification │  │ Gateway WebSocket │  │ Notification  │  │   │
│  │  │    Manager       │  │    Client        │  │   Delegate    │  │   │
│  │  └──────────────────┘  └──────────────────┘  └───────────────┘  │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## OpenClaw's Existing Notification Infrastructure

Based on the [OpenClaw documentation](https://docs.openclaw.ai/), the platform already has several mechanisms for proactive outreach:

### 1. Heartbeat System

From the [Heartbeat documentation](https://docs.openclaw.ai/gateway/heartbeat.md):

> "Heartbeat runs periodic agent turns in the main session so the model can surface anything that needs attention without spamming you."

**Key Features:**
- Runs every 30 minutes by default
- Checks `HEARTBEAT.md` workspace file
- Can be triggered manually: `openclaw system event --text "Check for urgent follow-ups" --mode now`
- Supports active hours configuration (e.g., 9am-10pm)
- Returns `HEARTBEAT_OK` when nothing needs attention

### 2. Webhooks

From the [Webhooks documentation](https://docs.openclaw.ai/automation/webhook.md):

**Available Endpoints:**
- `POST /hooks/wake` — Triggers system events for the main session
- `POST /hooks/agent` — Runs an isolated agent turn with customization
- `POST /hooks/<name>` — Custom mapped endpoints

**The `/hooks/agent` endpoint supports:**
```json
{
  "message": "Check if user needs a reminder",
  "deliver": true,
  "to": "whatsapp:+1234567890"
}
```

### 3. Broadcast Groups

From the [Broadcast Groups documentation](https://docs.openclaw.ai/broadcast-groups.md):

Enables multi-channel message distribution - the same notification can go to WhatsApp, Telegram, Discord, Slack, etc.

### 4. Gateway WebSocket Events

The Gateway emits server-push events including:
- `agent` — Agent activity updates
- `chat` — New messages
- `presence` — User/agent presence
- `heartbeat` — Heartbeat triggers
- `cron` — Scheduled task events

---

## Implementation Approach

### What We Need to Add

1. **APNs Module for Gateway** — A new module that sends push notifications to iOS devices
2. **Device Registry** — Store iOS device tokens in Gateway config
3. **Notification Router** — Route heartbeat/webhook triggers to APNs
4. **iOS App Integration** — Register device tokens with Gateway

### What We Leverage (Already Exists)

- Heartbeat system for periodic checks
- Webhooks for external triggers
- Cron jobs for scheduled notifications
- Gateway WebSocket for real-time updates
- `system.notify` tool (currently macOS only, extend to iOS)

---

## Phase 1: iOS APNs Foundation

### Prerequisites

1. **Apple Developer Account** with Push Notifications capability
2. **APNs Authentication Key** (.p8 file)
3. **App ID** with Push Notifications enabled

### Step 1.1: Generate APNs Key

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create a new key with **Apple Push Notifications service (APNs)**
3. Download the `.p8` file (one-time download!)
4. Note the **Key ID** and **Team ID**

### Step 1.2: Enable Push Notifications in Xcode

1. Select **OpenClaw** target → **Signing & Capabilities**
2. Add **Push Notifications** capability
3. Add **Background Modes** → Check **Remote notifications**

### Step 1.3: Create iOS Push Notification Files

#### File: `OpenClaw/Services/PushNotificationManager.swift`

```swift
//
//  PushNotificationManager.swift
//  OpenClaw
//
//  Manages APNs registration and notification permissions
//

import Foundation
import UserNotifications
import UIKit

enum NotificationPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
}

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var permissionStatus: NotificationPermissionStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var registrationError: String?

    private override init() {
        super.init()
    }

    // MARK: - Permission Handling

    func checkPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            permissionStatus = .notDetermined
        case .authorized:
            permissionStatus = .authorized
        case .denied:
            permissionStatus = .denied
        case .provisional:
            permissionStatus = .provisional
        case .ephemeral:
            permissionStatus = .authorized
        @unknown default:
            permissionStatus = .notDetermined
        }
    }

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
            print("[PushNotification] Permission request error: \(error)")
            return false
        }
    }

    // MARK: - APNs Registration

    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        self.registrationError = nil
        print("[PushNotification] Device token: \(token.prefix(16))...")

        // Register with OpenClaw Gateway
        Task {
            await GatewayNotificationService.shared.registerDevice(token: token)
        }
    }

    func handleRegistrationError(_ error: Error) {
        self.registrationError = error.localizedDescription
        print("[PushNotification] Registration error: \(error)")
    }

    // MARK: - Notification Categories

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

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 1 hour",
            options: []
        )

        // OpenClaw message category
        let messageCategory = UNNotificationCategory(
            identifier: "OPENCLAW_MESSAGE",
            actions: [replyAction, startChatAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Heartbeat alert category
        let heartbeatCategory = UNNotificationCategory(
            identifier: "OPENCLAW_HEARTBEAT",
            actions: [startChatAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        // Reminder category
        let reminderCategory = UNNotificationCategory(
            identifier: "OPENCLAW_REMINDER",
            actions: [startChatAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            messageCategory,
            heartbeatCategory,
            reminderCategory
        ])
    }

    // MARK: - Badge Management

    func clearBadge() async {
        UIApplication.shared.applicationIconBadgeNumber = 0
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
```

#### File: `OpenClaw/Services/GatewayNotificationService.swift`

```swift
//
//  GatewayNotificationService.swift
//  OpenClaw
//
//  Registers iOS device with OpenClaw Gateway for push notifications
//

import Foundation
import UIKit

actor GatewayNotificationService {
    static let shared = GatewayNotificationService()

    private var isRegistered = false
    private var lastRegisteredToken: String?

    /// OpenClaw Gateway URL (from settings or default)
    private var gatewayURL: String? {
        try? KeychainManager.shared.get(.openClawEndpoint)
    }

    /// Hook token for webhook authentication
    private var hookToken: String? {
        try? KeychainManager.shared.get(.gatewayHookToken)
    }

    // MARK: - Device Registration

    /// Register device token with OpenClaw Gateway
    func registerDevice(token: String) async {
        guard token != lastRegisteredToken else {
            print("[GatewayNotification] Already registered with this token")
            return
        }

        guard let baseURL = gatewayURL else {
            print("[GatewayNotification] Gateway URL not configured")
            return
        }

        // Use the webhook endpoint to register the device
        // This could be a custom hook or we extend the Gateway
        guard let url = URL(string: "\(baseURL)/hooks/ios-device") else {
            print("[GatewayNotification] Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add hook token authentication
        if let token = hookToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "action": "register",
            "device_token": token,
            "device_name": await UIDevice.current.name,
            "device_model": await UIDevice.current.model,
            "os_version": await UIDevice.current.systemVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.openclaw.app"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[GatewayNotification] Device registered with Gateway")
                    lastRegisteredToken = token
                    isRegistered = true
                } else {
                    print("[GatewayNotification] Registration failed: HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[GatewayNotification] Registration error: \(error)")
        }
    }

    /// Unregister device from Gateway
    func unregisterDevice() async {
        guard let token = lastRegisteredToken,
              let baseURL = gatewayURL,
              let url = URL(string: "\(baseURL)/hooks/ios-device") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let hookToken = hookToken {
            request.setValue("Bearer \(hookToken)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "action": "unregister",
            "device_token": token
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try await URLSession.shared.data(for: request)
            lastRegisteredToken = nil
            isRegistered = false
            print("[GatewayNotification] Device unregistered")
        } catch {
            print("[GatewayNotification] Unregister error: \(error)")
        }
    }
}
```

---

## Phase 2: OpenClaw Gateway Integration

### Option A: Extend OpenClaw Gateway (Recommended)

Create a new module for the OpenClaw Gateway that handles iOS push notifications.

#### Gateway Extension: `apns-notifier.ts` (TypeScript/Node.js)

```typescript
/**
 * APNs Notifier Module for OpenClaw Gateway
 *
 * This module extends the Gateway to support iOS push notifications
 * triggered by heartbeat, webhooks, or agent decisions.
 */

import jwt from 'jsonwebtoken';
import http2 from 'http2';
import fs from 'fs';
import path from 'path';

interface APNsConfig {
  keyPath: string;      // Path to .p8 file
  keyId: string;        // Key ID from Apple
  teamId: string;       // Team ID from Apple
  bundleId: string;     // App bundle identifier
  sandbox: boolean;     // Use sandbox or production
}

interface DeviceInfo {
  token: string;
  deviceName: string;
  registeredAt: Date;
  lastSeenAt: Date;
}

interface NotificationPayload {
  title: string;
  body: string;
  subtitle?: string;
  category?: string;
  badge?: number;
  data?: Record<string, any>;
}

class APNsNotifier {
  private config: APNsConfig;
  private privateKey: string;
  private devices: Map<string, DeviceInfo> = new Map();
  private jwtToken: string | null = null;
  private jwtExpiry: number = 0;

  constructor(config: APNsConfig) {
    this.config = config;
    this.privateKey = fs.readFileSync(config.keyPath, 'utf8');
  }

  // Generate or reuse JWT token
  private getToken(): string {
    const now = Math.floor(Date.now() / 1000);

    // Refresh if expired (tokens valid for 1 hour)
    if (!this.jwtToken || now >= this.jwtExpiry - 60) {
      this.jwtToken = jwt.sign(
        { iss: this.config.teamId, iat: now },
        this.privateKey,
        {
          algorithm: 'ES256',
          header: { kid: this.config.keyId }
        }
      );
      this.jwtExpiry = now + 3600;
    }

    return this.jwtToken;
  }

  // Register a device
  registerDevice(token: string, info: Partial<DeviceInfo>): void {
    this.devices.set(token, {
      token,
      deviceName: info.deviceName || 'Unknown',
      registeredAt: info.registeredAt || new Date(),
      lastSeenAt: new Date()
    });
    console.log(`[APNs] Registered device: ${token.substring(0, 16)}...`);
  }

  // Unregister a device
  unregisterDevice(token: string): boolean {
    const deleted = this.devices.delete(token);
    if (deleted) {
      console.log(`[APNs] Unregistered device: ${token.substring(0, 16)}...`);
    }
    return deleted;
  }

  // Send notification to a single device
  async send(deviceToken: string, payload: NotificationPayload): Promise<boolean> {
    const host = this.config.sandbox
      ? 'api.sandbox.push.apple.com'
      : 'api.push.apple.com';

    const apnsPayload = {
      aps: {
        alert: {
          title: payload.title,
          body: payload.body,
          ...(payload.subtitle && { subtitle: payload.subtitle })
        },
        sound: 'default',
        category: payload.category || 'OPENCLAW_MESSAGE',
        'mutable-content': 1,
        'thread-id': 'openclaw',
        ...(payload.badge !== undefined && { badge: payload.badge })
      },
      ...(payload.data && { openclaw: payload.data })
    };

    return new Promise((resolve) => {
      const client = http2.connect(`https://${host}`);

      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        'authorization': `bearer ${this.getToken()}`,
        'apns-topic': this.config.bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json'
      });

      req.on('response', (headers) => {
        const status = headers[':status'];
        if (status === 200) {
          console.log(`[APNs] Notification sent to ${deviceToken.substring(0, 16)}...`);
          resolve(true);
        } else {
          console.error(`[APNs] Error ${status} for ${deviceToken.substring(0, 16)}...`);
          resolve(false);
        }
        client.close();
      });

      req.write(JSON.stringify(apnsPayload));
      req.end();
    });
  }

  // Send to all registered devices
  async sendToAll(payload: NotificationPayload): Promise<number> {
    const tokens = Array.from(this.devices.keys());
    let successCount = 0;

    for (const token of tokens) {
      const success = await this.send(token, payload);
      if (success) successCount++;
    }

    return successCount;
  }

  // Get all registered devices
  getDevices(): DeviceInfo[] {
    return Array.from(this.devices.values());
  }
}

export { APNsNotifier, APNsConfig, NotificationPayload, DeviceInfo };
```

#### Gateway Webhook Handler Extension

```typescript
/**
 * Add this to the Gateway's webhook handler to support iOS device registration
 * and notification triggers.
 */

import { APNsNotifier } from './apns-notifier';

// Initialize APNs notifier (from config)
const apns = new APNsNotifier({
  keyPath: process.env.APNS_KEY_PATH || './AuthKey.p8',
  keyId: process.env.APNS_KEY_ID || '',
  teamId: process.env.APNS_TEAM_ID || '',
  bundleId: process.env.APNS_BUNDLE_ID || 'com.openclaw.app',
  sandbox: process.env.APNS_SANDBOX === 'true'
});

// Add webhook endpoint for iOS device management
// POST /hooks/ios-device
async function handleIOSDevice(req: Request): Promise<Response> {
  const body = await req.json();

  switch (body.action) {
    case 'register':
      apns.registerDevice(body.device_token, {
        deviceName: body.device_name
      });
      return new Response(JSON.stringify({ status: 'registered' }));

    case 'unregister':
      apns.unregisterDevice(body.device_token);
      return new Response(JSON.stringify({ status: 'unregistered' }));

    default:
      return new Response(JSON.stringify({ error: 'Unknown action' }), { status: 400 });
  }
}

// Add webhook endpoint to trigger iOS notifications
// POST /hooks/ios-notify
async function handleIOSNotify(req: Request): Promise<Response> {
  const body = await req.json();

  const sent = await apns.sendToAll({
    title: body.title || 'OpenClaw',
    body: body.body || body.message,
    subtitle: body.subtitle,
    category: body.category || 'OPENCLAW_MESSAGE',
    badge: body.badge,
    data: body.data || { type: 'start_conversation' }
  });

  return new Response(JSON.stringify({
    status: 'sent',
    devices_notified: sent
  }));
}

// Export for integration with Gateway hooks
export { handleIOSDevice, handleIOSNotify, apns };
```

### Option B: Standalone Sidecar Service

If you prefer not to modify the Gateway, run a sidecar service that:
1. Connects to Gateway WebSocket
2. Listens for `heartbeat` and `agent` events
3. Forwards notifications to APNs

---

## Phase 3: Heartbeat-Driven Notifications

### How It Works

1. Gateway's heartbeat runs every 30 minutes
2. Agent checks `HEARTBEAT.md` and decides if user needs notification
3. If urgent, agent calls `system.notify` tool (extended for iOS)
4. Notification sent via APNs

### Extend system.notify Tool

Add iOS support to the existing `system.notify` tool:

```typescript
// Extended system.notify tool
async function systemNotify(params: {
  title: string;
  message: string;
  platform?: 'macos' | 'ios' | 'all';
}): Promise<void> {
  const platform = params.platform || 'all';

  if (platform === 'macos' || platform === 'all') {
    // Existing macOS notification
    await notifyMacOS(params.title, params.message);
  }

  if (platform === 'ios' || platform === 'all') {
    // New iOS notification via APNs
    await apns.sendToAll({
      title: params.title,
      body: params.message,
      category: 'OPENCLAW_HEARTBEAT',
      data: { type: 'start_conversation', context: 'heartbeat' }
    });
  }
}
```

### Example HEARTBEAT.md

```markdown
# Heartbeat Checklist

Check the following and notify user if any are urgent:

1. Calendar events in next 2 hours
2. Unread messages requiring response
3. Pending tasks past due date
4. System health alerts

If nothing urgent, return HEARTBEAT_OK.
If something needs attention, call system.notify with a brief summary.
```

---

## Phase 4: Webhook-Triggered Outreach

### Use Existing Webhooks for External Triggers

External services can trigger notifications via the Gateway webhook:

```bash
# Trigger notification via webhook
curl -X POST https://your-gateway.ts.net/hooks/ios-notify \
  -H "Authorization: Bearer your-hook-token" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Task Complete",
    "body": "Your background job finished processing",
    "category": "OPENCLAW_MESSAGE",
    "data": {"type": "show_message", "task_id": "123"}
  }'
```

### Chain with /hooks/agent for AI-Generated Content

```bash
# Let OpenClaw generate the notification content
curl -X POST https://your-gateway.ts.net/hooks/agent \
  -H "Authorization: Bearer your-hook-token" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Generate a brief notification about the completed data analysis. Then call system.notify to send it.",
    "deliver": false
  }'
```

---

## Phase 5: Deep Linking & Actions

### Update AppState for Deep Linking

```swift
// OpenClaw/App/AppState.swift

enum DeepLinkAction: Equatable {
    case startConversation(context: String?)
    case showMessage(String)
    case sendMessage(String, context: String?)
    case openSettings

    static func == (lhs: DeepLinkAction, rhs: DeepLinkAction) -> Bool {
        switch (lhs, rhs) {
        case (.startConversation(let a), .startConversation(let b)):
            return a == b
        case (.showMessage(let a), .showMessage(let b)):
            return a == b
        case (.sendMessage(let m1, let c1), .sendMessage(let m2, let c2)):
            return m1 == m2 && c1 == c2
        case (.openSettings, .openSettings):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isConfigured: Bool = false
    @Published var showOnboarding: Bool = false

    // Notification state
    @Published var notificationPermission: NotificationPermissionStatus = .notDetermined
    @Published var pendingAction: DeepLinkAction?

    // ... existing code ...

    func clearPendingAction() {
        pendingAction = nil
    }
}
```

### Notification Delegate

```swift
// OpenClaw/App/NotificationDelegate.swift

import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        let openclawData = userInfo["openclaw"] as? [String: Any]
        let notificationType = openclawData?["type"] as? String
        let context = openclawData?["context"] as? String
        let message = openclawData?["message"] as? String

        await MainActor.run {
            switch actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                handleNotificationTap(type: notificationType, context: context, message: message)

            case "START_CHAT_ACTION":
                AppState.shared.pendingAction = .startConversation(context: context)

            case "REPLY_ACTION":
                if let textResponse = response as? UNTextInputNotificationResponse {
                    handleQuickReply(text: textResponse.userText, context: context)
                }

            case "SNOOZE_ACTION":
                scheduleSnooze(originalNotification: response.notification)

            default:
                break
            }
        }
    }

    private func handleNotificationTap(type: String?, context: String?, message: String?) {
        switch type {
        case "start_conversation":
            AppState.shared.pendingAction = .startConversation(context: context)
        case "show_message":
            if let message = message {
                AppState.shared.pendingAction = .showMessage(message)
            }
        default:
            AppState.shared.pendingAction = .startConversation(context: nil)
        }
    }

    private func handleQuickReply(text: String, context: String?) {
        AppState.shared.pendingAction = .sendMessage(text, context: context)
    }

    private func scheduleSnooze(originalNotification: UNNotification) {
        let content = originalNotification.request.content.mutableCopy() as! UNMutableNotificationContent
        content.title = "Reminder: \(content.title)"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

---

## Security Considerations

### Authentication Flow

```
iOS App                    Gateway                      APNs
   │                          │                           │
   │ Register device token    │                           │
   │ + Hook token auth        │                           │
   │─────────────────────────►│                           │
   │                          │                           │
   │                          │ Store in device registry  │
   │                          │                           │
   │                          │ Heartbeat triggers        │
   │                          │ notification              │
   │                          │                           │
   │                          │ JWT-signed request        │
   │                          │──────────────────────────►│
   │                          │                           │
   │◄─────────────────────────────────────────────────────│
   │                     Push notification                │
```

### Security Checklist

| Component | Security Measure |
|-----------|------------------|
| APNs .p8 Key | Stored on Gateway server, chmod 600, never in git |
| Hook Token | Required for device registration webhook |
| Gateway Connection | Via Tailscale/VPN or SSH tunnel |
| Device Tokens | Stored in Gateway, tokens are opaque |
| iOS Keychain | Hook token stored encrypted |

---

## File Changes Summary

### New iOS Files

| File | Purpose |
|------|---------|
| `Services/PushNotificationManager.swift` | APNs registration, permissions |
| `Services/GatewayNotificationService.swift` | Register with Gateway |
| `App/AppDelegate.swift` | APNs callbacks |
| `App/NotificationDelegate.swift` | Handle notification taps |

### Modified iOS Files

| File | Changes |
|------|---------|
| `App/AppState.swift` | Add `DeepLinkAction`, `pendingAction` |
| `OpenClawApp.swift` | Add AppDelegate adaptor |
| `Services/KeychainManager.swift` | Add `gatewayHookToken` key |
| `Features/Settings/SettingsView.swift` | Notification preferences |

### Gateway Extensions (TypeScript/Node.js)

| File | Purpose |
|------|---------|
| `apns-notifier.ts` | APNs HTTP/2 client |
| Webhook handlers | `/hooks/ios-device`, `/hooks/ios-notify` |
| Extended `system.notify` | iOS support for notifications |

### Xcode Project

- Add **Push Notifications** capability
- Add **Background Modes** → Remote notifications

---

## Key Differences from Original Plan

| Aspect | Original Plan | Revised Plan |
|--------|---------------|--------------|
| Backend | Separate FastAPI service | Extend OpenClaw Gateway |
| Triggers | Custom scheduler | Gateway Heartbeat + Webhooks |
| Device Registry | Separate SQLite DB | Gateway config/storage |
| AI Integration | Separate tool handler | Extend `system.notify` |
| Authentication | Separate secret | Gateway hook token |

---

## References

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [Heartbeat System](https://docs.openclaw.ai/gateway/heartbeat.md)
- [Webhooks](https://docs.openclaw.ai/automation/webhook.md)
- [Gateway Architecture](https://docs.openclaw.ai/concepts/architecture.md)
- [ElevenLabs Post-Call Webhooks](https://elevenlabs.io/docs/agents-platform/workflows/post-call-webhooks)

---

<p align="center">
  <em>OpenClaw Notifications Implementation Plan v2.0</em><br>
  <em>Leveraging OpenClaw Gateway Infrastructure</em>
</p>
