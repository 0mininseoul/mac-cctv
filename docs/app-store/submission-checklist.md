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

- [x] Build 4 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 3→4), 둘 다 `processingState: COMPLETE`
- [ ] **사람 작업**: TestFlight에서 build 4를 내부 테스트 그룹에 배정하고 재검증 (WebRTC 첫 연결·재접속, save-video 공유 시트의 "비디오 저장")

### Build 5 (2026-07-07) — 무장 직후 애매한 신호에 대한 단계적 에스컬레이션 추가

Task #10 "모션 감지 후 사이렌이 안 울림" 제보 근본 원인 확인: 버그가 아니라 설계대로 동작한 것 — 무장 후 30초 유예 기간(`armGracePeriod`)은 오탐 방지를 위한 1차 게이트라 유예 기간 내 모든 신호를 무조건 `.notifyOnly`(무음 이벤트 기록)로 처리한다. 실제 제보 사례는 무장 24초 후 트랙패드 터치였고, 이는 유예 기간(30초) 이내였다. 유예 기간 자체를 줄이면 소유자 본인의 정상적인 무장 직후 조작에도 사이렌이 울릴 위험이 있어(PRD §8.10: 공공장소 오탐 사이렌은 앱 삭제로 이어질 수 있는 리스크), 유예 기간을 유지하되 애매한 신호에 대해 3단계(`.escalate`)를 추가:

- 유예 기간 이후 터치 등 보강 신호와 함께 모션이 짧게(3초 미만) 감지되면 즉시 사이렌을 울리는 대신, iPhone에 "Mac이 들렸을 수 있습니다" 긴급 푸시(잠금화면에서 바로 취소할 수 있는 Dismiss 액션 포함)를 보내고 15초 카운트다운 시작
- 카운트다운 중 iPhone에서 취소(알림의 Dismiss 액션 또는 앱 내 "에스컬레이션 취소" 버튼)하면 사이렌 없이 종료, CloudKit에 `escalationDismissed` 이벤트로 감사 기록
- 취소하지 않고 15초가 지나면 기존과 동일하게 자동으로 사이렌 발동
- Mac 메뉴바 팝오버에도 대기 중 카운트다운 표시
- 기존 동작은 변경 없음: 3초 이상 지속되는 확실한 모션은 여전히 즉시 사이렌(에스컬레이션 단계 건너뜀), 모션 없는 단순 터치/전원 분리는 여전히 무음 처리

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 00ca9826-5a95-4155-a673-b63c060220de — build 5, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 32db5c71-5ff4-4118-a728-9fbd26bfa354 — build 5, processingState VALID
```

- [x] Build 5 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 4→5), 둘 다 `processingState: VALID`
- [ ] **사람 작업**: TestFlight에서 build 5를 내부 테스트 그룹에 배정하고 실기기로 에스컬레이션 시나리오 검증 (무장 → 30초 유예 대기 → 터치+짧은 흔들림 → 푸시+카운트다운 확인 → Dismiss 취소/타임아웃 두 경로 모두 확인)

### Build 6 (2026-07-07) — 에스컬레이션 파라미터 조정 및 iOS에 Mac 실제 상태 반영

사용자 피드백 두 가지 반영:

- 무장 유예 기간 30초 → 15초, 에스컬레이션 카운트다운 10초(기존 15초 계획을 5초로 줄였다가 최종 10초로 재조정) — `AutoSirenTriggerPolicy.armGracePeriod`/`escalationTimeout`
- Task #10 후속 제보: iOS "에스컬레이션 취소" 버튼이 Mac에 실제로 취소할 대상이 없을 때도 항상 탭 가능했고 "전송됨"만 표시되어 실제 효과가 있었는지 알 수 없었음. Session 레코드에 `escalationDeadline`(Date?) 필드를 추가해 Mac이 에스컬레이션 시작/취소/타임아웃 시점마다 반영하도록 하고, iOS는 기존 3초 라이브 폴링 루프에서 이 필드를 함께 조회해 실제로 대기 중일 때만 카운트다운과 취소 버튼을 노출하도록 변경 (`SessionPlaybackViewModel`, `SessionPlaybackView`)

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: f8cf14ce-7391-45ef-8d91-bab6e402159d — build 6, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: bcf62f61-fb23-495c-9ea1-3811b4f119d2 — build 6, processingState VALID
```

- [x] Build 6 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 5→6), 둘 다 `processingState: VALID`
- [ ] **사람 작업**: TestFlight에서 build 6를 내부 테스트 그룹에 배정하고 실기기 검증 (무장 → 15초 유예 대기 → 터치+짧은 흔들림 → 푸시+10초 카운트다운 확인 → iPhone에서 Dismiss 시 카운트다운/버튼이 실제로 사라지는지, 그리고 아무 일도 없을 때는 취소 버튼 자체가 안 보이는지 확인)

### Build 7 (2026-07-08) — build 6 실기기 테스트 결과 5건 반영

실기기 테스트에서 나온 제보 5건 처리:

1. **WebRTC가 연결된 지 ~20초 후 지연 재생으로 전환**: Mac 쪽 진단 로그(`m6-result.txt`)를 확인해보니 피어 연결은 사용자가 직접 감시를 끌 때까지 `connected` 상태를 유지했다 — 즉 실제 네트워크 단절이 아니었다. `LiveConnectionPolicy.connectedFrameGrace`(ICE 연결 이후 첫 프레임을 기다리는 시간)가 5초로 너무 타이트해서, ICE/DTLS는 붙었지만 디코더가 첫 프레임을 5초 안에 못 받으면 iOS가 스스로 피어 연결을 끊고 지연 재생으로 넘어가는 구조였다(재시도 없이 그 세션 동안 고정됨). 5초 → 15초로 완화. 또한 `WebRTCReceiver`의 상세 진단(`M6_RECEIVER_*`)이 지금까지 아무 곳에도 연결되어 있지 않아 iOS 쪽 근거가 전혀 없었음 — iOS 앱그룹 파일에 기록하는 `IOSDiagnostics` 추가, fallback 전환 시점에 연결 후 경과시간도 함께 기록. **다음 테스트에서 Xcode "Devices and Simulators → Download Container"로 iPhone의 `m6-receiver-result.txt`를 확인하면 실제 원인을 확정할 수 있음.**
2. **deviceMotion 에스컬레이션 시 Mac 팝오버는 10초 카운트다운이 보이는데 iPhone엔 카운트다운도 취소 UI도 안 보임**: build 6에서 처음 추가한 `Session.escalationDeadline` 필드가 원인일 가능성이 매우 높음 — CloudKit은 신규 필드를 Development 스키마에는 자동으로 추가하지만 Production에는 수동으로 "Deploy Schema Changes"를 눌러야 반영된다. TestFlight 빌드는 Production CloudKit 환경을 쓰므로, 이 필드를 한 번도 Production에 배포하지 않았다면 Mac의 저장 자체가 실패했을 것. **사람 작업 필요**: CloudKit Dashboard(icloud.developer.apple.com/dashboard) → 컨테이너 선택 → Schema → Deploy Schema Changes → Session 레코드 타입의 `escalationDeadline` 필드를 Production으로 배포. 근거를 명확히 남기기 위해 `m10-escalation-result.txt` 로그도 매번 덮어쓰던 것을 append로 바꿔, 다음 테스트에서 `M10_SESSION_SYNC_FAILED`가 찍히는지 그대로 확인 가능하게 함.
3. **사이렌 풀스크린 경고 문구 위치**: 화면 중앙 정렬 → 하단 정렬로 변경(`SirenController.SirenWarningView`). 사용자가 첨부한 이미지는 일반 "JPEG 파일" 플레이스홀더 아이콘으로 전달되어 실제 사진 내용을 확인할 수 없었음 — 이미지 자체를 배경으로 넣는 부분은 보류, 텍스트 위치만 우선 반영.
4. **푸시 알림 문구가 "이벤트 감지: personMotion"처럼 로우데이터 그대로 옴**: 이벤트 타입별 개별 CKQuerySubscription으로 분리(`ensureEventTypeSubscription`)해 personMotion/inputTouch/powerDisconnect/deviceMotion/lidClose 5종에 각각 자연어 고정 문구 부여(예: "사람이 감지됐어요!", "누군가 맥북을 두드리고 있어요"). 기존 범용 구독(`event-created-v1`)은 이 5종 + `sirenEscalation`(이미 전용 구독 있음)을 제외하도록 predicate 수정 — 중복 푸시 방지.
5. **iOS 보관함 로딩이 느림**: `SessionLibraryViewModel.load()`가 세션마다 순차적으로 `fetchEvents`를 호출하는 N+1 패턴이었음(세션 10개면 10번 순차 왕복) → `TaskGroup`으로 병렬화. 또한 로딩 전에 `sweepExpired()`(만료 세션 정리)를 블로킹으로 먼저 실행하던 것을 백그라운드로 분리.

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: f2ddf475-25ce-4f68-a1cb-f9b55466a581 — build 7, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 9e188585-aca5-46ad-8ab7-72caafa9c10f — build 7, processingState VALID
```

- [x] Build 7 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 6→7), 둘 다 `processingState: VALID`
- [x] Build 7 계획 당시 "CloudKit Production 스키마 미배포"를 원인으로 추정했으나, 실제 CloudKit Dashboard의 "Deploy Schema Changes" 확인 결과 Record Types/Indexes/Security Roles 모두 변경사항 0건 — 애초에 `saveSession`/`fetchSession`이 레코드 ID 기반 직접 저장·조회(`database.save`/`database.record(for:)`)라 인덱스·스키마 배포가 필요 없는 API였음. **가설 기각**, 진짜 원인은 build 8 참고.

### Build 8 (2026-07-08) — 사이렌 배경 이미지, 에스컬레이션 폴링 주기 수정

- 사이렌 풀스크린 경고에 사용자가 제공한 이미지(`apps/mac/MacCCTV/Assets.xcassets/SirenWarningBackground.imageset`)를 배경으로 추가, 하단 텍스트 가독성을 위해 하단 그라디언트 스크림 적용
- iOS 에스컬레이션 상태 폴링 원인 재진단: build 7까지도 `SessionPlaybackViewModel`의 에스컬레이션 상태 조회가 3초 주기 청크 로딩 루프에 얹혀 있었음 — 10초짜리 카운트다운 대비 3초 주기는 앱 실행·WebRTC 연결 지연을 감안하면 폴링 기회가 2~3회뿐이라 놓치기 쉬웠음. 청크 로딩 루프와 분리해 독립적인 1초 주기 `escalationPollLoop`로 변경 (레코드 ID 기반 직접 조회라 비용 저렴)
- 푸시 알림 문구를 한 파일에서 훑어볼 수 있도록 `docs/push-notification-copy.md` 추가 (실제 반영은 여전히 `Localizable.xcstrings`에서 — APNs의 `alert-loc-key`는 반드시 "Localizable.strings" 테이블에서만 조회되는 OS 레벨 제약이라 완전히 분리된 파일로는 동작 불가)

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 548a659f-5eae-442c-90ec-6e8c5ee17330 — build 8, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 40bac956-063b-4075-ba74-12fdfa51a7be — build 8, processingState VALID
```

- [x] Build 8 두 타겟 모두 업로드·처리 완료 (`project.yml`의 `CURRENT_PROJECT_VERSION` 7→8), 둘 다 `processingState: VALID`
- [x] **build 8 실기기 결과로 근본 원인 확정**: `m10-escalation-result.txt`에 `Cannot create or modify field 'escalationDeadline' in record 'Session' in production schema` 에러가 실제로 찍힘 → build 7의 "가설 기각"이 틀렸고, **처음 가설(Production 스키마 미배포)이 맞았음**. Dashboard "Deploy Schema Changes"가 0건으로 보인 건 이 필드가 Development 스키마에조차 없었기 때문(TestFlight=Production 쓰기 실패로 추론 안 됨). → build 9에서 접근 방식 자체를 바꿈(아래).

### Build 9 (2026-07-09) — build 8 실기기 결과 8건 반영 + 상태동기화 재설계

**핵심 재설계 — 실시간 상태를 Signal 채널로 전송(스키마 배포 불필요):** `Session.escalationDeadline` 필드는 Production 스키마에 없으면 쓰기가 실패한다(확정됨). 이후 사이렌 상태·세션 종료 등 상태가 늘 때마다 스키마 배포가 필요해지는 구조라, **신규 `SignalKind.macState` 메시지로 Mac→iOS 실시간 상태(에스컬레이션 마감시각/사이렌 on-off/세션종료)를 전송**하도록 전환. SignalKind에 enum 값을 추가하는 건 기존 Signal의 `kind` 문자열 컬럼에 새 값을 넣는 것뿐이라 **CloudKit 스키마 변경이 전혀 필요 없음.** `Session.escalationDeadline` 필드는 완전히 제거. → 앞으로 CloudKit Dashboard 수동 작업 불필요.

실기기 제보 8건:

1. **공포짤 이용등급**: 코드 아님 — **사람 작업**: App Store Connect → 앱 → 앱 정보(또는 제출 시) → 연령 등급 설문에서 "공포/무서움 테마(Horror/Fear Themes)"를 "가끔/약함" 이상으로 답하면 12+로 상향됨. 4+ 유지 불가(공포 이미지 포함).
2. **사이렌 문구가 이미지에 가려 안 보임**: 겹침 레이아웃(scaledToFill 전체 덮기)이 원인. 이미지 상단 62% + 하단 38% 불투명 검은 밴드에 큰 문구를 배치해 항상 보이게 재구성(`SirenWarningView`).
3. **종료된 세션 영상 하나도 재생 안 됨**: `AVComposition` 스티칭이 청크 MP4에서 실패하는 것으로 추정. 컴포지션이 비면 개별 파일을 `AVQueuePlayer`에 큐잉하는 폴백 추가(더 관대함) + `m4-replay-result.txt`에 청크수/재생가능수/합성수 진단 기록.
4. **푸시 문구 그대로**: 원인 확정 — 기존 `event-created-v1` catch-all 구독이 서버에 그대로 남아 옛 문구("이벤트 감지: …")로 계속 발송. **`database.save`는 기존 구독 ID의 predicate/문구를 갱신하지 못함.** 레거시 구독을 삭제하고 버전업(v2)한 타입별 구독을 재생성하도록 변경. 범용 catch-all은 제거(사이렌 관련 이벤트는 푸시 안 함).
5. **WebRTC 17초**: CloudKit이 ICE 후보 1개당 별도 레코드 왕복이라 지배적 지연. **non-trickle ICE로 전환** — ICE gathering 완료(최대 2.5초)까지 기다렸다가 후보가 포함된 SDP를 offer/answer로 한 번에 전송, 개별 후보 trickle 제거. CloudKit 왕복 ~10회 이상 → offer/answer 2회로 축소.
6. **종료 후 '누락 청크' 화면**: iOS가 세션 종료를 몰라 라이브 UI 유지가 원인. Mac이 종료 시 `macState(sessionEnded)` 전송 → iOS가 받으면 WebRTC 내리고 replay로 자동 전환(누락구간 UI 숨김).
7. **사이렌 버튼 '꾹 누르기' 힌트 없음**: 누르는 동안 좌→우로 채워지는 진행 표시 + "꾹 눌러서 사이렌을 울립니다" 힌트 문구 추가.
8. **사이렌 울릴 때 iOS에 끄기 버튼 없음**: `SignalKind.silenceSiren` 추가 — iOS가 보내면 Mac이 사이렌만 끄고 armed 유지(`.silenceSiren` 상태전환). Mac이 `macState(sirenActive)` 전송 → iOS가 사이렌 활성 시 '사이렌 끄기' 버튼 표시.

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 6d3da680-4e42-49d0-a2be-d923a14e9893 — build 9, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 8456d978-3767-47b4-aa7a-7a6bf080a1f7 — build 9, processingState VALID
```

- [x] Build 9 두 타겟 모두 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 8→9), 둘 다 `processingState: VALID`
- [ ] **사람 작업 1 (연령 등급)**: App Store Connect에서 연령 등급을 12+로 상향(공포 이미지). CloudKit Dashboard 수동 작업은 이제 불필요.
- [ ] **사람 작업 2 (재검증)**: TestFlight build 9 배정 후 8건 재확인 — 특히 (a) 에스컬레이션/사이렌 상태가 iPhone에 뜨는지, (b) 종료 세션 영상 재생(안 되면 `m4-replay-result.txt` 확인), (c) WebRTC 연결 시간 단축(안 되면 `m6-receiver-result.txt` 확인), (d) 사이렌 끄기 버튼 동작

### Build 10 (2026-07-11) — build 9 실기기 결과 7건 반영

Build 9 실기기 테스트에서 8건 제보(⑧ 종료 세션 자동재생은 이미 정상 확인되어 제외 → 7건). 각 항목은 이 개발 Mac의 실제 런타임 진단 로그·청크 파일·git 델타로 근본 원인을 확인함. 설계 문서: `docs/superpowers/specs/2026-07-10-build10-field-test-fixes-design.md`.

1. **카메라 ~3초 뒤 켜짐**: 무장 플로우가 `accountStatus`+`reconcile` CloudKit 왕복을 `engine.start()` 앞에 직렬로 쌓던 것이 원인. 카메라 예열(`async let`)을 그 왕복과 **병렬화**해 카메라가 ~1-2초 먼저 켜짐(무장 후에만 켜짐 — 사전 예열 아님, 사용자 선택). `SurveillanceController.startSurveillance`.
2. **꺼진 앱에서 푸시 전멸 (build 9 회귀, 확정)**: build 8까지는 초기 빌드의 stale `event-created-v1`(전체 이벤트·옛 문구) 구독이 푸시를 실어나르고 있었고, build 9가 그걸 삭제 후 per-type v2로 교체하는데 모든 에러를 `try?`로 삼켜, 삭제만 성공하고 생성 실패 시 구독 0개가 됨. **멱등·비파괴 재작성**(`synchronizeSubscriptions`): 기존 구독 조회(`fetchExistingSubscriptionIDs`) → 없는 것만 생성 → 전부 확인된 뒤에만 구식 삭제. iOS `m-notif-result.txt`에 `M11_SUBS_*` 진단 기록. (aps-environment/백그라운드모드는 재검토 후 제외 — export가 이미 production 재작성, 가시성 알림엔 백그라운드모드 불필요.)
3. **연결 로딩 표시 작음**: 좌하단 작은 칩 → 라이브·미연결 시 **중앙 대형 오버레이**(스피너 + "실시간 연결 중…"). `WebRTCReceiver.isConnectingLive` 바인딩.
4. **사이렌 버튼 너무 큼**: 세로 스택(48pt+힌트+상태) → **가로 한 줄**(사이렌 홀드버튼 38pt + 종료 버튼), 힌트는 공유 캡션 한 줄로. `LiveControlBar`.
5. **원격 종료 버튼**: 신규 `SignalKind.endSession`(iOS→Mac, 우선순위 0). Mac이 받으면 `stopSurveillance(.ended)`(종료 전 `sessionEnded` 방송 → iOS 자동 replay 전환). iOS는 오작동 방지 확인 다이얼로그 1회.
6. **WebRTC ~10초**: m6 로그의 `OFFER_SENT gathering=1`로 확정 — `.gatherContinually`는 `.complete`를 보고하지 않아 양쪽이 매번 2.5초 타임아웃을 꽉 채움. **`.gatherOnce`로 전환**(`.complete` 정상 발화) + host 후보 준비 즉시(≥1, ~0.6초) 전송 + iOS 시그널 폴링 500→250ms. 기대 ~10초 → ~4-5초.
7. **공포짤 전체화면 못 채움**: VStack(이미지 62%+검은밴드 38%) → **ZStack 전체 채움 + 하단 그라디언트 스크림 위 오버레이 자막**(폰트 확대). `SirenWarningView`.

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: c8a26bf9-dc15-4c00-8250-cbf766e5ebe8 — build 10, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: bc4e023b-cec5-439a-a2a8-1d92df489a9a — build 10, processingState VALID
```

- [x] Build 10 두 타겟 모두 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 9→10), 둘 다 `processingState: VALID`
- [x] **사람 작업 (재검증) 완료**: build 10 테스트 — WebRTC 8초로 단축, 카메라·레이아웃·모달 관련 후속 피드백은 build 11로 반영. 푸시는 여전히 미도착 → build 11에서 진짜 근본원인 확정.

### Build 11 (2026-07-12) — 푸시 진짜 근본원인 확정 + 라이브 컨트롤 재설계 + 재생 속도

build 10에서도 푸시 전멸이 계속돼 systematic-debugging으로 재조사. 설계: `docs/superpowers/specs/2026-07-12-build11-push-rootcause-ui-replay-design.md`.

**② 푸시 진짜 근본원인 (코드+git으로 확정, 로그 불필요):** `type == X` predicate를 쓰는 구독(per-type, escalation, catch-all)은 **`Event.type` 필드가 Production 스키마에서 Queryable로 인덱싱돼 있어야** 저장·발화된다. 앱은 Event를 `session`·`value:true`로만 쿼리해서 `type`은 Production에서 queryable로 설정된 적이 없다 → `type==X` 구독은 전부 저장 실패. build 8까지 푸시를 실어나른 건 `value:true`(전체매치) 구독뿐이었고 build 9가 그걸 지웠다. (signal/macState 동기화가 계속 잘 된 것도 그게 `value:true`라서.) `escalationDeadline` 때와 같은 Production 스키마 계열 문제.

1. **카메라 시작**: build 10에서 iCloud 왕복과 병렬화 완료(추가 변경 없음, 체감 확인 대상).
2. **라이브 하단 버튼 어색**: 사이렌·종료가 둘 다 빨강으로 경쟁 → **위계 재설계**(frontend-design): 사이렌=유일한 빨강 긴급 hold(그라디언트 채움+햅틱), 종료=중립 회색 컴팩트 secondary. 통일 52pt/14pt 라운드. `LiveControlBar` + 컴포넌트 분리.
3. **종료 확인 모달 상단**: `.confirmationDialog`(하단 액션시트) → `.alert`(중앙 모달).
4. **종료 세션 재생 11초**: `fetchChunks`가 목록 조회 시 모든 청크 MP4를 재다운로드하던 것이 원인. `fetchChunkMetadata`(video 제외 빠른 쿼리) + `ChunkAssetCache.cachedFileURL`로 **캐시 안 된 청크만 다운로드**, 컴포지션 duration 로딩 **병렬화**. 재열람/라이브로 본 세션은 사실상 즉시 재생.
5. **사이렌 텍스트**: 화면 높이 비례(`height*0.11`, 최대 160pt)로 확대.
6. **WebRTC**: build 10에서 8초로 개선됨(추가 최적화 보류).

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 28d62cf6-14e8-4f3d-8197-a52b32076fe8 — build 11, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 9f9ee685-deea-4c07-b480-909763e8e109 — build 11, processingState VALID
```

- [x] Build 11 두 타겟 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 10→11), 둘 다 `processingState: VALID`
- [ ] **사람 작업 1 (필수 — 푸시 근본 해결)**: CloudKit Dashboard에서 `Event.type`을 Queryable로 표시 후 Production 배포:
  1. https://icloud.developer.apple.com/dashboard → 컨테이너 `iCloud.com.youngminpark.maccctv` 선택
  2. 좌측 **Schema → Indexes**(또는 Record Types → **Event**)
  3. **Event** 레코드 타입에서 `type` 필드에 **QUERYABLE** 인덱스 추가 (Add Index → Field: type, Index Type: Queryable → Save)
  4. 우상단 **Deploy Schema Changes…** → Development에서 **Production**으로 배포 확정
  5. 배포 후 iPhone에서 **build 11 앱을 한 번 재실행**(구독 부트스트랩이 재실행돼 v3 per-type 구독 생성)
- [ ] **사람 작업 2 (재검증)**: 위 배포 후 — (a) 꺼진 앱에서 이벤트 주면 친근 문구 푸시 도착(안 오면 iPhone `m-notif-result.txt`의 `M11_SUBS_CREATED` vs `M11_SUBS_CREATE_FAILED` 확인), (b) 라이브 하단 컨트롤/종료 모달, (c) 종료 세션 재생 즉시성, (d) 사이렌 텍스트 크기

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

### Build 12 (2026-07-13) — 푸시 근본원인 확정(프로덕션 프로브) + 자동 폴백

**근본원인 확정 (프로덕션에 직접 CKQuerySubscription을 만들어 확인):** Private DB 서버 로그에 `SubscriptionCreate` 6건이 `BAD_REQUEST`, 그리고 프로덕션 컨테이너에 직접 프로브를 돌린 결과:
- `Event value:true` 구독 → **성공** (Signal 구독·build 8 catch-all과 동일 형태)
- `Event type == X` 구독(alert/silent 무관) → **실패**, `code=12 server="attempting to create a subscription in a production container"`

즉 `type == X` predicate 구독은 **Event `type` queryable 인덱스가 프로덕션 스키마에 실제로 배포돼 있어야** 하는데(대시보드 표시와 무관하게) 배포가 안 돼 거부된다. `value:true`는 필드 인덱스가 필요 없어 항상 성공. `escalationDeadline`과 동일 계열의 dev↔prod 스키마 분기.

**해결 — 자동 폴백(스키마 상태와 무관하게 푸시 보장):** `synchronizeSubscriptions`가 per-type(`type==X`, 친근 문구)를 시도하고, 하나라도 실패하면 `value:true` 전체매치 구독(`event-all-v1`, 제너릭 문구 `event_generic_notification_body`)을 만들어 푸시가 무조건 도착하게 한다. 인덱스가 실제로 배포되면 per-type이 성공하며 폴백은 자동 제거(self-healing). 모드는 `m-notif-result.txt`의 `M11_SUBS_MODE per-type|fallback`으로 확인.

- [x] Build 12 두 타겟 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 11→12), 둘 다 `processingState: VALID`
- [x] **사람 작업 완료**: CloudKit Dashboard에서 Event `type` queryable 인덱스를 프로덕션에 실제 배포함. 배포 후 앱 재실행 시 폴백이 자동으로 per-type 친근 문구로 승격됨 — **실기기에서 친근 per-type 푸시 도착 확인 완료(2026-07-14)**. (프로덕션 화면에 인덱스가 "보이는" 것과 실제 배포는 다름 — 배포 전엔 프로덕션이 `type==X` 구독을 거부했음.)
- [ ] **재검증**: 꺼진 앱에서 이벤트 → 푸시 도착(폴백이면 "🚨 Mac에서 이상이 감지됐어요", 인덱스 배포됐으면 "사람이 감지됐어요!" 등 per-type).

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 858dcb9d-2bce-4471-bfc1-db87a2234fc9 — build 12 (UPLOAD SUCCEEDED)

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: ef8e73c4-d53c-4b69-b972-f033f9d82f8d — build 12 (UPLOAD SUCCEEDED)
```

> 두 타겟 모두 `processingState VALID` 확인 완료. (업로드 시점 개발 Mac의 DNS가 일시 불안정해 iOS 업로드/폴링을 재시도했으나 최종 성공.)

### Build 13 (2026-07-13) — 라이브 하단 컨트롤 UI 재설계 (frontend-design)

build 12 실기기에서 라이브 하단 사이렌 버튼이 화면 절반을 차지하며 부풀던 문제. **원인**: `SirenHoldButton` 안의 채움용 `GeometryReader`가 greedy인데 버튼이 `minHeight`만 지정돼 상한 없이 남는 세로 공간을 다 먹었음. **수정**: 컨트롤 독을 **고정 58pt 높이**로 바꾸고(비디오가 `maxHeight:.infinity`로 남는 공간 차지), frontend-design으로 재구성 — 사이렌은 홀드 시 빨강 그라디언트가 좌→우로 쓸고 글로우+햅틱이 나는 pill(힌트는 라벨 `꾹 눌러 사이렌`에 흡수), 종료는 중립 secondary(66pt), 상단 헤어라인 구분선. `event value:true` 폴백 푸시(build 12)로 이미 푸시는 도착 확인됨.

- [x] Build 13 두 타겟 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 12→13), 둘 다 `processingState: VALID`
- [x] **재검증 완료(2026-07-14)**: 라이브 하단 컨트롤(콤팩트 사이렌 pill·홀드 애니메이션·종료 버튼) 정상, 사이렌 풀스크린 텍스트 크기 정상, 친근 per-type 푸시 정상 도착.

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 0ce68a89-217f-401f-a4ba-088ee102fba1 — build 13

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 9e850920-2984-42b6-9899-dc392f57916a — build 13
```

### Build 14 (2026-07-13) — 종료 세션 재생 로딩 인디케이터

build 13 실기기: 종료된 세션은 재생 버튼을 누르고 3초+ 기다려야 재생되고 로딩 표시가 없음. **원인**: replay 로딩(메타데이터 쿼리 + 미캐시 청크 다운로드 + 컴포지션 합성) 동안 플레이어에 아직 아이템이 없어 화면이 검은 채로 아무 신호가 없었고, 자동재생 전에 사용자가 play를 누르게 됨. **수정**: `isPreparingReplay` 상태를 추가해 첫 로딩 동안 **중앙 스피너 오버레이("영상 불러오는 중…")** 표시, 준비되면 자동 재생(기존 `playbackActive` 경로) + 스피너 페이드아웃. (다운로드 자체는 build 11의 캐시-우선/미캐시만 다운로드/병렬 합성 유지 — 재열람·라이브로 본 세션은 빠름.)

- [x] Build 14 두 타겟 업로드·처리 완료 (`CURRENT_PROJECT_VERSION` 13→14), 둘 다 `processingState: VALID`
- [ ] **재검증**: 종료 세션 열람 시 스피너 표시 후 자동 재생.

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 7d140619-46cf-4ca0-bd72-ebfaa5a15cbc — build 14

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: d2469ef7-bda4-4ce4-8047-70421fc42609 — build 14
```

### Build 15 (2026-07-13) — 보관함 최근 세션 백그라운드 프리페치 (Wi-Fi)

종료 세션 재생이 "본 것만 빨라지는" 구조였음(청크는 세션을 열 때만 다운로드→캐시). 최근에 볼 확률이 높은 세션을 미리 받아 즉시 재생되게 함. **구현**: 보관함 로드 후 최근 **종료 세션 3개**의 청크를 백그라운드로 캐시 워밍(`CloudKitStore.prefetchSessionChunks` = 메타데이터→미캐시만 다운로드). **Wi-Fi(비-expensive/비-constrained)일 때만** 실행(`Reachability`)해 셀룰러 데이터 절약. 목록 로딩은 안 막고 fire-and-forget. `m-prefetch-result.txt`에 `M13_PREFETCH` 로깅.

- [ ] Build 15 두 타겟 업로드·처리
- [ ] **재검증**: Wi-Fi에서 보관함 진입 후 잠시 뒤 최근 세션 3개가 즉시 재생되는지(스피너 없이/짧게).

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: 35baef1e-dce6-45ad-a8ca-0d269953a9f0 — build 15

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey <API_KEY_ID> --apiIssuer <ISSUER_ID>
# Delivery UUID: ac351f5a-418d-497f-9762-ea6180044ec0 — build 15
```

### 버전 번호 참고

현재 `project.yml`은 `MARKETING_VERSION: 0.1.0`, `CURRENT_PROJECT_VERSION: 1`이다. 최초 정식 제출이라면 "1.0"으로 올리는 것이 관례적이지만, 이는 제품 의사결정이라 임의로 바꾸지 않았다 — 원하면 알려주면 반영한다.

## 6. 웹 랜딩 페이지

- [x] `web/index.html` — 정적 1페이지, 한/영 토글, Lighthouse Accessibility/Best Practices/SEO/Agentic Browsing 전부 100점, LCP 174ms/CLS 0.00
- [x] Vercel 배포 완료 — **https://mac-cctv.vercel.app** (`0minseouls-projects` 팀, Hobby 플랜). 라이브 URL에서도 Lighthouse 전 항목 100점 재확인
- [ ] **사람 작업**: 앱 승인 후 `web/index.html`의 "Coming Soon" App Store 배지 2곳(hero, 최종 CTA)을 실제 스토어 링크로 교체 후 `web/README.md`의 재배포 명령으로 반영

## 7. 최종 확인

- [ ] 위 항목 전부 완료 후 App Store Connect에서 "심사에 제출" 클릭 (두 앱 각각)
- [ ] 제출 후 `docs/HANDOFF.md`에 제출일과 심사 상태 추적 메모 추가 권장
