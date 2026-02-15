//
//  Log.swift
//  OpenClaw
//
//  Lightweight logging with level control. Uses os.Logger in release builds.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.openclaw.voice"
    private static let logger = Logger(subsystem: subsystem, category: "OpenClaw")

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
