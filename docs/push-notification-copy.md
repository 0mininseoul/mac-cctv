# 푸시 알림 문구

이 문구들은 iOS 앱의 `apps/ios/CCTVCompanion/Support/Localizable.xcstrings`에 저장되어 있고,
Apple의 원격 알림 시스템(APNs)이 알림을 표시할 때 이 파일에서 직접 값을 읽어온다.
그래서 이 문구를 **다른 별도 파일로 완전히 분리할 수는 없다** — 값이 실제로 반영되려면
반드시 `Localizable.xcstrings` 안에 있어야 한다. 이 파일은 그 값들을 한눈에 모아 보여주는
참고용 목록이다.

## 수정하는 방법

1. Xcode에서 `apps/ios/CCTVCompanion/Support/Localizable.xcstrings`를 더블클릭해서 연다
   (JSON이 아니라 표 형태 에디터가 열린다).
2. 검색창에 `notification_body`를 입력해서 아래 항목들만 필터링한다.
3. 한국어(ko)/영어(en) 칸을 직접 수정하고 저장하면 끝 — 빌드/재배포만 하면 반영된다.
4. 이 문서도 값이 바뀌면 같이 업데이트해두면 나중에 훑어보기 편하다 (선택사항, 자동 동기화 아님).

## 이벤트 감지 알림 (타입별 개별 문구)

| 이벤트 | 키 | 한국어 | 영어 |
|---|---|---|---|
| 사람 감지 | `event_personMotion_notification_body` | 사람이 감지됐어요! | A person was detected! |
| 터치/키보드 입력 | `event_inputTouch_notification_body` | 누군가 맥북을 두드리고 있어요 | Someone is touching your Mac |
| 전원 분리 | `event_powerDisconnect_notification_body` | 누군가가 충전기를 뽑았어요 | Someone unplugged the charger |
| 기기 흔들림/이동 | `event_deviceMotion_notification_body` | 누군가 맥북을 움직였어요 | Someone moved your Mac |
| 노트북 덮개 닫힘 | `event_lidClose_notification_body` | 누군가 맥북 덮개를 닫았어요 | Someone closed the lid |

## 그 외 알림

| 상황 | 키 | 한국어 | 영어 |
|---|---|---|---|
| 위 5종 외 나머지 이벤트 (sirenAuto/sirenManual/escalationDismissed 등, 범용 문구) | `event_notification_body_format` | 이벤트 감지: %@ | Event detected: %@ |
| 단계적 에스컬레이션 경고 (Dismiss 액션 포함) | `escalation_notification_body` | Mac이 들렸을 수 있습니다. 확인하거나 취소를 눌러 경보를 중지하세요. | A Mac may have been picked up. Tap to view, or Dismiss to cancel the alarm. |

## 새 이벤트 타입에 개별 문구를 추가하고 싶다면

`Packages/CCTVKit/Sources/CCTVKit/Cloud/CloudKitStore.swift`의 `friendlyEventTypes` 배열에
타입을 추가하고, `Localizable.xcstrings`에 `event_<타입명>_notification_body` 키를 만들면
`EventNotificationBootstrap.start()`가 앱 실행 시 자동으로 그 타입 전용 구독을 등록한다.
