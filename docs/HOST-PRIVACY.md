# Host privacy mode

Status: not enabled. A capture-exclusion experiment is ready, but its macOS Screen Recording approval is pending.

The bundled Mac engine captures a physical display with `AVCaptureScreenInput` in `src/platform/macos/av_video.m`. A black window placed over that display would also enter the stream. Adding a curtain alone would hide the desktop from both people.

ScreenCaptureKit can exclude a window from display capture. The experiment checks that property before replacing any capture backend:

```sh
sh Scripts/check-privacy-capture.sh
```

This builds and opens **Trunkline Privacy Check**, a separate local test app. If macOS asks, approve Screen Recording for that app, then quit and reopen it. Existing Trunkline permissions are untouched. The probe creates a small green window covered by a black window. It checks whether unfiltered capture is black and filtered capture is green. Images stay in memory. Only status and a message are saved to `.build/privacy-capture/result.json`.

Compilation passed on macOS 27.2.1 with Xcode 27.2. The current runtime result is `permission-required`, not a passed capture test. The probe is excluded from shipping app targets.

After the probe passes, implementation still needs:

1. A filtered live-capture backend with frame delivery and cancellation tests. Keep existing capture available until the replacement passes streaming checks.
2. A host capability tied to the current stream. Show a curtain only after filtered capture is acknowledged. Remove it on shutdown and stop streaming on unsafe capture failure.
3. A local escape that works without the remote device. Verify it with physical input, not only injected events.
4. Coverage for all attached displays, monitor changes, Spaces, full-screen apps, sleep, connection loss and crashes.

A window overlay is not a macOS lock screen. Do not advertise physical-screen privacy until these checks pass. Brightness changes and video cropping do not satisfy this feature.
