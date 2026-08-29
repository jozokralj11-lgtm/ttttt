# TouchLooper v0.1

TouchLooper is a system-wide touch macro recorder for jailbroken iOS 15/16. It records UIKit touch events to a timestamped JSONL file and replays them through ZXTouch.

## Target

- iPhone 7 / 8 / X and other arm64 checkm8 devices
- iOS 15 or iOS 16
- palera1n rootless first
- Dopamine/rootless should also be viable where ZXTouch Rootless works
- Theos + ElleKit/Substrate-compatible injection

## What v0.1 does

- Floating SpringBoard panel
- Record taps
- Record swipes and drags
- Record multi-touch (up to 19 fingers)
- Keyboard taps are captured as ordinary touch events when the keyboard process receives UIKit events
- Playback 0.1x to 10x speed
- Repeat N times
- Delay between loops
- STOP flag interrupts playback
- Saves the current macro as JSONL
- Normalized coordinates allow the same macro to scale to another screen size

## Important dependency

Install the maintained **ZXTouch Rootless** package first. TouchLooper uses ZXTouch's local service and Python module only for generating the synthetic replay touches. The recorder itself is TouchLooper.

ZXTouch Rootless currently documents iOS 15-16 rootless support and exposes `touch()`, `get_screen_size()`, recording, playback and text-related APIs.

Also install `python3` from your jailbreak bootstrap/package manager.

## Build on a Mac with Theos

```bash
export THEOS=~/theos
cd TouchLooper-v0.1
make clean package FINALPACKAGE=1
```

The `.deb` will appear under `packages/`.

## Install

Copy the generated `.deb` to the phone, then install it through Sileo/Filza or SSH. The package resprings SpringBoard after installation.

## Usage

1. Tap `REC`.
2. After about 0.35 seconds the status changes to Recording.
3. Perform your taps, swipes and keyboard taps.
4. Tap `STOP`.
5. Tap `PLAY`.
6. Enter repeat count, playback speed and loop delay.
7. Tap Play.

`SAVE` copies the latest recording to:

`/var/mobile/Library/TouchLooper/macros/<name>.jsonl`

The current recording is:

`/var/mobile/Library/TouchLooper/current.jsonl`

## Caveats / things to test first

This is a first source build, not a device-tested release. Private jailbreak environments differ, so test on a spare device first.

The two biggest compatibility checks are:

1. Whether your tweak injector accepts the broad `com.apple.UIKit` filter on your palera1n setup. If not, switch to an explicit process/bundle filter list.
2. Whether your ZXTouch build interprets touch coordinates exactly as `get_screen_size()` reports. The helper deliberately uses normalized coordinates and scales them to ZXTouch's reported display size.

Apple's keyboard may run in a separate UIKit process. Because this package requests UIKit-wide injection, its keyboard touches should be recorded; third-party keyboard behavior can vary.

## Next version

The next logical additions are a macro picker, rename/delete UI, visual timeline editor, keyboard semantic-text capture, orientation transforms, and a hardware-button gesture to show the panel again after hiding it.
