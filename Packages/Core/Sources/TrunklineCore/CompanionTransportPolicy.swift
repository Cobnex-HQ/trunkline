import Foundation

/// Desktop video, audio and input belong exclusively to Sunshine/Moonlight.
/// Legacy wire cases remain decodable so old clients can be rejected explicitly.
public enum CompanionTransportPolicy {
    public static func allows(_ message: WireMessage) -> Bool {
        switch message {
        case .startStream, .stopStream, .requestKeyframe, .setAudioEnabled,
             .video, .audio, .pointer, .scroll, .text, .key: return false
        default: return true
        }
    }
}
