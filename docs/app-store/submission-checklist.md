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

- [ ] **사람 작업**: App Privacy 질문지에서 "데이터 수집 없음" 선택 — 근거는 `docs/app-store/privacy-label.md` 전체 참고, 두 앱 각각 반복
- [ ] **사람 작업**: App Review Information → Notes에 `docs/app-store/review-notes.md`의 영문 블록 붙여넣기 (두 앱 각각)
- [ ] **사람 작업**: 카메라 사용 목적 문구는 이미 Info.plist에 반영되어 있음 (재확인만) — `NSCameraUsageDescription`

## 3. 앱 등록 — 중요: 두 개의 별도 App Store Connect 앱 레코드 필요

Mac 타겟과 iOS 타겟의 번들 ID를 분리했다 (`com.youngminpark.maccctv.mac` / `com.youngminpark.maccctv.ios` — 이전에는 실수로 동일했음, 이번 세션에서 수정·검증됨). 즉 **Universal Purchase 단일 앱이 아니라 App Store Connect에 앱을 2개 따로 등록**해야 한다:

- [ ] **사람 작업**: App Store Connect에서 "CCTV for Mac" (macOS, `com.youngminpark.maccctv.mac`) 앱 레코드 생성
- [ ] **사람 작업**: App Store Connect에서 "CCTV for Mac 컴패니언" (iOS, `com.youngminpark.maccctv.ios`) 앱 레코드 생성 — 표시명은 아직 미확정이면 "CCTV for Mac Companion" 등으로 결정 필요
- [ ] **사람 작업**: 두 앱 모두 App Store 카테고리 = Utilities (Mac Info.plist에 `LSApplicationCategoryType: public.app-category.utilities` 이미 반영됨 — iOS는 App Store Connect 등록 화면에서 직접 선택)
- [ ] **사람 작업**: 가격 = 무료 (PRD §11), 연령 등급 설문 작성

## 4. CloudKit 프로덕션 스키마 배포 — TestFlight 전 필수 선행 작업

- [ ] **사람 작업**: CloudKit Console에서 Development 스키마를 **Production으로 배포**. Release/TestFlight 빌드는 Production CloudKit 환경을 사용하므로(이번 세션에서 entitlements의 하드코딩된 `Development` 환경 키를 제거해 자동 전환되도록 수정함), 이 배포가 안 되어 있으면 TestFlight 빌드에서 CloudKit 호출이 전부 실패한다. **가장 먼저 확인할 항목.**

## 5. TestFlight 빌드 — 로컬 아카이브/익스포트 검증 완료

두 타겟 모두 Release 아카이브 → 익스포트까지 실제로 실행해 서명된 산출물을 만들어 확인했다. 재현 가능한 형태로 `script/archive_and_export.sh [mac|ios|all]`에 정리되어 있다:

```
script/archive_and_export.sh all
# → build/export/mac/CCTV for Mac.pkg   (Cloud Managed Apple Distribution 서명 확인됨)
# → build/export/ios/CCTV Companion.ipa (Cloud Managed Apple Distribution 서명 확인됨)
```

두 파일 모두 `pkgutil --check-signature` / `DistributionSummary.plist` 확인 결과 유효한 Apple Distribution 인증서로 서명된, 업로드 가능한 상태다.

`script/ExportOptions-{mac,ios}.plist`의 `destination`은 현재 `export`(로컬 저장)로 설정되어 있다. **실제 App Store Connect 업로드는 이 문서 기준으로는 아직 실행하지 않았다** — 업로드는 Apple 계정에 실제로 빌드를 생성하는, 되돌리기 어렵고 외부에 영향을 주는 작업이라 명시적 승인 없이 실행하지 않았다. 업로드 방법 중 택1:

- **권장(사람)**: Xcode → Window → Organizer → Archives에서 두 아카이브(`build/archives/*.xcarchive`, 또는 Xcode로 새로 아카이브)를 선택해 "Distribute App" → App Store Connect
- **또는**: Transporter.app에 위 `.pkg` / `.ipa` 드래그
- **또는(자동화, 승인 시)**: `script/ExportOptions-*.plist`의 `destination`을 `upload`로 바꾼 뒤 동일한 `xcodebuild -exportArchive` 명령을 다시 실행 — 이 경우 Xcode에 로그인된 Apple ID로 즉시 업로드된다

- [ ] **사람 작업 (또는 승인 후 자동화)**: 위 방법 중 하나로 두 빌드를 App Store Connect에 업로드
- [ ] **사람 작업**: TestFlight에서 두 빌드 각각 "내부 테스트" 그룹에 배정 → 외부 테스터 초대 전 베타 검토(Beta App Review) 통과 확인
- [ ] **사람 작업**: 외부 테스터로 설치 → 온보딩부터 사이렌까지 전 시나리오 수동 검증 (계획 M9 검증 기준)

### 버전 번호 참고

현재 `project.yml`은 `MARKETING_VERSION: 0.1.0`, `CURRENT_PROJECT_VERSION: 1`이다. 최초 정식 제출이라면 "1.0"으로 올리는 것이 관례적이지만, 이는 제품 의사결정이라 임의로 바꾸지 않았다 — 원하면 알려주면 반영한다.

## 6. 웹 랜딩 페이지

- [x] `web/index.html` — 정적 1페이지, 한/영 토글, Lighthouse Accessibility/Best Practices/SEO/Agentic Browsing 전부 100점, LCP 174ms/CLS 0.00
- [x] Vercel 배포 완료 — **https://mac-cctv.vercel.app** (`0minseouls-projects` 팀, Hobby 플랜). 라이브 URL에서도 Lighthouse 전 항목 100점 재확인
- [ ] **사람 작업**: 앱 승인 후 `web/index.html`의 "Coming Soon" App Store 배지 2곳(hero, 최종 CTA)을 실제 스토어 링크로 교체 후 `web/README.md`의 재배포 명령으로 반영

## 7. 최종 확인

- [ ] 위 항목 전부 완료 후 App Store Connect에서 "심사에 제출" 클릭 (두 앱 각각)
- [ ] 제출 후 `docs/HANDOFF.md`에 제출일과 심사 상태 추적 메모 추가 권장
