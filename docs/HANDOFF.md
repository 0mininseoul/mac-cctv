# 코딩 세션 핸드오프 — Mac CCTV

이 문서는 코드 작성 세션(새 Claude Code 세션 등)에 그대로 전달하는 용도다. 기획·계획 세션(Fable)에서는 코드를 작성하지 않기로 했으므로, 구현은 아래 프롬프트로 시작한다.

## 필요 문서 (모두 이 레포에 있음)

1. `docs/PRD.md` — 제품 요구사항 v5. **모든 제품 결정이 확정된 상태** (미확정 항목 없음)
2. `docs/superpowers/plans/2026-07-04-mac-cctv-implementation-plan.md` — 마일스톤 M0~M9 구현 계획

## 시작 프롬프트 (코딩 세션에 붙여넣기)

```
docs/PRD.md 와 docs/superpowers/plans/2026-07-04-mac-cctv-implementation-plan.md 를 읽고
Mac CCTV 구현을 시작해줘.

규칙:
- 계획의 마일스톤 순서(M0부터)를 따르고, 각 마일스톤의 "검증" 기준을 통과시킨 뒤 다음으로 넘어가.
  검증 결과(실제 실행/재생 확인)를 나에게 보고하고 넘어가.
- PRD의 제품 결정(단축키 ⌃⌘C, 오디오 금지, private DB만, 제3자 SDK 금지, 무화면 원칙,
  자동 사이렌 보수적 트리거 등)은 재논의하지 말고 그대로 구현해. 계획과 PRD가 충돌하면 PRD 우선.
- 순수 로직(RetentionPolicy, FallbackPlaylist, MotionClassifier 판정, 상태 머신)은 TDD로:
  테스트 먼저, 실패 확인, 구현, 통과 확인, 커밋. 하드웨어 의존부는 계획에 적힌 수동 검증 절차로.
- 커밋은 작은 단위로 자주. conventional commits.
- 계획 문서의 "미해결 지점" 3개(M1 청크 포맷, M6 WebRTC 난항 시 폴백 출시, M8 종료 인증 포함 여부)에
  도달하면 구현을 멈추고 나에게 결정을 물어봐.
- Apple Developer Program 계정은 있음. Xcode 서명·CloudKit 컨테이너 설정에서 팀 선택이 필요하면 알려줘.

M0(저장소 스캐폴드 + CloudKit 배선)부터 시작해.
```

## 이어하기 프롬프트 (세션이 끊겼을 때)

```
docs/PRD.md 와 docs/superpowers/plans/2026-07-04-mac-cctv-implementation-plan.md 를 읽어줘.
git log 로 진행 상황을 파악한 뒤, 마지막으로 완료된 마일스톤의 검증 기준이 아직 통과하는지
빠르게 확인하고, 다음 마일스톤을 이어서 진행해줘. 규칙은 시작 프롬프트와 동일:
마일스톤 검증 통과 → 보고 → 다음, PRD 결정 재논의 금지, 순수 로직 TDD, 잦은 커밋,
미해결 지점 3개는 나에게 질문.
```

## 사람이 직접 해야 하는 일 (Claude가 못 하는 것)

- Xcode에서 Apple Developer 팀 로그인·서명 설정 (최초 1회)
- CloudKit Console에서 스키마 프로덕션 배포 (M9 직전)
- 실기기 테스트: iPhone 셀룰러망 폴백(M6), 실제 카페에서 사이렌 리허설(M7)
- App Store Connect 앱 등록, 심사 제출, TestFlight 테스터 초대 (M9)
- Vercel 계정 연결 (M9)
