# Simulator screenshot review

Capture production views with debug-only simulator data using `--ui-review`. The fixture stores no credentials, connects to no host and performs no remote actions. Screenshots are retained as named XCTest attachments.

Run from the repository root after generating the Xcode project:

```sh
python3 Scripts/capture-ui-review.py \
  --iphone EXISTING_IPHONE_UDID --ipad EXISTING_IPAD_UDID
```

The default run captures both devices in portrait and landscape, with light and dark appearance. Tests wait for the review view, check the effective theme and verify screenshot orientation. Results, attachments and logs are saved under `.build/ui-redesign/after`. Existing results are never overwritten.

For a shorter review, run the full suite on iPhone portrait/light and iPad landscape/dark, then use `--suite smoke` for the remaining combinations. Smoke captures eight main views. Select variants with `--device`, `--appearance` and `--orientation`. Use `--skip-build` only when the test build is current.

Repeat `--only-testing UIReviewScreenshots/UIReviewScreenshots/testFilesScreens` with other test names to select specific cases. Tests have a six-minute default limit and an eight-minute maximum. Run device automation sequentially.

| Area | Screens/state coverage in harness | Limits |
| --- | --- | --- |
| Connection | Initial setup, expanded pairing link, two saved Macs/selected Mac/passcode entry, connecting, connection menu, forget confirmation | No passcodes or tickets are stored. Biometric unlock and real network failures require a physical integration review |
| Scanner | Actual unsupported-device screen | Simulator has no camera scan/video coverage |
| Help | Top and lower sections | External privacy/setup/issues pages are links, not app screens |
| Desktop setup | Summary, displays menu, saved Mac menu, switch/add confirmation, options, stream settings, disconnect confirmation | No successful pairing or real host connection |
| Desktop viewer | Production toolbar, overflow, shortcuts, gesture help, controls overlay, text sheet via simulator-only surface hook | Black placeholder explicitly replaces stream. No video, input injection, stream statistics or real display switching claimed |
| Terminal | Session list, new-session menu, empty/loading/creating, running detail, keyboard, options, paste, rename, end confirmation, ended detail | Synthetic output. No shell starts or commands execute |
| Controls | Top/lower sections, app launcher, app action menu/quit confirmation, power menu/lock confirmation, clipboard | No remote actions submitted. Real permission failures/host disconnection need integration review |
| Files | Listing, folder, row actions, rename, trash confirmation, new folder, sorting, upload document picker, transfer progress, downloaded/share sheet, empty and old-host state | No real upload/download/delete. A local synthetic text file feeds native share sheet |
| File move/preview | Not present in current app | Files exposes Rename/Move to Trash, not a move-destination picker or Quick Look preview. Do not label the share sheet a file preview |
| macOS | `MacClientTests` captures five host pages in light and dark appearance | Native window capture requires an available desktop. OS permission prompts are not covered |

Screenshots support visual review. They are not pixel-diff assertions or a replacement for functional and physical-device tests.

## Rotation and keyboard regressions

Fresh screenshots do not test navigation transitions. Run these cases on both devices after changing workspace layout:

```sh
python3 Scripts/capture-ui-review.py \
  --iphone EXISTING_IPHONE_UDID --ipad EXISTING_IPAD_UDID \
  --appearance dark --orientation portrait \
  --output .build/layout-check \
  --only-testing UIReviewScreenshots/UIReviewScreenshots/testConnectedTerminalRotation \
  --only-testing UIReviewScreenshots/UIReviewScreenshots/testPasscodeKeyboardRotation \
  --only-testing UIReviewScreenshots/UIReviewScreenshots/testControlsRotation
```

Each case rotates portrait → landscape → portrait without relaunching. Terminal opens through the workspace and session list. It checks that the session uses the available width and stays above the keyboard accessory. Connection checks that a synthetic passcode remains visible and survives rotation and reveal/hide. Controls checks equal card sizes and that the sidebar does not cover the first action.

The viewer case, `testDesktopViewerScreens`, also checks that Send text opens the keyboard and fits its editor between the navigation bar and keyboard. Run it in landscape on both devices.

Also check a narrow iPad window and a hardware or floating keyboard on a device. Screenshots with a placeholder desktop cannot validate a live stream or pointer alignment.

## Capture details

- The script sets theme and orientation in each generated `.xctestrun`. Captures use the full device display and account for EXIF orientation.
- The synthetic terminal uses a steady cursor to reduce idle waits. Production cursor behavior is unchanged.
- Native menu actions use exact labels across Button and PopUpButton accessibility types, with bounded menu scrolling. The grouped shortcut parent menu is captured. Individual key submenus are not captured.
- The system document picker gets 30 seconds to expose its Cancel control. An empty popover fails readiness.
- Mac window capture is skipped when the OS cannot capture the desktop, even if permission is already granted.
