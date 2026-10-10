# Roundtable

Live captions for group conversations, for people who are deaf or hard of hearing.
It runs entirely on the iPhone: no account, no API keys, no server.

- **Shows who is talking and where.** The iPhone's built-in stereo microphone lets Roundtable
  estimate where each voice comes from. Every caption is colored by seat (far left … far right)
  and you can give the seats names ("Mom", "Sam").
- **Captions are on-device.** It uses `SpeechAnalyzer` on iOS 26+ and on-device
  `SFSpeechRecognizer` on iOS 17–25. Audio never leaves the phone.
- **Phones at the table can team up without the internet.** Phones with the same room code
  share their captions over MultipeerConnectivity (peer-to-peer Wi‑Fi and Bluetooth), so a
  long table can have a phone at each end.
- Large adjustable text, a vibration when someone in a different seat starts talking, transcript
  sharing, and the screen stays awake while captioning.

## Build and run

1. Open `Roundtable.xcodeproj` in **Xcode 16 or later** (Xcode 26 recommended: that's what
   enables the `SpeechAnalyzer` engine; older Xcode versions build with the `SFSpeechRecognizer` engine only).
2. Select the **Roundtable** target › *Signing & Capabilities*, choose your Team, and change the
   bundle identifier (`com.vdrol.Roundtable`) if Xcode says it's taken.
3. Run on a **real iPhone** (iOS 17+). The Simulator has no stereo mic, and speech recognition
   in it is unreliable.
4. When asked, allow Microphone, Speech Recognition, and Local Network access.

The first time you run it, iOS may download the on-device speech model, which needs internet.
After that everything works offline. If you see "On-device speech recognition isn't available",
turn on Settings › General › Keyboard › Enable Dictation and let the model download.

If the project won't open on your Xcode version, regenerate it with
[XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen`.

## Using it

1. Lay the phone flat in the middle of the table, **top pointing away from you**.
2. Tap **Start captions**. The dial shows the live speaker direction, and each caption gets
   that seat's color.
3. If left and right are swapped, go to Settings › *Swap left and right*. If everyone shows as
   the middle seat, raise *Direction sensitivity*.
4. To add more phones: install the app on them, set the same **room code** in Settings, and
   their captions appear in everyone's feed, marked with a 📡 icon and the phone's name.

## How it works

```
Built-in mic (stereo polar pattern)
        │  AVAudioEngine tap, 4096-frame buffers
        ├──► DirectionEstimator ── L/R level difference, noise-gated, smoothed
        │                          → live dial + average direction per caption
        └──► mono downmix ──► CaptionTranscriber
                               ├─ ModernSpeechTranscriber  (SpeechAnalyzer, iOS 26+)
                               └─ LegacySpeechTranscriber  (SFSpeechRecognizer, on-device)
                                        │ partial / final segments
                                        ▼
                                  CaptionStore ◄──► PeerSession (MultipeerConnectivity)
                                        │
                                     SwiftUI
```

| Folder | What's inside |
| --- | --- |
| `Roundtable/Audio` | Stereo session setup, capture engine, direction estimation |
| `Roundtable/Speech` | The two on-device speech engines behind one `CaptionTranscriber` protocol |
| `Roundtable/Networking` | `PeerSession`: discovery by room code and caption exchange |
| `Roundtable/Store` | `CaptionStore` (app state), `LiveMeter` (fast-updating dial state) |
| `Roundtable/Views` | SwiftUI screens |

**Direction:** On iPhone XS and later, `AVAudioSession` can record a stereo image from the
built-in mics (`setPreferredPolarPattern(.stereo)`). Roundtable compares the loudness of the
left and right channels, ignores buffers that are below an adaptive noise floor, and averages
the direction over each caption, weighted by loudness. It gives roughly the seat (five zones),
not exact angles. It can't tell front from back, so people directly across and directly behind
look the same. That's why the phone goes in the middle of the table, and why a second phone helps.

**Segments:** `SpeechAnalyzer` finalizes phrases at natural pauses. `SFSpeechRecognizer` keeps
one growing transcript, so the legacy engine commits a segment after a 1.3 s pause, or after
220 characters, and starts a new request.

## Limitations and ideas

- Direction is only stereo left/right. Two people sitting in the same seat zone get the same color.
- No background captioning: it stops when the app leaves the screen.
- Ideas for later: speaker identification by voice, Apple Watch caption mirroring,
  Live Activity captions on the Lock Screen, and a translated caption view with the `Translation` framework.
