//
//  AudioSessionManager.swift
//  OpenClaw
//
//  Audio session cleanup. The ElevenLabs SDK configures its own session
//  via LiveKit — this only handles deactivation on conversation end.
//

import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
}
