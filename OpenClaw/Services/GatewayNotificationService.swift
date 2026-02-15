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
    private let maxRetries = 3

    private var gatewayURL: String? {
        try? KeychainManager.shared.get(.openClawEndpoint)
    }

    private var hookToken: String? {
        try? KeychainManager.shared.get(.gatewayHookToken)
    }

    // MARK: - Device Registration

    func registerDevice(token: String) async {
        guard token != lastRegisteredToken else {
            Log.debug("Gateway: already registered with this token")
            return
        }

        guard let baseURL = gatewayURL, !baseURL.isEmpty else {
            Log.debug("Gateway: URL not configured, skipping registration")
            return
        }

        guard let url = URL(string: "\(baseURL)/hooks/ios-device") else {
            Log.error("Gateway: invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let hookToken = hookToken {
            request.setValue("Bearer \(hookToken)", forHTTPHeaderField: "Authorization")
        }

        let deviceName = await MainActor.run { UIDevice.current.name }
        let deviceModel = await MainActor.run { UIDevice.current.model }
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }

        let body: [String: Any] = [
            "action": "register",
            "device_token": token,
            "device_name": deviceName,
            "device_model": deviceModel,
            "os_version": osVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.openclaw.app"
        ]

        for attempt in 0..<maxRetries {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        Log.info("Gateway: device registered")
                        lastRegisteredToken = token
                        isRegistered = true
                        return
                    } else {
                        Log.error("Gateway: registration failed HTTP \(httpResponse.statusCode)")
                    }
                }
                return // non-retryable HTTP error
            } catch {
                Log.error("Gateway: registration error (attempt \(attempt + 1)): \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    func unregisterDevice() async {
        guard let token = lastRegisteredToken,
              let baseURL = gatewayURL,
              let url = URL(string: "\(baseURL)/hooks/ios-device") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

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
            Log.info("Gateway: device unregistered")
        } catch {
            Log.error("Gateway: unregister error: \(error.localizedDescription)")
        }
    }

    func getRegistrationStatus() -> Bool {
        isRegistered
    }

    func getMaskedToken() -> String? {
        guard let token = lastRegisteredToken else { return nil }
        return String(token.prefix(8)) + "..." + String(token.suffix(8))
    }
}
