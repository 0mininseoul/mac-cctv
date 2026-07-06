# M9 제출 체크리스트 — App Store Connect

이 문서는 구현 계획 M9("배포 준비")의 산출물을 실제 제출까지 연결하는 체크리스트다. 항목마다 **완료(자동화 가능)** 와 **사람이 직접 해야 함**을 구분했다 — 후자는 App Store Connect 웹 UI·Apple ID 인증·실제 결제/계약 동의가 필요해 Claude Code가 대신할 수 없는 항목이다 (`docs/HANDOFF.md` "사람이 직접 해야 하는 일" 참고).

## 1. 앱 아이콘 / 스크린샷

- [x] Mac + iOS 앱 아이콘 생성·적용 (`apps/mac/MacCCTV/Assets.xcassets`, `apps/ios/CCTVCompanion/Assets.xcassets`) — 두 타겟 빌드 검증 완료
- [x] Mac 스크린샷 2장 (대기 팝오버, 온보딩 1/3단계) — `store-assets/screenshots/mac/`, App Store 제출용으로 사용 가능
- [ ] iOS 스크린샷 — `store-assets/screenshots/ios/`에 1장 있으나 시뮬레이터 iCloud 미로그인으로 인증 에러가 노출된 상태라 **제출용 아님** (한계는 `SCREENSHOTS.md` 참고)
- [ ] **사람 작업**: Mac "감시 중" 팝오버 + iOS 라이브 화면 스크린샷 — 실제 카메라를 켜고 iCloud 업로드가 발생하는 상태라 자동화하지 않음. 같은 세션에서 함께 찍으면 5분 내 가능
- [ ] **사람 작업**: Mac 온보딩 2/3단계 스크린샷 — 카메라 권한을 실제로 허용해야 진행되는 시스템 다이얼로그라 자동화하지 않음
- [ ] **사람 작업**: 영문 로케일 스크린샷 (필요 시 — 현재는 시스템 언어인 한국어로만 캡처됨)

## 2. App Store Connect — 프라이버시 · 심사 노트

- [x] **사람 작업 완료**: App Privacy 질문지에서 "데이터 수집 없음" 선택함 (두 앱 모두)
- [ ] **사람 작업**: App Review Information → Notes에 `docs/app-store/review-notes.md`의 영문 블록 붙여넣기 — 외부 테스터를 추가하거나 정식 심사에 제출하는 시점에만 필요 (지금 내부 테스팅만으로는 불필요, §5 참고)
- [x] 카메라 사용 목적 문구는 Info.plist에 반영됨 — `NSCameraUsageDescription` (iOS는 이번에 추가, Mac은 기존부터 있었음)

## 3. 앱 등록 — 완료

Mac 타겟과 iOS 타겟의 번들 ID를 분리했다 (`com.youngminpark.maccctv.mac` / `com.youngminpark.maccctv.ios`). App Store Connect에 앱 2개가 등록되어 있다:

- [x] **"CCTV for Mac"** — macOS, `com.youngminpark.maccctv.mac`, SKU `maccctv-macos-20260705` (App Store Connect app id `6787679673`). 원래 번들 ID가 `.ios`로 잘못 연결되어 있었는데(과거 번들 ID 공유 버그의 흔적), 빌드가 아직 없는 상태라 App Store Connect에서 번들 ID 드롭다운만 바꿔 재사용함 — 앱 삭제·재생성 불필요했음
- [x] **"CCTV for Mac Companion"** — iOS, `com.youngminpark.maccctv.ios`, SKU `maccctv-ios-20260706` (app id `6787729272`)
- [x] **사람 작업 완료**: 두 앱 모두 App Store 카테고리 = Utilities 입력함 (API로 자동화 시도했으나 이 API 키 역할은 앱 등록/빌드 업로드만 가능하고 카테고리·가격·연령등급 등 마케팅 메타데이터 수정은 `403 FORBIDDEN` — 사람이 직접 함)
- [x] **사람 작업 완료**: 가격 = 무료, 연령 등급 설문 작성함

## 4. CloudKit 프로덕션 스키마 배포 — 완료

- [x] **사람 작업 완료**: CloudKit Console에서 Production 스키마 배포함

## 5. TestFlight 빌드 — 업로드 완료

두 타겟 모두 Release 아카이브 → 익스포트 → 업로드까지 실행 완료. 재현 가능한 아카이브/익스포트 명령은 `script/archive_and_export.sh [mac|ios|all]`.

업로드는 `xcodebuild -exportArchive -destination upload`가 두 가지 이유로 막혀서 (① 자동 서명 세션은 업로드 API 인증까지 못 미침 — `IDEDistribution.DistributionCredentialedProviderLocatorError`, ② App Store Connect API 키(`~/.appstoreconnect/private_keys/AuthKey_<API_KEY_ID>.p8`, Key ID `<API_KEY_ID>`)는 인증서를 새로 발급하는 권한이 없어 iOS Cloud 서명이 거부됨), 대신 **이미 서명까지 끝난 `.pkg`/`.ipa`를 `xcrun altool --upload-app`으로 업로드**했다 (서명과 업로드를 분리 — 서명은 앞서 `-allowProvisioningUpdates`로 이미 끝나 있었고, altool은 인증서 발급 권한 없이 업로드 API 권한만 있으면 됨):

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 8871917e-5464-4fed-b897-0a99b7fcbc86 — build 1, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: c907cc59-3789-4af7-951e-60675b06049b — build 1, processingState VALID
# (first two iOS delivery attempts failed silently on Apple's backend — error 90683,
#  missing NSCameraUsageDescription; WebRTC.framework references camera APIs even
#  though this app never calls them. Fixed in apps/ios/CCTVCompanion/Support/Info.plist.)
```

- [x] 두 빌드 App Store Connect에 업로드 완료, 둘 다 `processingState: VALID`
- [x] **사람 작업 완료**: TestFlight에서 두 빌드 각각 "내부 테스트" 그룹에 배정하고 테스터 추가함

### Build 2 (2026-07-06) — 실기기 테스트에서 발견된 버그 수정

Build 1을 실기기(Mac+iPhone TestFlight)로 검증하며 발견된 문제 2건 수정 후 재업로드:

- **재생 검은 화면**: `CKAsset.fileURL`이 CloudKit이 관리하는 임시 파일이라 원본 레코드가 해제되면 사라짐 — 지난 세션 다시보기가 항상 검은 화면이었던 원인. `ChunkAssetCache`로 최초 1회 로컬에 복사해 안정적인 경로를 반환하도록 수정 (TDD, `CCTVKitTests` 전체 통과)
- **UI 정리**: 재생 화면에서 "지연 라이브: N초 지연, 청크 N개" 같은 내부 구현 노출 텍스트 제거, "7일 자동 삭제" 안내를 보관함 우측 상단 설정(gear) 화면으로 이동

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: f78a6a5f-d3bf-4683-8782-beed06cecc8c — build 2, COMPLETE

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 652dee32-5ae9-4638-b481-62abfc6e2c02 — build 2, COMPLETE
```

- [x] Build 2 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 1→2)
- [x] **사람 작업 완료**: TestFlight에서 build 2를 내부 테스트 그룹에 배정하고 재검증함

### Build 3 (2026-07-06) — 실기기 테스트에서 발견된 버그 3건 추가 수정

Build 2를 실기기로 검증하며 발견된 문제 4건 중 3건은 build 2 이후 로컬 커밋으로 이미 해결되어 있었고(재생바 길이·save-video 부재는 build 2에 해당 기능 자체가 없었을 뿐), 나머지 1건(WebRTC 재접속)은 이번에 새로 수정:

- **재생바가 6초 단위로 보임**: 원인 아님으로 확인 — `AVMutableComposition` 합성 로직 자체는 정상(합성 mp4로 직접 재현 테스트, 3×2초 청크 → 정확히 6.0초). Build 2가 아직 `AVQueuePlayer` 방식이라 청크마다 재생바가 리셋되는 옛 동작이었을 뿐, build 3부터는 정상 표시될 것으로 예상
- **save-video 공유 시트 없음**: build 2에는 해당 기능 자체가 없었음 (build 2 업로드 이후 로컬 커밋으로 구현됨) — build 3부터 종료된 세션에 노출
- **설정 화면 부실**: 섹션 구조로 재구성 — 저장 위치/자동 삭제 안내, iCloud 저장 공간 확인 방법(iPhone 설정 > Apple ID > iCloud > 저장 공간 관리), 보관함에서 스와이프해 즉시 삭제하는 방법, 앱 버전 정보
- **WebRTC 재접속 실패** (진짜 버그, 신규 수정): Mac의 `BroadcastSession`이 녹화 시작 시 offer를 한 번만 보내고 재협상 수단이 없어, 보관함으로 나갔다 재접속하면 항상 10초 타임아웃 후 지연 폴백으로 빠졌음. `SignalKind.viewerReady`를 추가해 iOS가 세션 진입(최초/재접속 모두)마다 신호를 보내면 Mac이 기존 연결을 정리하고 새 peer connection + 새 offer로 재협상하도록 수정. iOS도 재접속 시 신호 수신 커서를 현재 시각으로 리셋해 과거 offer/ice를 재처리하지 않게 함

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 09bfdf54-58cc-4850-85a5-5868c45662fa — build 3

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 761eb110-6fd5-42c7-95b9-46af3d417875 — build 3
```

- [x] Build 3 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 2→3), 둘 다 `processingState: COMPLETE`
- [x] **사람 작업 완료**: TestFlight에서 build 3를 내부 테스트 그룹에 배정하고 재검증함 — 재생바 길이·save-video 버튼·설정 화면은 정상 확인. WebRTC는 첫 연결·재접속 모두 여전히 지연 폴백, save-video 공유 시트에 "비디오 저장" 옵션 없음 — 아래 build 4에서 수정

### Build 4 (2026-07-06) — WebRTC 연결 타임아웃 회귀 + Save Video 권한 누락 수정

Build 3 검증에서 새로 드러난 문제 2건:

- **WebRTC 연결이 첫 접속도 실패** (build 3에서 만든 회귀): build 3의 viewerReady 기반 재협상 수정이 재접속은 고쳤지만, 이제 모든 연결(최초 포함)이 "iOS→Mac viewerReady 왕복 + Mac→iOS offer 왕복"을 먼저 거쳐야 해서 기존 10초 타임아웃 예산을 갉아먹게 됨. iOS 신호 폴링 주기를 2초→0.5초로 줄이고, `LiveConnectionPolicy` 타임아웃을 10초→20초로 늘려 이 왕복에 여유를 줌
- **save-video 공유 시트에 "비디오 저장" 옵션 없음**: 파일 형식 문제가 아니라 `NSPhotoLibraryAddUsageDescription`이 Info.plist에 없어서였음 — 이 문구가 없으면 iOS가 사진 보관함에 쓰는 공유 액션 자체를 조용히 숨김 (예전 카메라 권한 문구 누락과 같은 종류의 문제). `apps/ios/CCTVCompanion/Support/Info.plist`·`InfoPlist.xcstrings`에 추가함

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 63209d2e-9128-4239-a607-e22882ecbb7c — build 4

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: a0947e90-3365-4537-a6d0-cc300da49b89 — build 4
```

- [x] Build 4 두 타겟 모두 업로드 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 3→4)
- [ ] **사람 작업**: TestFlight에서 build 4를 내부 테스트 그룹에 배정하고 재검증 (WebRTC 첫 연결·재접속, save-video 공유 시트의 "비디오 저장")

**외부 테스터는 결정에 따라 불필요 (2026-07-06):** 계획 문서의 M9 검증 기준은 "TestFlight 외부 테스터 설치"라고 되어 있지만, 실기기(본인 Mac + iPhone) 검증이 목적이면 그 계정이 이미 내부 테스터로 등록되어 있으니 내부 테스팅만으로 충분하다. 외부 테스터(Beta App Review 필요)는 **팀 멤버가 아닌 다른 사람**에게 정식 출시 전 미리 배포하고 싶을 때만 필요 — PRD §11 출시 전략도 베타 단계 없이 바로 무료 출시라 필수 아님. 필요해지면 아래 항목 진행:

- [ ] **(선택) 외부 테스터가 필요해지면**: 베타 검토(Beta App Review) 제출 전 App Review Information Notes 작성 필요

**Export Compliance 자동화 (2026-07-06):** build 3까지는 매 업로드마다 App Store Connect에서 "Missing Compliance"로 뜨며 웹 UI에서 수동으로 답변해야 했음 — 두 앱 Info.plist에 `ITSAppUsesNonExemptEncryption` 키 자체가 없어서 매번 물어보는 구조였음. 표준 TLS(CloudKit)·표준 DTLS-SRTP(WebRTC)만 쓰고 자체 암호화가 없으므로 두 Info.plist에 `ITSAppUsesNonExemptEncryption = false`를 추가함 (`apps/mac/MacCCTV/Support/Info.plist`, `apps/ios/CCTVCompanion/Support/Info.plist`) — **build 4부터** 매 업로드마다 자동으로 규정 준수 처리됨. build 3는 이 수정 이전에 업로드되어 여전히 TestFlight에서 수동으로 한 번 답변해야 함(암호화 사용 여부 질문에 "표준 암호화만 사용"으로 응답).
- [x] **사람 작업 완료**: iOS·Mac 둘 다 TestFlight로 설치 완료 (iOS는 기존 개발용 설치를 대체하며 로컬 데이터 유실 — 의도된 정리였음)
- [ ] **사람 작업**: 실기기 종단 검증 — 번들 ID 분리·CloudKit Production 전환·Release 서명 빌드 조합으로는 처음 도는 경로라 아래 시나리오를 실제로 확인 필요:
  1. Mac 온보딩: 카메라 권한 허용 → iCloud 확인 통과 → 온보딩 완료
  2. `⌃⌘C` → 메뉴바 아이콘만 변화, 창 없음 확인
  3. iPhone 앱 열기 → 1~2초 지연 실시간 영상 (또는 폴백 모드 "지연" 표시) 확인
  4. 키보드 입력 / 전원 분리 / 뚜껑 닫기 중 하나 → iPhone 푸시 알림 도착 확인
  5. iPhone 라이브 화면에서 사이렌 버튼 길게 누르기 → Mac에서 2초 내 사이렌+전체화면 경고 → `⌃⌘C`로 3초 내 해제
  6. `⌃⌘C` → 감시 종료
  7. iPhone 보관함에서 방금 세션 재생 확인, CloudKit Console(Production 환경)에 Session/Chunk 레코드 실제로 쌓였는지 확인
  8. 문제 생기면 바로 알려주기 — Production 환경·Release 서명이라 Debug 빌드에서 안 보이던 문제(엔타이틀먼트 차이 등)가 나올 수 있음

### 버전 번호 참고

현재 `project.yml`은 `MARKETING_VERSION: 0.1.0`, `CURRENT_PROJECT_VERSION: 1`이다. 최초 정식 제출이라면 "1.0"으로 올리는 것이 관례적이지만, 이는 제품 의사결정이라 임의로 바꾸지 않았다 — 원하면 알려주면 반영한다.

## 6. 웹 랜딩 페이지

- [x] `web/index.html` — 정적 1페이지, 한/영 토글, Lighthouse Accessibility/Best Practices/SEO/Agentic Browsing 전부 100점, LCP 174ms/CLS 0.00
- [x] Vercel 배포 완료 — **https://mac-cctv.vercel.app** (`0minseouls-projects` 팀, Hobby 플랜). 라이브 URL에서도 Lighthouse 전 항목 100점 재확인
- [ ] **사람 작업**: 앱 승인 후 `web/index.html`의 "Coming Soon" App Store 배지 2곳(hero, 최종 CTA)을 실제 스토어 링크로 교체 후 `web/README.md`의 재배포 명령으로 반영

## 7. 최종 확인

- [ ] 위 항목 전부 완료 후 App Store Connect에서 "심사에 제출" 클릭 (두 앱 각각)
- [ ] 제출 후 `docs/HANDOFF.md`에 제출일과 심사 상태 추적 메모 추가 권장
