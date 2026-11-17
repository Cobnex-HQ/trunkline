#!/usr/bin/env python3
"""Capture production UI fixtures through XCTest, preserving screenshots in xcresult.

Pass two existing simulator IDs; this script never creates or deletes devices.
Run sequentially: XCTest controls simulator orientation and app lifecycle.
"""
import argparse
import json
import plistlib
from pathlib import Path
import subprocess


def run(command, **kwargs):
    print(" ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone", required=True, help="Existing iPhone simulator UDID")
    parser.add_argument("--ipad", required=True, help="Existing iPad simulator UDID")
    parser.add_argument("--device", nargs="+", choices=["iphone", "ipad"], default=["iphone", "ipad"])
    parser.add_argument("--output", type=Path, default=Path(".build/ui-redesign/after"))
    parser.add_argument("--derived-data", type=Path, default=Path(".build/ui-review-derived"))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--appearance", nargs="+", choices=["light", "dark"], default=["light", "dark"])
    parser.add_argument("--orientation", nargs="+", choices=["portrait", "landscape"], default=["portrait", "landscape"])
    parser.add_argument("--suite", choices=["full", "smoke"], default="full", help="Full secondary-screen coverage or major screens only")
    parser.add_argument("--only-testing", action="append", help="Optional XCTest selector. Repeat to select several tests")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    common = ["xcodebuild", "-project", "Trunkline.xcodeproj", "-scheme", "UIReviewScreenshots",
              "-configuration", "Debug", "-derivedDataPath", args.derived_data,
              "CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO"]
    if not args.skip_build:
        run(common + ["build-for-testing", "-destination", f"platform=iOS Simulator,id={args.iphone}"])
    candidates = sorted((args.derived_data / "Build/Products").glob("UIReviewScreenshots_*.xctestrun"))
    if len(candidates) != 1:
        raise SystemExit(f"Expected one generated UIReviewScreenshots xctestrun, found: {candidates}")
    original_run = candidates[0]
    manifest = []
    failures = []
    for device, udid in [("iphone", args.iphone), ("ipad", args.ipad)]:
        if device not in args.device:
            continue
        for appearance in args.appearance:
            for orientation in args.orientation:
                stem = f"{device}-{appearance}-{orientation}"
                result = args.output / f"{stem}.xcresult"
                if result.exists():
                    raise SystemExit(f"Refusing to overwrite existing test evidence: {result}")
                configuration = plistlib.loads(original_run.read_bytes())
                if "TestConfigurations" in configuration:
                    targets = [target for config in configuration["TestConfigurations"]
                               for target in config.get("TestTargets", [])]
                else:
                    targets = [target for key, target in configuration.items()
                               if not key.startswith("__") and isinstance(target, dict)]
                if not targets:
                    raise SystemExit("Generated xctestrun contains no test targets")
                for target in targets:
                    environment = target.setdefault("EnvironmentVariables", {})
                    environment["TRUNKLINE_CAPTURE_APPEARANCE"] = appearance
                    environment["TRUNKLINE_CAPTURE_ORIENTATION"] = orientation
                # Keep __TESTROOT__ paths valid by storing alongside the generated run file.
                variant_run = original_run.parent / f"capture-{stem}.xctestrun"
                variant_run.write_bytes(plistlib.dumps(configuration))
                command = ["xcodebuild", "test-without-building", "-xctestrun", variant_run,
                           "-destination", f"platform=iOS Simulator,id={udid}",
                           "-parallel-testing-enabled", "NO",
                           "-test-timeouts-enabled", "YES",
                           "-default-test-execution-time-allowance", "360",
                           "-maximum-test-execution-time-allowance", "480",
                           "-resultBundlePath", result]
                if args.only_testing:
                    command += [f"-only-testing:{selector}" for selector in args.only_testing]
                elif args.suite == "smoke":
                    command += ["-only-testing:UIReviewScreenshots/UIReviewScreenshots/testWorkspaceSmoke"]
                else:
                    command += ["-skip-testing:UIReviewScreenshots/UIReviewScreenshots/testWorkspaceSmoke",
                                "-skip-testing:UIReviewScreenshots/UIReviewScreenshots/testDesktopPrimaryAction"]
                passed = True
                try:
                    with (args.output / f"{stem}.log").open("w") as log:
                        run(command, stdout=log, stderr=subprocess.STDOUT)
                except subprocess.CalledProcessError:
                    passed = False
                    failures.append(stem)
                exported = args.output / stem
                if result.exists():
                    # Includes XCTest screenshot attachments and a manifest of their names.
                    run(["xcrun", "xcresulttool", "export", "attachments", "--path", result,
                         "--output-path", exported])
                manifest.append({"device": device, "udid": udid, "appearance": appearance,
                                 "orientation": orientation, "passed": passed,
                                 "result": str(result), "attachments": str(exported)})
                (args.output / "runs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if failures:
        raise SystemExit("Incomplete screenshot runs: " + ", ".join(failures))


if __name__ == "__main__":
    main()
