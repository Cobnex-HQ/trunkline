# Device-sized desktops

Status: feasibility checked, not enabled. Mirror Mac retains the selected monitor’s exact aspect ratio.

Checked with Xcode 27.2 and the macOS 27.2 SDK. Public CoreGraphics and ScreenCaptureKit headers expose physical display modes and capture sizing. They do not expose a virtual-display creation API. This is a finding about the SDK checked, not a claim that no driver or private implementation could provide it.

[CGDisplaySetDisplayMode](https://developer.apple.com/documentation/coregraphics/cgdisplaysetdisplaymode(_:_:_:)) selects an existing monitor mode. It changes the local screen too. [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration) controls capture output dimensions, scaling and cropping. Those settings do not create a differently shaped Mac workspace.

Run the read-only probe with the target device’s current usable width and height:

```sh
swift Scripts/check-desktop-sizes.swift 1488 2266
swift Scripts/check-desktop-sizes.swift 2266 1488
```

The development Mac advertised 60 modes. None matched either example ratio within 0.5%. Device models, window sizes and attached monitors differ, so rerun with the actual dimensions. The probe makes no display changes.

An independent device-sized desktop needs a separately evaluated virtual-display provider. Before enabling one, verify its public distribution route, license, signing, rotation behavior, pointer coordinates, monitor hot-plug and restoration after a crash. Preserve Mirror Mac as the default and keep all workspace changes opt-in. A capture resize or forced physical resolution change does not satisfy this feature.
