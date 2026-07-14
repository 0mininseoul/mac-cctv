# Mac CCTV

**Step away. We'll watch your seat.**

Mac CCTV turns your MacBook into a personal anti-theft camera. One keyboard shortcut
arms the built-in webcam; you watch your café table live from your iPhone, every
second backs up to *your own* iCloud, and it all auto-deletes after 7 days. No
sign-up, no server, no data collected — the whole thing runs on CloudKit and WebRTC
with zero backend.

- 📹 **Arm with one shortcut** — `⌃⌘C` starts recording from the menu bar; no windows, no fuss.
- 📱 **Live from your iPhone** — low-latency WebRTC stream, with a delayed-playback fallback over iCloud.
- 🔔 **Smart alerts** — natural-language push when someone touches, moves, unplugs, or closes the Mac ("사람이 감지됐어요!").
- 🚨 **Remote siren** — hold to blast a full-screen warning + alarm from the Mac; end the session remotely.
- ☁️ **Your iCloud only** — chunked recording to your private CloudKit database, 7-day auto-retention.

## How it works

Two apps share one Swift package and communicate entirely through the user's private
CloudKit database — there is no custom server.

```
┌──────────────────────────┐        CloudKit (private DB)         ┌──────────────────────────┐
│  MacCCTV  (menu-bar app)  │  ── Session / Chunk / Event / ──►   │  CCTVCompanion  (iOS)     │
│                           │      Signal records                  │                           │
│  • webcam capture         │                                      │  • live view              │
│  • motion/input/power/lid │  ◄── Signal records (siren, end,  ──  │  • recording library      │
│    event detection        │      viewerReady) ──►                │  • push notifications     │
│  • staged auto-siren      │                                      │  • remote siren / end     │
│  • chunked iCloud upload  │  ══ WebRTC media (SDP/ICE over ══►   │                           │
│  • full-screen siren      │      Signal records, non-trickle)    │                           │
└──────────────────────────┘                                      └──────────────────────────┘
```

- **Live video** is WebRTC (peer-to-peer). SDP/ICE are exchanged as CloudKit `Signal`
  records (non-trickle: candidates are baked into the offer/answer to avoid per-candidate
  round-trips). If the realtime path can't connect, iOS falls back to delayed playback of
  the uploaded chunks.
- **Recordings** are ~6-second H.264 MP4 *chunks* written locally, uploaded to CloudKit,
  and cached on-device for instant replay. A startup catch-up re-uploads any chunk that
  was left on disk when a session's upload didn't finish.
- **Alerts / control** ride the same `Signal` channel: the Mac broadcasts its live state
  (escalation countdown, siren on/off, session ended); the phone sends siren / end-session
  / dismiss-escalation commands back.
- **Retention**: a 7-day sweep runs on launch (both platforms) and deletes expired
  sessions and chunks.

## Repository layout

```
apps/
  mac/MacCCTV/          macOS menu-bar app (capture, detection, siren, upload)
  ios/CCTVCompanion/    iOS companion (live view, library, notifications)
Packages/CCTVKit/       shared Swift package — domain models, CloudKit store,
                        WebRTC signaling, chunk upload, retention, detection policy
                        (+ the unit tests: `swift test`)
tests/                  app-target tests (StoreKit, etc.)
script/                 archive/export + build-and-run helpers
web/                    static landing page (deployed to Vercel)
docs/                   PRD, handoff, App Store submission checklist, design specs
project.yml             XcodeGen project definition (source of truth)
```

## Requirements

- Xcode 15+ (String Catalogs), macOS 14+ / iOS 17+ deployment targets
- XcodeGen (`brew install xcodegen`) — the `.xcodeproj` is generated from `project.yml`,
  which is the source of truth
- An Apple Developer account with iCloud/CloudKit + Push enabled for the two bundle IDs
  (`com.youngminpark.maccctv.mac`, `com.youngminpark.maccctv.ios`) sharing the
  `iCloud.com.youngminpark.maccctv` container and `group.com.youngminpark.maccctv` app group

## Build & run

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Run the shared-package unit tests
cd Packages/CCTVKit && swift test && cd -

# 3. Build either target
xcodebuild -project MacCCTV.xcodeproj -scheme MacCCTV       -destination 'platform=macOS' build
xcodebuild -project MacCCTV.xcodeproj -scheme CCTVCompanion -destination 'generic/platform=iOS Simulator' build

# 4. Open in Xcode to run on device
open MacCCTV.xcodeproj
```

Then, on the Mac app: grant camera permission, press **`⌃⌘C`** to arm (the menu-bar
icon changes — no window appears), and open the iOS app to watch live.

### TestFlight

`script/archive_and_export.sh [mac|ios|all]` archives and exports signed `.pkg`/`.ipa`,
which are uploaded with `xcrun altool --upload-app`. See
[`docs/app-store/submission-checklist.md`](docs/app-store/submission-checklist.md) for
the full pipeline and per-build history.

> **CloudKit note:** push notification subscriptions use a per-type predicate, which
> requires the `Event.type` field to be marked **Queryable** and deployed to the
> *production* CloudKit schema. If it isn't, the app self-heals to a match-all
> fallback subscription (generic copy) so alerts still arrive. See the build-12 notes
> in the submission checklist.

## Privacy

No account, no analytics, no third-party server. Video lives only in the user's own
private CloudKit database and is deleted after 7 days. The camera-usage strings in each
app's `Info.plist` explain that the iOS app never captures — it only receives the Mac's
stream (the WebRTC library links camera APIs the app never enables).

## Docs

- [`docs/PRD.md`](docs/PRD.md) — product requirements (Korean)
- [`docs/HANDOFF.md`](docs/HANDOFF.md) — coding-session handoff & human-only tasks
- [`docs/app-store/submission-checklist.md`](docs/app-store/submission-checklist.md) — release pipeline + build log
- [`docs/superpowers/specs/`](docs/superpowers/specs/) — design specs for major changes
