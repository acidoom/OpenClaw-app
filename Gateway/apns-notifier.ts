/**
 * APNs Notifier - HTTP/2 implementation for Apple Push Notification service
 *
 * Uses HTTP/2 as required by APNs (HTTP/1.1 is not supported)
 * Manages device registration and notification delivery.
 */

import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import * as http2 from "http2";
import * as os from "os";

export interface ApnsConfig {
  keyPath: string;
  keyId: string;
  teamId: string;
  bundleId: string;
  sandbox?: boolean;
}

export interface NotificationPayload {
  title: string;
  body: string;
  subtitle?: string;
  category?: string;
  badge?: number;
  sound?: string;
  data?: Record<string, unknown>;
}

export interface SendResult {
  success: boolean;
  deviceToken: string;
  error?: string;
}

export interface RegisteredDevice {
  token: string;
  deviceName?: string;
  deviceModel?: string;
  osVersion?: string;
  appVersion?: string;
  registeredAt: Date;
  lastSeenAt: Date;
}

export { ApnsNotifier as APNsNotifier };

export class ApnsNotifier {
  private keyPath: string;
  private keyId: string;
  private teamId: string;
  private bundleId: string;
  private sandbox: boolean;
  private cachedToken: string | null = null;
  private tokenExpiry: number = 0;
  private devices: Map<string, RegisteredDevice> = new Map();
  private deviceStorePath: string;

  constructor(config: ApnsConfig) {
    this.keyPath = config.keyPath;
    this.keyId = config.keyId;
    this.teamId = config.teamId;
    this.bundleId = config.bundleId;
    this.sandbox = config.sandbox ?? true;

    // Persist devices to ~/.openclaw/devices.json
    const dataDir = path.join(os.homedir(), ".openclaw");
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }
    this.deviceStorePath = path.join(dataDir, "devices.json");
    this.loadDevices();

    console.log(
      `[ApnsNotifier] Initialized: bundleId=${this.bundleId} sandbox=${this.sandbox} devices=${this.devices.size}`
    );
  }

  // ---------------------------------------------------------------------------
  // Device Management
  // ---------------------------------------------------------------------------

  registerDevice(
    token: string,
    info?: {
      deviceName?: string;
      deviceModel?: string;
      osVersion?: string;
      appVersion?: string;
    }
  ): void {
    const now = new Date();
    const existing = this.devices.get(token);
    this.devices.set(token, {
      token,
      deviceName: info?.deviceName ?? existing?.deviceName,
      deviceModel: info?.deviceModel ?? existing?.deviceModel,
      osVersion: info?.osVersion ?? existing?.osVersion,
      appVersion: info?.appVersion ?? existing?.appVersion,
      registeredAt: existing?.registeredAt ?? now,
      lastSeenAt: now,
    });
    this.saveDevices();
    console.log(
      `[ApnsNotifier] Device registered: ${token.substring(0, 8)}... (total: ${this.devices.size})`
    );
  }

  unregisterDevice(token: string): boolean {
    const removed = this.devices.delete(token);
    if (removed) {
      this.saveDevices();
      console.log(
        `[ApnsNotifier] Device unregistered: ${token.substring(0, 8)}... (total: ${this.devices.size})`
      );
    }
    return removed;
  }

  getDeviceCount(): number {
    return this.devices.size;
  }

  getDevices(): RegisteredDevice[] {
    return Array.from(this.devices.values());
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  async send(
    deviceToken: string,
    payload: NotificationPayload
  ): Promise<SendResult> {
    console.log(
      "[ApnsNotifier] send() called for token:",
      deviceToken.substring(0, 8) + "..."
    );

    const host = this.sandbox
      ? "api.sandbox.push.apple.com"
      : "api.push.apple.com";

    const alert: Record<string, string> = {
      title: payload.title,
      body: payload.body,
    };
    if (payload.subtitle) {
      alert.subtitle = payload.subtitle;
    }

    const aps: Record<string, unknown> = {
      alert,
      sound: payload.sound ?? "default",
    };
    if (payload.badge !== undefined) {
      aps.badge = payload.badge;
    }
    if (payload.category) {
      aps.category = payload.category;
    }

    const apnsPayload: Record<string, unknown> = { aps, ...payload.data };
    const body = JSON.stringify(apnsPayload);
    const token = this.getAuthToken();

    return new Promise((resolve) => {
      const client = http2.connect(`https://${host}`);

      client.on("error", (err: Error) => {
        console.error("[ApnsNotifier] HTTP/2 connection error:", err.message);
        resolve({
          success: false,
          deviceToken,
          error: `HTTP/2 connection error: ${err.message}`,
        });
      });

      const req = client.request({
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${token}`,
        "apns-topic": this.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body).toString(),
      });

      let responseData = "";
      let statusCode: number | undefined;

      req.on("response", (headers: http2.IncomingHttpHeaders) => {
        statusCode = headers[":status"] as number;
      });

      req.on("data", (chunk: Buffer) => {
        responseData += chunk.toString();
      });

      req.on("end", () => {
        client.close();
        if (statusCode === 200) {
          console.log("[ApnsNotifier] Notification sent successfully!");
          // Update lastSeenAt on successful delivery
          const device = this.devices.get(deviceToken);
          if (device) {
            device.lastSeenAt = new Date();
          }
          resolve({ success: true, deviceToken });
        } else {
          console.error("[ApnsNotifier] APNs error:", statusCode, responseData);
          resolve({
            success: false,
            deviceToken,
            error: `APNs error ${statusCode}: ${responseData}`,
          });
        }
      });

      req.on("error", (err: Error) => {
        client.close();
        resolve({
          success: false,
          deviceToken,
          error: `Request error: ${err.message}`,
        });
      });

      req.write(body);
      req.end();
    });
  }

  async sendToAll(
    payload: NotificationPayload
  ): Promise<{ total: number; successful: number; results: SendResult[] }> {
    const tokens = Array.from(this.devices.keys());
    if (tokens.length === 0) {
      return { total: 0, successful: 0, results: [] };
    }

    const results = await Promise.all(
      tokens.map((token) => this.send(token, payload))
    );
    const successful = results.filter((r) => r.success).length;

    return { total: tokens.length, successful, results };
  }

  async sendMessageNotification(
    title: string,
    message: string
  ): Promise<void> {
    await this.sendToAll({
      title,
      body: message,
      category: "OPENCLAW_MESSAGE",
      data: { type: "start_conversation" },
    });
  }

  // ---------------------------------------------------------------------------
  // Device Persistence
  // ---------------------------------------------------------------------------

  private saveDevices(): void {
    try {
      const data = Array.from(this.devices.values()).map((d) => ({
        ...d,
        registeredAt: d.registeredAt.toISOString(),
        lastSeenAt: d.lastSeenAt.toISOString(),
      }));
      fs.writeFileSync(this.deviceStorePath, JSON.stringify(data, null, 2));
    } catch (err) {
      console.error("[ApnsNotifier] Failed to save devices:", err);
    }
  }

  private loadDevices(): void {
    try {
      if (!fs.existsSync(this.deviceStorePath)) return;
      const raw = fs.readFileSync(this.deviceStorePath, "utf8");
      const data = JSON.parse(raw) as Array<Record<string, unknown>>;
      for (const d of data) {
        this.devices.set(d.token as string, {
          token: d.token as string,
          deviceName: d.deviceName as string | undefined,
          deviceModel: d.deviceModel as string | undefined,
          osVersion: d.osVersion as string | undefined,
          appVersion: d.appVersion as string | undefined,
          registeredAt: new Date(d.registeredAt as string),
          lastSeenAt: new Date(d.lastSeenAt as string),
        });
      }
    } catch (err) {
      console.error("[ApnsNotifier] Failed to load devices:", err);
    }
  }

  // ---------------------------------------------------------------------------
  // JWT Auth
  // ---------------------------------------------------------------------------

  private getAuthToken(): string {
    const now = Math.floor(Date.now() / 1000);

    if (this.cachedToken && now < this.tokenExpiry - 600) {
      return this.cachedToken;
    }

    const privateKey = fs.readFileSync(this.keyPath, "utf8");
    const header = { alg: "ES256", kid: this.keyId };
    const payload = { iss: this.teamId, iat: now };

    const encodedHeader = Buffer.from(JSON.stringify(header)).toString(
      "base64url"
    );
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString(
      "base64url"
    );

    const signatureInput = `${encodedHeader}.${encodedPayload}`;
    const sign = crypto.createSign("SHA256");
    sign.update(signatureInput);
    const signature = sign.sign(privateKey);

    const rawSignature = this.derToRaw(signature);
    const encodedSignature = rawSignature.toString("base64url");

    this.cachedToken = `${signatureInput}.${encodedSignature}`;
    this.tokenExpiry = now + 3600;

    return this.cachedToken;
  }

  private derToRaw(derSignature: Buffer): Buffer {
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

    if (r.length > 32) r = r.subarray(r.length - 32);
    if (s.length > 32) s = s.subarray(s.length - 32);

    const rawSignature = Buffer.alloc(64);
    r.copy(rawSignature, 32 - r.length);
    s.copy(rawSignature, 64 - s.length);

    return rawSignature;
  }
}
