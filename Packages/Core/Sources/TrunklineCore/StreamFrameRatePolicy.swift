import Foundation

public enum StreamFrameRatePolicy {
    /// The dashboard can report a temporarily reduced refresh rate before the stream becomes full screen.
    /// Keep the selected stream rate so interactive sessions are not negotiated down to 30 FPS.
    public static func targetFramesPerSecond(for profile: StreamProfile, preStreamDisplayMaximum: Int) -> Int {
        profile.framesPerSecond
    }
}
