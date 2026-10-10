# Roundtable

Live captions for group conversations, for people who are deaf or hard of hearing.
It runs entirely on the device, on **iPhone, iPad and Mac**: no account, no API keys, no server.

- **Shows who is talking and where.** With any microphone that records two or more channels,
  Roundtable estimates where each voice comes from. Every caption is colored by seat
  (far left … far right) and you can give the seats names ("Mom", "Sam").
- **Captions are on-device.** It uses `SpeechAnalyzer` on iOS/macOS 26+ and on-device
  `SFSpeechRecognizer` on iOS 17–25 / macOS 14–15. Audio never leaves the device.
- **Devices at the table can team up without the internet.** iPhones, iPads and Macs with the
  same room code share their captions over MultipeerConnectivity (peer-to-peer Wi‑Fi and
  Bluetooth). For example, a Mac at one end of the table and an iPhone at the other.
- Large adjustable text, a vibration (iPhone) or trackpad tap (Mac) when someone in a different
  seat starts talking, transcript sharing, and the screen stays awake while captioning.

## Which devices can detect direction?

Direction compares two microphone channels, so it works on any device as long as its
**input has 2 or more channels**. Choose the microphone in **Settings › Microphone**, which shows
each input's channel count.

| Device | Built-in mic | With an external stereo mic |
| --- | --- | --- |
| iPhone XS and later | ✅ stereo | ✅ |
| iPad | ✅ on models whose mics support stereo (checked when you start) | ✅ USB‑C / Lightning |
| Mac | ⚠️ most MacBook/iMac built-in mics are delivered to apps as **mono**, which gives captions but no direction | ✅ any USB stereo mic or audio interface |

On a Mac, plug in a stereo USB microphone (or an audio interface with two mics) and select it.
If the interface has more than two inputs, choose which ones are left and right under
*Left channel* / *Right channel*.

## Build and run

1. Open `Roundtable.xcodeproj` in **Xcode 16 or later** (Xcode 26 recommended: that's what
   enables the `SpeechAnalyzer` engine).
2. Select the **Roundtable** target › *Signing & Capabilities*, choose your Team, and change the
   bundle identifier (`com.vdrol.Roundtable`) if Xcode says it's taken.
3. Pick where to run it, in the device menu at the top of Xcode:
   - **My Mac:** runs as a native Mac app. Nothing else is needed.
   - **Your iPhone or iPad:** connect it and turn on Developer Mode.
4. Allow Microphone, Speech Recognition, and Local Network access when asked.

The first time you run it, the on-device speech model may need to download, which requires
internet. After that everything works offline. If you see "On-device speech recognition isn't
available", turn on Dictation (iPhone: Settings › General › Keyboard; Mac: System Settings ›
Keyboard) and let the model download.

If the project won't open on your Xcode version, regenerate it with
[XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen`.

## Using it

1. Put the device, or the stereo microphone, in the middle of the table with its left side on
   your left. An iPhone lies flat, top pointing away from you.
2. Start captions. The dial shows the live speaker direction, and each caption gets that seat's color.
3. If left and right are swapped, go to Settings › *Swap left and right*. If everyone shows as
   the middle seat, raise *Direction sensitivity*.
4. To add more devices: run Roundtable on them and set the same **room code**. Their captions
   appear in everyone's feed, marked with a 📡 icon and the device's name.

## How it works

```
Microphone (any channel count; choose it in Settings)
        │  AVAudioEngine tap, 4096-frame buffers
        ├──► DirectionEstimator ── chosen L/R channel pair, level difference,
        │                          noise-gated, smoothed → live dial + per-caption direction
        └──► mono downmix ──► CaptionTranscriber
                               ├─ ModernSpeechTranscriber  (SpeechAnalyzer, iOS/macOS 26+)
                               └─ LegacySpeechTranscriber  (SFSpeechRecognizer, on-device)
                                        │ partial / final segments
                                        ▼
                                  CaptionStore ◄──► PeerSession (MultipeerConnectivity)
                                        │
                                     SwiftUI (iOS + macOS)
```

| Folder | What's inside |
| --- | --- |
| `Roundtable/App` | App entry point and `Platform` (the iOS/macOS differences) |
| `Roundtable/Audio` | Input selection (`AVAudioSession` on iOS, Core Audio on macOS), capture, direction |
| `Roundtable/Speech` | The two on-device speech engines behind one `CaptionTranscriber` protocol |
| `Roundtable/Networking` | `PeerSession`: discovery by room code and caption exchange |
| `Roundtable/Store` | `CaptionStore` (app state), `LiveMeter` (fast-updating dial state) |
| `Roundtable/Views` | SwiftUI screens shared by both platforms |

**Direction:** on iPhone, the built-in mic is switched to its stereo polar pattern. On every
device, external inputs are opened with all their channels. Roundtable compares the loudness
of the left and right channels, ignores buffers below an adaptive noise floor, and averages
the direction over each caption, weighted by loudness. It gives roughly the seat (five zones),
not exact angles, and it can't tell front from back.

**Segments:** `SpeechAnalyzer` finalizes phrases at natural pauses. `SFSpeechRecognizer` keeps
one growing transcript, so the legacy engine commits a segment after a 1.3 s pause, or after
220 characters, and starts a new request.

## Limitations and ideas

- Direction needs a 2+ channel input. A single mono mic can't tell left from right.
- On iPhone/iPad, captioning stops when the app leaves the screen. The Mac app keeps going in the background.
- Ideas for later: estimate direction across devices from which one hears the speaker loudest
  (this would make mono Macs useful too), speaker identification by voice, and translated captions
  with the `Translation` framework.
