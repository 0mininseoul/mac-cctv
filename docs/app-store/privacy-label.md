# App Privacy 라벨 — App Store Connect 입력 가이드

- 대상: **CCTV for Mac** (macOS 앱), **CCTV for Mac 컴패니언** (iOS 앱) — 두 앱 모두 동일하게 적용
- 결론: **"데이터 수집 없음" (Data Not Collected)** 선택
- 근거 문서: `docs/PRD.md` §9(운영비 0원 검증), §10(법적·심사 리스크 4번), 구현 계획 Global Constraints("개발자 서버·제3자 백엔드·광고/분석 SDK 절대 금지")

이 문서는 App Store Connect의 "App Privacy" 질문지에 실제로 입력할 값과, 심사관이 "정말 수집이 없는지" 의문을 가질 만한 지점에 대한 근거를 짝지어 정리한다. 두 앱 모두 동일한 아키텍처(사용자 본인 CloudKit private DB만 사용, 개발자 서버 0대)를 공유하므로 라벨도 동일해야 한다.

## App Store Connect에서 실제로 클릭할 경로

App Store Connect → 앱 선택 → App Privacy → "Get Started" → **"Do you or your third-party partners collect data from this app?"** → **No**를 선택하고 저장. 두 앱 각각에 대해 반복 (앱마다 별도 라벨).

## 왜 "수집 없음"이 성립하는가 — 핵심 논리

Apple의 App Privacy 정의에서 "수집(Collection)"은 **개발자(또는 개발자가 제공한 제3자)의 서버나 인프라로 데이터가 전송되어 개발자가 접근 가능한 상태**가 되는 것을 말한다. 이 앱은:

1. 개발자가 운영하는 서버가 **존재하지 않는다** (PRD §9 — 저장·시그널링·푸시 전부 CloudKit, STUN은 Google/Cloudflare 공용).
2. 영상·이벤트·세션 메타데이터는 전부 **사용자 본인의 iCloud 계정(CloudKit private database)**에만 저장된다. Private database는 정의상 그 계정 소유자 외에는 (개발자 포함) 아무도 접근할 수 없다. Apple은 iCloud(사용자 소유 저장소)에만 남는 데이터를 "제3자에게 공개되지 않는" 데이터로 취급하며, 개발자가 접근권이 없는 이상 이는 개발자의 "수집"에 해당하지 않는다 — Files/Notes 앱이 iCloud 동기화를 이유로 데이터 수집을 선언하지 않는 것과 같은 논리.
3. 분석·광고·크래시리포팅 SDK를 포함한 **제3자 SDK가 전혀 없다** (`stasel/WebRTC`는 미디어 전송 라이브러리이며 어떤 데이터도 외부로 전송하지 않음 — 계획 문서 Global Constraints 2026-07-05 명확화 참고).
4. 결제(팁 자)는 StoreKit 2로 처리되며 영수증 검증 서버가 없다 — 거래 데이터는 Apple이 자체적으로 보유·처리하고 개발자 코드는 거래 결과(성공/실패)만 받는다.

## 항목별 점검표 (App Store Connect 질문지 카테고리 순서)

| 카테고리 | 하위 항목 | 이 앱에서 발생하는가 | 선언 여부 |
|---|---|---|---|
| **Contact Info** | 이름/이메일/전화번호/주소 | 회원가입·로그인 없음 (PRD §6 "로그인 화면 없음") | 수집 안 함 |
| **Health & Fitness** | — | 해당 없음 | 수집 안 함 |
| **Financial Info** | 결제 정보 | StoreKit 2가 전담, 앱 코드는 카드 정보 접근 불가 | 수집 안 함 |
| **Location** | 위치(정밀/대략) | GPS 미사용 (PRD §5 Won't — Find My 영역) | 수집 안 함 |
| **Sensitive Info** | — | 해당 없음 | 수집 안 함 |
| **Contacts** | 주소록 | 접근하지 않음 | 수집 안 함 |
| **User Content** | **사진 또는 동영상** | 웹캠 영상이 존재하지만 **사용자 본인 CloudKit private DB에만 저장**, 개발자 서버 미경유·미접근 (§9) | 수집 안 함 |
| **User Content** | 오디오 데이터 | 오디오 캡처 자체가 MVP에서 금지됨 (PRD §10-2, Global Constraints) | 수집 안 함 (애초에 캡처하지 않음) |
| **Browsing / Search History** | — | 해당 없음 | 수집 안 함 |
| **Identifiers** | User ID / Device ID | CloudKit이 내부적으로 iCloud 계정 컨테이너를 사용하지만 이는 Apple의 시스템 식별자이며 개발자 서버로 전송되지 않음 | 수집 안 함 |
| **Purchases** | 구매 이력 | StoreKit 2 소모성 IAP(팁 자) — 개발자가 별도로 구매 이력을 저장·전송하지 않음 | 수집 안 함 |
| **Usage Data** | 앱 내 상호작용, 광고 데이터 등 | 분석 SDK 없음, 이벤트 로그는 CloudKit private DB(Event 레코드)에만 존재하며 감시 세션 자체의 알림 트리거 용도 — 사용자 본인 것 외 누구에게도 전송되지 않음 | 수집 안 함 |
| **Diagnostics** | 크래시 데이터, 성능 데이터 | 자체 크래시 리포팅 SDK 없음. Xcode Organizer의 크래시 로그는 OS 수준 "Share With App Developers" 사용자 옵트인 기능이며 앱 코드가 수집하는 것이 아님 | 수집 안 함 |
| **Other Data** | — | 해당 없음 | 수집 안 함 |

## 향후 라벨을 다시 검토해야 하는 경우 (v1.1+ 대비)

- PRD §14에 명시된 **하우스 배너(자체 Pro 업셀)**는 외부 광고 SDK가 아니라 자체 자산이므로 라벨에 영향 없음. 단, 향후 "제3자 광고 SDK 재검토" 조건이 실제로 발동하면 이 라벨은 반드시 갱신해야 한다.
- Pro 수익화(§14) 도입 시 결제 수단이 바뀌지 않는 한(App Store IAP 유지) 라벨 변경 불필요.
- CloudKit public database를 사용하게 되거나 개발자 서버가 추가되는 순간 이 문서 전체가 무효화된다 — 그런 변경은 Global Constraints 위반이므로 애초에 발생해서는 안 된다.

## 마케팅 활용

"영상은 당신의 iCloud에만 저장됩니다 — 개발자는 접근할 수 없습니다"는 App Privacy 라벨의 "데이터 수집 없음" 배지와 정확히 일치하는 주장이므로, 앱스토어 설명·랜딩 페이지(`web/`)·심사 노트에서 이 라벨을 근거로 그대로 인용해도 된다.
