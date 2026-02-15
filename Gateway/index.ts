/**
 * iOS Push Notifications Plugin for OpenClaw Gateway
 *
 * This plugin provides the send_ios_notification tool for sending
 * push notifications to iOS devices via APNs.
 *
 * Installation on DGX Spark:
 *   1. Copy this folder to ~/.openclaw/extensions/ios-push-notifications/
 *   2. Compile TypeScript: npx tsc (or use the pre-compiled JS files)
 *   3. Configure in ~/.openclaw/openclaw.json
 *   4. Restart gateway: openclaw gateway restart
 *
 * Configuration in openclaw.json:
 *   "plugins": {
 *     "load": {
 *       "paths": ["/home/antares/.openclaw/extensions/ios-push-notifications"]
 *     },
 *     "entries": {
 *       "ios-push-notifications": {
 *         "enabled": true,
 *         "config": {
 *           "apns": {
 *             "keyPath": "/path/to/AuthKey_XXXXXX.p8",
 *             "keyId": "YOUR_KEY_ID",
 *             "teamId": "YOUR_TEAM_ID",
 *             "bundleId": "carc.ai.OpenClaw",
 *             "sandbox": true
 *           }
 *         }
 *       }
 *     }
 *   }
 */

import { ApnsNotifier } from "./apns-notifier.js";

// ---------------------------------------------------------------------------
// Inline type definitions for OpenClaw Plugin SDK
// These mirror the types from "openclaw/plugin-sdk" so the plugin compiles
// standalone without requiring the SDK as a build dependency.
// ---------------------------------------------------------------------------

interface ToolParameter {
  type: string;
  description?: string;
  properties?: Record<string, ToolParameter>;
  required?: string[];
}

interface ToolDefinition {
  name: string;
  description: string;
  parameters: ToolParameter;
  execute: (params: Record<string, unknown>) => Promise<unknown>;
}

interface OpenClawPluginApi {
  pluginConfig?: Record<string, unknown>;
  registerTool(tool: ToolDefinition): void;
}

interface OpenClawPlugin {
  id: string;
  name: string;
  description: string;
  configSchema: Record<string, unknown>;
  register(api: OpenClawPluginApi): void;
}

// ---------------------------------------------------------------------------

interface ApnsPluginConfig {
  keyPath: string;
  keyId: string;
  teamId: string;
  bundleId: string;
  sandbox?: boolean;
}

interface PluginConfig {
  apns?: ApnsPluginConfig;
}

const plugin: OpenClawPlugin = {
  id: "ios-push-notifications",
  name: "iOS Push Notifications",
  description: "Send push notifications to iOS devices via APNs",
  configSchema: {},

  register(api: OpenClawPluginApi) {
    const pluginConfig = api.pluginConfig as PluginConfig | undefined;

    console.log(
      "[ios-push-notifications] Initializing with config:",
      pluginConfig?.apns ? "APNs configured" : "no APNs config"
    );

    if (!pluginConfig?.apns) {
      console.warn(
        "[ios-push-notifications] No APNs configuration found — plugin disabled"
      );
      return;
    }

    const notifier = new ApnsNotifier({
      keyPath: pluginConfig.apns.keyPath,
      keyId: pluginConfig.apns.keyId,
      teamId: pluginConfig.apns.teamId,
      bundleId: pluginConfig.apns.bundleId,
      sandbox: pluginConfig.apns.sandbox ?? true,
    });

    api.registerTool({
      name: "send_ios_notification",
      description:
        "Send a push notification to an iOS device. Use this to alert the user on their iPhone.",
      parameters: {
        type: "object",
        properties: {
          deviceToken: {
            type: "string",
            description:
              "The APNs device token for the target iOS device (64 character hex string)",
          },
          title: {
            type: "string",
            description: "The notification title (shown prominently)",
          },
          body: {
            type: "string",
            description: "The notification body text (shown below the title)",
          },
          badge: {
            type: "number",
            description:
              "Optional badge number to display on the app icon",
          },
          sound: {
            type: "string",
            description: "Optional sound name (default: 'default')",
          },
        },
        required: ["deviceToken", "title", "body"],
      },
      execute: async (params: Record<string, unknown>) => {
        const deviceToken = params.deviceToken as string;
        const title = params.title as string;
        const body = params.body as string;
        const badge = params.badge as number | undefined;
        const sound = (params.sound as string) ?? "default";

        console.log(
          `[ios-push-notifications] Sending to ${deviceToken.substring(0, 8)}...`
        );

        const result = await notifier.send(deviceToken, {
          title,
          body,
          badge,
          sound,
        });

        if (result.success) {
          return { success: true, message: "Notification sent successfully" };
        } else {
          return { success: false, error: result.error };
        }
      },
    });

    console.log(
      "[ios-push-notifications] Plugin registered: send_ios_notification tool available"
    );
  },
};

export default plugin;
