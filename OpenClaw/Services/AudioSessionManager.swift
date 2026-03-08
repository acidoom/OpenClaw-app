//
//  AudioSessionManager.swift
//  OpenClaw
//
//  Configures AVAudioSession for voice conversations
//

import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() {}
    
    func configureForVoiceChat() throws {
        let session = AVAudioSession.sharedInstance()
        
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers]
        )
        
        try session.setActive(true)
        
        // Force output to speaker
        try session.overrideOutputAudioPort(.speaker)
    }
    
    func configureForAudiobookPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        
        // Try configurations from most to least featured
        let configs: [(AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.spokenAudio, [.allowAirPlay, .allowBluetoothA2DP]),
            (.default, [.allowBluetoothA2DP]),
            (.default, []),
        ]
        
        var configured = false
        for (mode, options) in configs {
            do {
                try session.setCategory(.playback, mode: mode, options: options)
                print("[AudioSession] Configured: mode=\(mode.rawValue), options=\(options.rawValue)")
                configured = true
                break
            } catch {
                print("[AudioSession] Failed mode=\(mode.rawValue) options=\(options.rawValue): \(error)")
            }
        }
        
        if !configured {
            // Last resort — bare minimum
            print("[AudioSession] All configs failed, trying bare .playback category")
            try session.setCategory(.playback)
        }
        
        try session.setActive(true)
    }
    
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
}
