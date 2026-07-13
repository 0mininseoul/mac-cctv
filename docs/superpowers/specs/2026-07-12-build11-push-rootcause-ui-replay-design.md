# Build 11 — 푸시 근본원인 확정 + 라이브 컨트롤 재설계 + 재생 속도 + 사이렌 텍스트

작성일: 2026-07-12
브랜치: `feat/m0-cloudkit-scaffold`
선행: build 10 필드 테스트 결과

## 배경

build 10 실기기 테스트에서 5건 제보. 핵심은 **푸시가 build 10에서도 여전히 전멸** — build 10의 "멱등 구독 부트스트랩" 수정이 문제를 못 잡았다는 뜻이라 systematic-debugging으로 재조사. UI 3건은 frontend-design으로 처리.

## 이슈별 근본 원인 + 해결

### ② 푸시 전멸 — 진짜 근본 원인 확정: `Event.type`이 Production 스키마에서 queryable 아님

**증거 (코드 + git, 로그 없이 확정):**
- 최초 `event-created-v1` 구독(build ≤6)은 `NSPredicate(value: true)` — 전체 매치. 어떤 필드도 queryable일 필요 없음 → build 8까지 푸시를 실어나른 유일한 구독.
- signal 구독(macState 동기화)도 `value:true` → Production에서 정상 발화(그래서 실시간 상태 동기화는 늘 잘 됨).
- per-type v2 / escalation / catch-all 구독은 `type == X` predicate → **`Event.type` 필드가 Production 스키마에서 Queryable로 인덱싱돼 있어야** 저장·발화됨.
- 앱의 Event **쿼리**는 `session`(레퍼런스)·`value:true`로만 함 — `type`으로 쿼리한 적이 없어 `type`은 Production에서 queryable로 설정된 적이 없음. `escalationDeadline` 때와 **같은 계열의 Production 스키마 한계.**
- build 9가 유일하게 발화하던 `value:true` 구독(`event-created-v1`)을 삭제 → 전멸. build 10은 그걸 복구하지 않고 `type==X` per-type만 시도(실패) → 여전히 전멸.

**해결 (사용자 선택: 친근 per-type 문구 유지):**
1. **사람 작업 1회**: CloudKit Dashboard에서 `Event.type` 필드를 **Queryable**로 표시하고 Production 배포. 그러면 per-type/escalation 구독이 정상 저장·발화.
2. 코드: per-type 구독 ID를 v2→**v3**로 bump(깨진 v2가 서버에 남아있을 경우까지 클린 재생성). obsolete 목록에 v1·v2 추가. build 10의 멱등·비파괴 부트스트랩 + `m-notif-result.txt` 진단(`M11_SUBS_CREATED/SKIP/CREATE_FAILED`) 유지 → build 11 자체가 성공/실패를 자가 진단.
3. 순서 주의: Dashboard 배포 → 앱 재실행(부트스트랩이 재실행돼 v3 생성). (부트스트랩은 앱 실행 시점에만 돎.)

### ⑤ 종료 세션 재생 11초 — 매번 전체 재다운로드

**원인**: `fetchChunksBySessionReference`가 `desiredKeys`에 `video`(CKAsset)를 포함 → 청크 목록을 가져올 때 **모든 청크 MP4를 CloudKit에서 통째로 다운로드**한 뒤에야 재생. 로컬 캐시가 있어도 fetch가 asset을 재요청. + 컴포지션 빌드가 청크별 순차 로딩(~1-2s 추가).

**해결**:
- `CloudKitStore.fetchChunkMetadata`(신규): `video` 제외한 빠른 메타데이터 쿼리. `ChunkAssetCache.cachedFileURL`(신규)로 이미 캐시된 청크는 URL 즉시 확보.
- ViewModel `refreshReplay`: 메타데이터 우선 → **캐시 안 된 청크만** `fetchChunks(ids:)`로 다운로드 → 병합. 라이브로 봤거나 재열람한 세션은 다운로드 0 → 사실상 즉시 재생.
- `loadReplayComposition`: 청크별 duration 로딩을 TaskGroup으로 **병렬화**(Sendable한 URL·CMTime만 경계 통과, 컴포지션 mutation은 순차 유지).

### ③④ 라이브 하단 버튼 어색 — 위계 없는 두 빨간 버튼

**원인**: 사이렌(빨강 hold)과 종료(빨강 tap)가 같은 빨강·비슷한 크기로 경쟁.

**해결(frontend-design)**: `LiveControlBar` 재설계 — 사이렌 = 유일한 빨강 긴급 액션(전체폭 hold, 그라디언트 채움 + 완료 시 햅틱), 종료 = 중립 회색 컴팩트 secondary(아이콘+라벨 세로, 74pt 폭). 통일된 52pt 높이·14pt 라운드. 에스컬레이션은 별도 주황 스트립. 컴포넌트 분리(`SirenHoldButton`/`SilenceSirenButton`/`EndSessionButton`/`EscalationCountdownStrip`).

### ⑥ 종료 확인 모달이 화면 상단에 어색 — 액션시트

**원인**: `.confirmationDialog`는 iPhone에서 하단 액션시트. 사용자는 중앙 모달을 원함.

**해결**: `.alert`로 교체 → 화면 중앙 정렬 모달.

### ⑦ 사이렌 텍스트 아직 작음

**해결**: Mac `SirenWarningView` 자막을 화면 높이 비례(`height*0.11`, 최대 160pt)로 확대(기존 고정 68pt), 아이콘 72→84pt.

## 비고 — WebRTC 8초

build 10에서 ~10s→8s로 개선됨(`.gatherOnce` + 후보 즉시전송). 추가 최적화는 별도 이슈로 보류(무서버 CloudKit 시그널링 왕복이 남은 병목).

## 검증
1. `swift test`(CCTVKit) 58 통과.
2. `xcodegen generate` + Mac/iOS 두 타겟 빌드 성공.
3. build 11 패키징 → 온디바이스: **Dashboard 배포 후** 꺼진 앱 푸시 도착(안 오면 `m-notif-result.txt`의 `M11_SUBS_*` 확인), 라이브 컨트롤/모달/사이렌 텍스트, 재생 속도(특히 재열람 즉시성).

## 사람 작업 (필수)
1. **CloudKit Dashboard**: Event 레코드 타입의 `type` 필드를 Queryable로 표시 → Deploy Schema Changes to Production. (클릭 순서는 체크리스트 build 11 섹션 참고.)
2. Dashboard 배포 후 build 11 설치·재실행 → 재검증.
