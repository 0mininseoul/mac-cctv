# Mac CCTV 구현 계획

> **For agentic workers:** 이 계획은 코딩 세션에서 `superpowers:executing-plans` 또는 `superpowers:subagent-driven-development`로 실행한다. 각 마일스톤은 독립적으로 검증 가능한 산출물로 끝난다. **이 문서는 의도적으로 코드를 포함하지 않는다** — 파일 구조·인터페이스·검증 기준까지만 확정하고, 코드는 실행 세션에서 TDD로 작성한다 (순수 로직은 테스트 먼저, 하드웨어 의존부는 수동 검증 절차 명시).

**Goal:** 단축키(⌃⌘C)로 켜는 Mac 웹캠 감시 + iPhone 실시간 시청(WebRTC) + iCloud 청크 녹화(7일 자동삭제) + 이벤트 알림 + 사이렌. 운영비 0원 (개발자 서버 0대).

**Architecture:** Mac 앱이 AVFoundation으로 무화면 캡처 → ① WebRTC 트랙으로 iPhone에 P2P 송출, ② 6초 fMP4 청크로 CloudKit private DB 업로드. 시그널링·푸시·저장 전부 CloudKit(사용자 본인 iCloud). P2P 실패 시 청크 이어재생으로 폴백.

**Tech Stack:** Swift 5.10+ / SwiftUI / AVFoundation / CloudKit / WebRTC(SPM: `stasel/WebRTC`) / StoreKit 2 / macOS 14+, iOS 17+ 타겟.

**전제 문서:** `docs/PRD.md` (v5, 모든 제품 결정 확정 상태). 이 계획과 PRD가 충돌하면 PRD가 우선.

## Global Constraints (모든 마일스톤에 적용)

- 감시 중 Mac 화면에 어떤 창·프리뷰·오버레이도 띄우지 않는다 (메뉴바 아이콘 상태 변화만; 사이렌 발동 시의 전체화면 경고는 유일한 예외)
- 웹캠 LED를 끄거나 우회하려는 어떤 시도도 하지 않는다
- 개발자 서버·제3자 백엔드·광고/분석 SDK 절대 금지. 네트워크 통신은 CloudKit·STUN·P2P만. **명확화(2026-07-05): 이 금지는 사용자 데이터를 수집·외부 전송하는 SDK가 대상이다. 데이터를 어디로도 보내지 않는 오픈소스 라이브러리(예: 기술 스택에 명시된 stasel/WebRTC)는 금지 대상이 아니다**
- CloudKit은 **private database만** 사용 (public DB 금지 — 비용 발생 지점)
- 오디오 캡처 금지 (MVP — PRD §10 법적 리스크)
- 기본 단축키 ⌃⌘C, 사용자 변경 가능
- 한국어/영어 동급 지원: 모든 사용자 노출 문자열은 String Catalog(`Localizable.xcstrings`) 경유, 하드코딩 금지
- App Store 표기명 "CCTV for Mac" / 브랜드 "Mac CCTV"
- 자동 사이렌 오탐 = 최악의 실패. 확신 낮으면 사이렌 대신 알림만 (PRD §8.10)
- 커밋은 마일스톤 내 단계마다 자주, 메시지는 conventional commits

---

## 저장소 구조 (M0에서 확정)

```
mac_cctv/
├── docs/                          # PRD, 이 계획, 핸드오프
├── Packages/CCTVKit/              # 공유 Swift Package (Mac·iOS 공용)
│   ├── Sources/CCTVKit/
│   │   ├── Schema/CKSchema.swift          # 레코드 타입·필드명 상수 (단일 진실 공급원)
│   │   ├── Models/                        # Session, Chunk, Event, SignalMessage 값 타입
│   │   ├── Cloud/CloudKitStore.swift      # CRUD·구독·에러 재시도 래퍼
│   │   ├── Cloud/RetentionPolicy.swift    # 7일 삭제 대상 계산 (순수 로직 — 단위 테스트 대상)
│   │   ├── Signaling/SignalingChannel.swift  # 프로토콜 + CloudKit 구현
│   │   └── Live/FallbackPlaylist.swift    # 청크 목록 → 이어재생 큐 계산 (순수 로직)
│   └── Tests/CCTVKitTests/
├── apps/mac/MacCCTV/              # macOS 메뉴바 앱 타겟
│   ├── App/                       # @main MenuBarExtra, AppState(상태 머신: idle↔armed↔siren)
│   ├── Capture/                   # CaptureEngine(AVCaptureSession), ChunkWriter(AVAssetWriter), LocalRingBuffer
│   ├── Upload/ChunkUploader.swift # 업로드 큐·재시도·긴급 플러시
│   ├── Detection/                 # EventDetector(입력·전원·뚜껑), MotionClassifier(전역/부분 모션)
│   ├── Live/BroadcastSession.swift # WebRTC 송출
│   ├── Siren/SirenController.swift # 최대음량 경보 + 전체화면 경고창 + 해제
│   ├── Hotkey/HotkeyManager.swift  # 전역 단축키 (Carbon RegisterEventHotKey — 샌드박스 호환)
│   ├── Power/SleepBlocker.swift    # IOPMAssertion
│   └── UI/                        # PopoverView(설정 3개), OnboardingView(3단계)
├── apps/ios/CCTVCompanion/        # iOS 컴패니언 앱 타겟
│   ├── App/
│   ├── Live/                      # LiveView, WebRTCReceiver, FallbackPlayer(AVQueuePlayer)
│   ├── Library/                   # 세션 목록·재생·삭제
│   ├── Alerts/NotificationHandler.swift
│   ├── Siren/SirenButton.swift    # 길게 누르기
│   └── Monetization/              # TipJarView, HouseBanner(Pro 업셀 — v1.0은 자리만)
└── web/                           # Vercel 랜딩 페이지 (정적, M9)
```

두 앱 타겟은 같은 CloudKit 컨테이너(`iCloud.<bundle-prefix>.maccctv`)와 App Group을 공유한다.

## CloudKit 스키마 (CCTVKit/Schema — 모든 마일스톤의 계약)

| 레코드 타입 | 필드 | 용도 |
|---|---|---|
| `Session` | `startedAt: Date`, `endedAt: Date?`, `deviceName: String`, `status: String(recording/ended/interrupted)` | 감시 세션 1회 |
| `Chunk` | `session: Reference`, `index: Int`, `startedAt: Date`, `duration: Double`, `video: CKAsset(fMP4)` | 4~6초 영상 조각 |
| `Event` | `session: Reference`, `type: String(inputTouch/powerDisconnect/lidClose/personMotion/deviceMotion/sirenAuto/sirenManual)`, `occurredAt: Date`, `confidence: Double` | 감지 이벤트 (푸시 트리거) |
| `Signal` | `session: Reference`, `kind: String(offer/answer/ice/sirenCommand)`, `payload: String(JSON)`, `sender: String(mac/ios)`, `createdAt: Date` | WebRTC 시그널링 + 원격 명령 |

- iPhone 알림: `Event`·`Session`에 `CKQuerySubscription` + `notificationInfo`(알림 문구 포함) — **CloudKit이 APNs를 대신 쏴주므로 푸시 서버 불필요.** `Signal`은 silent push(`shouldSendContentAvailable`) + 핸드셰이크 중 2초 폴링 병행 (silent push는 전달 보장이 없음).
- 사이렌 원격 명령도 `Signal(kind: sirenCommand)`로 전달 — 별도 채널 불필요.

## 핵심 기술 레퍼런스 (실행 세션의 조사 시간 절약용)

| 기능 | API | 비고 |
|---|---|---|
| 전역 단축키 | Carbon `RegisterEventHotKey` | 샌드박스·접근성 권한 없이 동작. NSEvent 글로벌 모니터는 쓰지 말 것(권한 필요) |
| 입력 터치 감지 | `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)` | 유휴시간이 리셋되면 입력 발생. 권한 불필요, 1초 폴링 |
| 전원 분리 | `IOPSNotificationCreateRunLoopSource` | IOKit 전원 소스 변경 콜백 |
| 뚜껑 닫힘 | `NSWorkspace.willSleepNotification` + IORegistry `AppleClamshellState` | 닫힘 → 긴급 플러시 트리거 |
| 잠자기 방지 | `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)` | 디스플레이는 꺼지게 둔다 |
| 청크 작성 | `AVAssetWriter` — 청크당 파일 1개(독립 재생 가능 MP4)로 시작 | 청크 경계 프레임 드랍이 재생에서 거슬리면 `AVAssetWriterDelegate` fMP4 세그먼트(HLS형)로 전환. 이 결정은 M1 검증에서 확정 |
| WebRTC | SPM `stasel/WebRTC` 바이너리 | STUN은 `stun.l.google.com:19302` 등 공용. TURN 없음 — 연결 타임아웃(10초) 시 폴백 확정 |
| 폴백 재생 | `AVQueuePlayer` + 신규 청크 감지 폴링(3초) | 지연 목표 10~20초 |
| 알림 | `CKQuerySubscription` + `UNUserNotificationCenter` | 원격 알림 capability 필요 |
| 팁 자 | StoreKit 2 소모성 IAP 3종 (₩3,000/5,900/12,000) | 영수증 검증 서버 불필요 |

## 자동 사이렌 트리거 명세 (M7의 계약 — PRD M9·§8.10)

`MotionClassifier`가 프레임을 8×8 그리드로 나눠 블록별 차분을 계산:
- **부분 모션** (일부 블록만 변화) → `personMotion` 이벤트, 알림만
- **전역 모션** (전 블록이 동시에 대폭 변화 = 기기가 들려 움직임) → 후보 신호

자동 사이렌 발동 조건 (**전부** 충족):
1. 전역 모션이 **3초 이상 연속** 지속
2. 보강 신호 동반: 최근 10초 내 입력 터치 **또는** 최근 30초 내 전원 분리
3. 감시 시작 후 30초 경과 (사용자 본인의 정리 동작 오탐 방지)

조건 미달 → `deviceMotion` 이벤트로 iPhone 긴급 알림만. 발동 시 Mac에서 ⌃⌘C(+M8 이후 인증)로 3초 내 해제. 모든 임계값은 상수 파일 한 곳에 모아 튜닝 가능하게.

---

## 마일스톤 (각각 독립 검증 가능, 이 순서대로)

### M0 — 저장소 스캐폴드와 CloudKit 배선
**산출물:** 위 구조의 Xcode 프로젝트(맥·iOS 타겟 + CCTVKit 패키지), CloudKit 컨테이너·capability 설정, 두 앱이 각자 기기에서 빌드·실행되고 같은 컨테이너에 테스트 레코드 1개를 쓰고 읽음.
**검증:** Mac에서 쓴 레코드가 iPhone에서 읽힘 (같은 Apple ID). CloudKit Console에서 스키마 확인.
**리스크:** 컨테이너 권한·프로비저닝이 최초 난관 — 여기서 막히면 이후 전부 막히므로 M0에 격리.

### M1 — Mac 무화면 캡처 → 로컬 청크
**산출물:** `CaptureEngine`(720p/~800kbps H.264, 오디오 없음, 프리뷰 없음) + `ChunkWriter`(6초 독립 MP4) + `LocalRingBuffer`(용량 상한, 오래된 것 삭제). UI 없이 임시 CLI 플래그/테스트 하네스로 구동.
**검증:** 60초 실행 → 청크 10개 생성, 각각 QuickTime에서 단독 재생 가능, 청크 간 시간 공백 < 0.5초. 화면에 아무 창 없음 확인. **청크 경계 품질이 나쁘면 여기서 fMP4 세그먼트 방식으로 전환 결정.**
**테스트:** 링버퍼 정책(상한·삭제 순서)은 순수 로직으로 분리해 단위 테스트.

### M2 — 업로드 파이프라인 + 7일 보존
**산출물:** `CloudKitStore`, `ChunkUploader`(순차 업로드·지수 백오프 재시도·네트워크 단절 시 로컬 대기), `RetentionPolicy`(양 앱 실행 시 만료 삭제 sweep), 긴급 플러시 API(진행 중 청크 즉시 마감·업로드).
**검증:** 감시 5분 → CloudKit Console에 Session 1 + Chunk ~50. Wi-Fi 껐다 켜기 → 누락 없이 따라잡음. 시스템 날짜 조작 또는 `now` 주입으로 7일 경과 시뮬레이션 → sweep이 정확히 만료분만 삭제.
**테스트:** `RetentionPolicy`(경계: 정확히 7일, 6.99일, 진행 중 세션 보호) 단위 테스트. 업로더 재시도 로직은 CloudKit 목킹으로 단위 테스트.

### M3 — 메뉴바 앱 + 단축키 + 상태 머신
**산출물:** `MenuBarExtra` 앱(대기/감시 아이콘 2상태), `HotkeyManager`(⌃⌘C 토글, 충돌 시 팝오버에서 변경), `AppState` 상태 머신(idle↔armed↔siren), `SleepBlocker`, 팝오버(상태 텍스트·시작/종료·설정 3개: 단축키/화질/알림), 감시 시작 시 iCloud 여유 용량 확인(부족 시 화질 자동 하향 + 경고 — PRD §8.5).
**검증:** 다른 앱 전체화면 상태에서 ⌃⌘C → 감시 시작(창 없음, 아이콘만 변화), 다시 ⌃⌘C → 종료·세션 마감. 감시 중 30분 방치 → 시스템 잠들지 않음, 디스플레이는 꺼짐.
**테스트:** 상태 머신 전이(불법 전이 거부 포함) 단위 테스트.

### M4 — iOS 보관함 + 폴백 스트리밍
**산출물:** 세션 목록(날짜·길이·이벤트 뱃지), 세션 재생(`FallbackPlaylist` + `AVQueuePlayer` 이어재생), 스와이프 삭제, **동일 경로로 진행 중 세션의 준실시간 재생**(신규 청크 3초 폴링 = 폴백 모드 그 자체), "7일 뒤 자동 삭제" 문구.
**검증:** Mac 감시 중 iPhone에서 열기 → 15~25초 지연으로 현재 상황 재생. 종료된 세션 처음부터 재생. 청크 간 재생 끊김이 시청 가능 수준.
**테스트:** `FallbackPlaylist`(청크 정렬·결손 index 처리·라이브 엣지 계산) 단위 테스트.

### M5 — 이벤트 감지 + 푸시 알림
**산출물:** `EventDetector`(입력 터치·전원 분리·뚜껑 닫힘 → Event 레코드 + 긴급 플러시 연동), `MotionClassifier`(부분/전역 분류, 위 명세), iOS `CKQuerySubscription` 등록 + 알림 표시(탭 → 라이브 화면 딥링크).
**검증:** 감시 중 ① 키 입력 ② 전원 분리 ③ 뚜껑 닫기 ④ 카메라 앞 손 흔들기 ⑤ 노트북 들어올리기 — 각각 5초 내 iPhone 알림, type 정확. 뚜껑 닫기 직전 영상이 클라우드에 존재.
**테스트:** `MotionClassifier`를 녹화된 테스트 프레임 시퀀스(픽스처)로 단위 테스트 — 사람 접근/기기 이동/무변화 3케이스.

### M6 — WebRTC 실시간 라이브
**산출물:** `SignalingChannel`(CloudKit Signal 레코드 + silent push + 폴링), Mac `BroadcastSession`(캡처 프레임을 WebRTC 트랙에 공급 — M1 캡처와 카메라 1개 공유 주의), iOS `WebRTCReceiver` + `LiveView`(연결 상태·경과 시간 표시), 10초 타임아웃 → M4 폴백 자동 전환·"지연 모드" 표시.
**검증:** 같은 Wi-Fi에서 지연 1~2초. iPhone 셀룰러 전환 → P2P 성공 시 실시간, 실패 시 폴백 자동 전환(사용자 개입 없음). 라이브 시청 중에도 청크 업로드 계속됨.
**리스크(높음):** WebRTC×CloudKit 시그널링이 전체에서 가장 불확실. 이틀 이상 막히면 폴백 모드를 v1.0 라이브로 삼고 WebRTC를 v1.1로 미루는 것도 허용된 결정 — 단, 사용자에게 보고 후.

### M7 — 사이렌
**산출물:** `SirenController`(시스템 볼륨 최대 강제 + 경보음 루프 + 전체화면 "이 기기는 녹화·추적 중" 경고창 — 감시 중 유일하게 허용된 화면 표시), iOS 사이렌 버튼(길게 누르기 → Signal(sirenCommand)), 자동 트리거(위 명세), ⌃⌘C 해제.
**검증:** iPhone 길게 누르기 → Mac 사이렌 2초 내 발동. 노트북 들고 5초 걷기 → 자동 발동. 카메라 앞 손 흔들기·테이블 치기 → 발동 안 함(알림만). ⌃⌘C → 3초 내 해제·볼륨 복원.
**테스트:** 자동 트리거 판정(이벤트 시퀀스 → 발동 여부)을 순수 함수로 분리해 경계 케이스 단위 테스트 (2.9초 전역 모션 = 미발동 등).

### M8 — 온보딩·현지화·수익화 배선
**산출물:** Mac 온보딩 3단계(카메라 권한→iCloud 확인→iPhone 앱 QR), 한/영 String Catalog 전면 적용, 팁 자(StoreKit 2, Mac 팝오버·iOS 보관함 하단), `HouseBanner`(v1.0은 "Pro 곧 출시" 없이 숨김 처리 가능한 슬롯만), 감시 종료 인증 옵션(S3 — Touch ID/암호, 기본 꺼짐).
**검증:** 시스템 언어 한/영 전환 → 전 화면 번역 누락 0. 샌드박스 계정으로 팁 결제 완료. 신규 Mac에서 온보딩만 따라가면 첫 감시 성공.

### M9 — 배포 준비
**산출물:** 앱 아이콘·스크린샷, 프라이버시 라벨("데이터 수집 없음"), 심사 노트(도난 방지 목적 명시, PRD §10 근거), `web/` 랜딩 페이지(정적 1페이지: 데모 영상 슬롯·앱스토어 링크·한/영) Vercel 배포, TestFlight 빌드 2종.
**검증:** TestFlight 외부 테스터 설치 → 온보딩부터 사이렌까지 전 시나리오 통과. Lighthouse 성능 90+. 심사 제출 체크리스트 완료.

---

## 마일스톤 의존 관계

M0 → M1 → M2 → {M3, M4} → M5 → M6 → M7 → M8 → M9
(M3와 M4는 M2 뒤 병렬 가능. M6이 지연되면 M7~M9는 폴백 라이브 기준으로 선진행 가능.)

## 계획 자체의 미해결 지점 (실행 중 결정, 사용자 보고 필요)

1. **M1**: ~~독립 MP4 청크 vs fMP4 세그먼트~~ → **결정됨 (2026-07-05): 독립 MP4 청크로 진행.** 근거: CCTV 용도라 경계 미세 끊김 허용, 청크 단독 재생 가능성이 증거 가치에 더 중요. 단 M1 검증에서 청크 간 공백 >0.5초 또는 경계 프레임 깨짐 발견 시 fMP4 세그먼트 전환 재제안
2. **M6**: WebRTC 난항 시 v1.0을 폴백 라이브로 출시할지 — 사용자 결정 사항
3. **M8**: 종료 인증(S3)을 MVP에 넣을지 v1.1로 미룰지 — 구현 난이도 확인 후 제안
