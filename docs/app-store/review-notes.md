# App Review 노트 — App Store Connect "App Review Information > Notes"에 붙여넣을 내용

두 앱(**CCTV for Mac** / macOS, **CCTV for Mac 컴패니언** / iOS)은 한 쌍의 컴패니언 앱이다. 각 앱 제출 시 아래 내용을 리뷰어가 바로 이해할 수 있도록 Notes 필드에 넣는다. 영어 심사팀이 배정될 가능성이 높으므로 **영문 버전을 우선 사용**하고, 필요 시 한글 버전을 참고용으로 덧붙인다.

---

## 영문 (App Store Connect에 붙여넣기용)

```
WHAT THIS APP DOES
CCTV for Mac lets a user monitor their OWN unattended laptop while they briefly
step away from it (e.g. a café, library, or coworking space). The user starts
monitoring on their Mac with a keyboard shortcut before leaving their seat, and
watches their own desk in real time from their own iPhone. This is a personal
anti-theft / peace-of-mind tool, not a covert surveillance or spyware product.
There is no scenario in which this app records or transmits video of anyone
other than the person who owns and operates both devices.

CAMERA / WEBCAM LED
The webcam's hardware indicator light cannot be and is not disabled by this
app — we intentionally do not attempt this, both because it is a hardware-level
safeguard on Apple silicon Macs and because a visibly-active camera is part of
the product's theft-deterrent value proposition. There is no hidden recording:
whenever the camera captures video, the green LED is on, exactly as it is for
FaceTime or any other camera app.

WHERE VIDEO IS STORED
All video is written directly to the user's own iCloud account via CloudKit
(private database only — never a public database, never a developer-operated
server). We do not operate any backend, we cannot access user video, and there
is no data collection to report in App Privacy (see the "Data Not Collected"
declaration). Video auto-deletes after 7 days.

THE FULL-SCREEN SIREN WARNING
The Mac app has one full-screen UI element: a "This device is being recorded
and tracked" warning banner, shown only when the user (or a conservative
automatic trigger — see below) activates the siren, which also plays an
audible alarm. This is a deterrent shown to a would-be thief, not the device
owner, and is the single exception to the app's normal no-UI, menu-bar-only
behavior. It can be dismissed instantly by the device owner via the same
global keyboard shortcut used to start monitoring.

Automatic siren activation is intentionally conservative: it only fires when
a sustained (3+ second) full-frame camera shift is combined with a corroborating
signal (recent keyboard/trackpad input or a power disconnect), and never
within the first 30 seconds of a session (to avoid false positives from the
user's own packing-up motion). Simple hand-waving in front of the camera or
a bumped table does not trigger it — only a notification is sent in that case.

HOW TO TEST END-TO-END
1. Install "CCTV for Mac" on a Mac and "CCTV for Mac Companion" on an iPhone,
   both signed into the SAME iCloud account (this is required — the two apps
   pair automatically via the shared iCloud account, there is no separate
   login or account creation in this app).
2. On first launch, the Mac app's onboarding requests Camera permission and
   confirms iCloud availability. No other permissions are required.
3. Press Control+Command+C (the default, user-changeable global shortcut) to
   start monitoring — the menu bar icon changes state; no window appears.
4. Open the iPhone app — it connects automatically (same iCloud account) and
   shows a live view within 1-2 seconds (WebRTC peer-to-peer) or, if P2P is
   unavailable on the test network, a short-delay fallback (~15-20s) with a
   "delayed mode" indicator — this is expected, documented behavior (see PRD
   §7, item 2), not a bug.
5. Press Control+Command+C again to stop monitoring.
6. Long-press the siren button on the iPhone's live screen to test the manual
   siren; it should sound and show the full-screen warning on the Mac within
   ~2 seconds, dismissible from the Mac via the same shortcut.

PERMISSIONS REQUESTED
- Camera (NSCameraUsageDescription): core anti-theft monitoring function.
- No microphone, no location, no contacts. Audio recording is intentionally
  excluded from this app entirely (not just unused — the capture pipeline has
  no audio track) due to two-party-consent recording law considerations in
  some jurisdictions.
- Push notifications (iOS): event alerts (motion, lid close, power
  disconnect) delivered via CloudKit's own silent-push mechanism — we do not
  operate a push server.

PRIVATE / UNDOCUMENTED APIs
This build does not use any private or undocumented APIs. An experimental
accelerometer-based motion feature (Apple Silicon IOKit HID sensor) exists
only in a separate, non-App-Store direct-distribution build and is fully
excluded from this target.

NO ADS, NO TRACKING, NO THIRD-PARTY SDKS
The only third-party dependency is stasel/WebRTC (SPM), an open-source media
transport library that sends no data anywhere on its own — it is the
transport for the peer-to-peer video stream described above. There is no
analytics, advertising, or crash-reporting SDK in this app.
```

---

## 한글 (내부 참고용 — 필요 시 함께 첨부)

```
이 앱은 사용자 본인이 자리를 비운 동안 자신의 노트북을 스스로 지켜보는 개인용
도난 방지 도구다. Mac에서 단축키로 감시를 시작하면 같은 iCloud 계정의 iPhone
에서 실시간으로 자기 자리를 볼 수 있다. 타인을 몰래 촬영하는 시나리오는
존재하지 않는다.

웹캠 LED는 하드웨어 제약으로 끌 수 없으며, 끄려고 시도하지도 않는다 — 오히려
"녹화 중임이 보이는 것"이 도난 억제 효과의 일부다. 영상은 개발자 서버를
전혀 거치지 않고 사용자 본인의 iCloud(CloudKit private database)에만
저장되며 7일 후 자동 삭제된다.

Mac 앱의 유일한 전체화면 UI는 사이렌 경고("이 기기는 녹화·추적 중")이며,
도둑에게 보여주기 위한 것으로 소유자 본인이 언제든 같은 단축키로 3초 내
해제할 수 있다. 자동 발동은 보수적 복합 조건(전역 모션 3초 이상 + 입력·전원
신호 동반)에서만 작동해 오탐을 최소화했다.

오디오는 지역별 녹음 동의 법규 이슈로 MVP에서 아예 캡처하지 않는다. 분석·
광고·크래시리포팅 SDK는 전혀 포함되어 있지 않고, 유일한 제3자 라이브러리는
데이터를 어디로도 전송하지 않는 오픈소스 미디어 전송 라이브러리(stasel/
WebRTC)뿐이다.
```

## 제출 전 체크

- [ ] 위 영문 노트를 Mac 앱, iOS 앱 각각의 App Store Connect "App Review Information > Notes"에 붙여넣기
- [ ] 카메라 사용 목적 문구(`NSCameraUsageDescription`, Info.plist)가 위 설명과 톤이 일치하는지 확인 — `docs/app-store/submission-checklist.md`에서 재확인
- [ ] 리뷰어가 실제로 두 기기(또는 Mac + 시뮬레이터)를 같은 Apple ID로 테스트할 수 있는지 — 데모 계정이 아니라 "본인 Apple ID로 테스트"이므로 리뷰어 환경에 따라 추가 설명 요청이 올 수 있음. 그런 경우를 대비해 데모 영상 링크를 함께 제공하는 것을 권장 (App Review Information의 "Notes"에 데모 영상 URL 추가 가능)
