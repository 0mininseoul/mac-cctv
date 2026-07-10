# Build 10 — 필드 테스트(build 9) 피드백 8건 수정 설계

작성일: 2026-07-10
브랜치: `feat/m0-cloudkit-scaffold`
선행: build 9(f6cc128) 필드 테스트 결과

## 배경

사용자가 build 9를 실기기(이 개발 Mac + 페어링된 iPhone)에서 테스트하고 8건을 보고.
각 항목은 코드 조사 + 이 Mac의 실제 런타임 진단 로그/청크 파일로 근본 원인을 확인했다.
App Store 연령 등급은 사용자가 이미 12+로 상향 완료.

## 이슈별 근본 원인 + 해결 방향

### ① 카메라가 단축키 후 ~3초 뒤 켜짐
- **원인**: `CaptureEngine.start()`가 단축키 경로에서 권한확인 → `configureIfNeeded()`(디바이스 탐색·입력/출력 추가) → `session.startRunning()`을 순차 실행. 대부분은 `startRunning()` 하드웨어 예열(~1.5–2.5초), 세션 구성이 ~0.5초 추가.
- **결정(사용자)**: 사전 예열은 하지 않음(프라이버시 유지). **설정만 앞당김**.
- **해결**: 세션 구성(`configureIfNeeded` + 카메라 권한 사전 확인)을 무장 준비/컨트롤러 초기화 시점으로 앞당겨, 단축키 땐 `startRunning()`만 남긴다. 카메라 초록불은 여전히 "무장할 때만" 켜진다. ~3초 → ~2초.

### ② 앱이 꺼진 상태에서 푸시 안 옴 (회귀)
- **원인(확정)**: build 8까지는 초기 빌드에서 만들어져 서버에 남아있던 stale 제너릭 구독 `event-created-v1`(전체 이벤트·옛 문구)이 푸시를 실어나르고 있었다. build 9(task #43)가 그 구독을 삭제하고 per-type v2로 교체했는데, 이 "삭제 후 재생성"이 (a) 모든 에러를 `try?`로 삼키고 (b) 멱등성·검증·재시도가 없어, 삭제만 성공하고 생성이 실패하면 구독이 0개가 되어 푸시가 전멸한다.
- **비원인 확인**: `aps-environment=development`이지만 export가 `app-store-connect`+automatic이라 Xcode가 production으로 재작성 → 빌드 6·8에서 푸시가 왔던 이유. 회귀 아님. (그래도 소스 값을 production으로 바꿔 belt-and-suspenders.)
- **해결(구현됨)**:
  1. 구독 부트스트랩을 **비파괴·멱등**으로 재작성(`EventNotificationBootstrap.synchronizeSubscriptions`): `CloudKitStore.fetchExistingSubscriptionIDs()`(=`database.allSubscriptions()`)로 기존 조회 → 필요한 구독(signal, escalation, per-type v2)을 **먼저 보장(있으면 skip, 없으면 생성)** → 전부 확인된 뒤에만 구식(`event-created-v1`, `*-v1`) 삭제. 어느 시점에도 구독 공백이 없다.
  2. iOS 앱그룹에 **구독 결과 진단 로그**(`m-notif-result.txt`: `M11_SUBS_EXISTING/SKIP/CREATED/CREATE_FAILED/DELETED/KEEP_LEGACY`) 기록 → 다음 빌드에서 Download Container로 확정.
- **제외(재검토 후)**:
  - `aps-environment`를 production으로 바꾸지 않음: export(`app-store-connect`+automatic)가 이미 production으로 재작성하며(빌드 6·8 푸시 도착이 증거), 소스를 바꾸면 로컬 Debug 디바이스 실행이 오히려 깨진다.
  - `UIBackgroundModes: remote-notification` 추가하지 않음: 앱에 background silent 푸시 핸들러가 없어 미사용 capability일 뿐이고(심사 리스크), 꺼진 앱의 **가시성 알림**(이번 이슈)은 background mode 없이도 시스템이 표시한다.

### ③ WebRTC 연결 로딩 표시가 너무 작음
- **원인**: 라이브 연결 상태를 좌측 하단 작은 caption 칩으로만 표시(`SessionPlaybackView` 33–40행).
- **해결**: 라이브·미연결 상태일 때 영상 위 **중앙 대형 오버레이**(ProgressView 스피너 + "실시간 연결 중…" 큰 문구). 연결 완료되면 사라짐.

### ④ 사이렌 버튼 너무 큼 + ⑤ 원격 종료 버튼
- **원인**: 하단 컨트롤이 세로 스택(48pt 버튼 + 힌트 + 상태문구)이라 세로 공간을 크게 차지.
- **해결**:
  - 하단 컨트롤을 **가로 한 줄**로 재구성: 얇은 사이렌 홀드버튼 + 우측에 **종료 버튼**. 두께 약 1/3로 축소, 힌트는 짧은 caption 한 줄.
  - 원격 종료: 신규 `SignalKind.endSession`(iOS→Mac) 추가. Mac `BroadcastSession`이 우선순위 0으로 수신 → `SurveillanceController.stopSurveillance` 호출. iOS는 오작동 방지 확인 다이얼로그 1회 후 전송. 종료되면 ⑧ 경로로 재생 전환.

### ⑥ WebRTC 여전히 ~10초
- **원인**: CloudKit 시그널링 순차 왕복 + 양쪽 ICE gathering `.complete` 대기(각 최대 2.5초).
- **해결**: 같은 WiFi에선 host 후보만으로 즉시 연결되므로 **`.complete` 완주를 기다리지 않고** 후보 준비 즉시(또는 ~0.4초 그레이스) `localDescription` 전송. iOS 시그널 폴링 500→250ms. 기대 ~10초 → ~4–5초.

### ⑦ 사이렌 공포짤이 전체화면을 못 채움
- **원인**: 현재 VStack — 이미지 상단 62% + 하단 검은 밴드에 문구.
- **해결(요구사항)**: ZStack으로 `Image.scaledToFill().ignoresSafeArea()`가 **전체화면 꽉 채움**, 그 위 **하단 정렬 오버레이 문구**(가독성 위해 하단 어두운 그라디언트 스크림) + 폰트 확대. macOS 창(`SirenWarningView`)에 적용.

### ⑧ 세션 종료 시 자동으로 정상 재생 — 조치 불필요(확인됨)
- 사용자가 build 9 실기기 테스트에서 **이미 정상 동작 확인**. build 9의 컴포지션+큐 폴백 + `endedRemotely` 전환이 제대로 작동함.
- **재생 경로는 건드리지 않는다.** 단, 원격 종료(⑤)로 세션이 끝날 때도 동일하게 replay로 전환되는지만 확인(⑤ 구현 시 endedRemotely 흐름 재사용).

## 신규/변경 인터페이스 요약
- `SignalKind.endSession` 추가(iOS→Mac, 우선순위 0). 스키마 배포 불필요(기존 Signal `kind` 컬럼 재사용).
- iOS `NotificationSubscriptionManager`(신규 또는 CloudKitStore 확장): 멱등 보장 + 진단.
- iOS Info.plist `UIBackgroundModes`, iOS/mac entitlements `aps-environment=production`.
- 신규 로컬라이즈 키: 연결 중 오버레이 문구, 종료 버튼/확인 다이얼로그 문구.

## 검증
1. `swift test`(CCTVKit) 전체 통과 + endSession/구독 관련 신규 케이스.
2. `xcodegen generate` → `xcodebuild -scheme MacCCTV build`, `-scheme CCTVCompanion build` 양쪽 성공.
3. build 10 패키징(아카이브/익스포트/TestFlight 업로드) → 온디바이스 재검증. 특히 ② 푸시(꺼진 앱), ⑤ 원격 종료, ⑥ 연결 시간. ② 재현 시 iPhone `m-notif-result.txt` 확인.

## 스코프 밖
- 실시간 시그널링 백엔드 도입(무서버 원칙 유지) — ⑥은 무서버 범위 내 최적화만.
- 카메라 사전 예열(사용자가 프라이버시 이유로 배제).
