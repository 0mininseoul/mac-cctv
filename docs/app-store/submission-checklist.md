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

## 3. 앱 등록 — 완료

Mac 타겟과 iOS 타겟의 번들 ID를 분리했다 (`com.youngminpark.maccctv.mac` / `com.youngminpark.maccctv.ios`). App Store Connect에 앱 2개가 등록되어 있다:

- [x] **"CCTV for Mac"** — macOS, `com.youngminpark.maccctv.mac`, SKU `maccctv-macos-20260705` (App Store Connect app id `6787679673`). 원래 번들 ID가 `.ios`로 잘못 연결되어 있었는데(과거 번들 ID 공유 버그의 흔적), 빌드가 아직 없는 상태라 App Store Connect에서 번들 ID 드롭다운만 바꿔 재사용함 — 앱 삭제·재생성 불필요했음
- [x] **"CCTV for Mac Companion"** — iOS, `com.youngminpark.maccctv.ios`, SKU `maccctv-ios-20260706` (app id `6787729272`)
- [ ] **사람 작업**: 두 앱 모두 App Store 카테고리 = Utilities (Mac Info.plist에 `LSApplicationCategoryType: public.app-category.utilities` 이미 반영됨 — iOS는 App Store Connect 등록 화면에서 직접 선택)
- [ ] **사람 작업**: 가격 = 무료 (PRD §11), 연령 등급 설문 작성

## 4. CloudKit 프로덕션 스키마 배포 — 완료

- [x] **사람 작업 완료**: CloudKit Console에서 Production 스키마 배포함

## 5. TestFlight 빌드 — 업로드 완료

두 타겟 모두 Release 아카이브 → 익스포트 → 업로드까지 실행 완료. 재현 가능한 아카이브/익스포트 명령은 `script/archive_and_export.sh [mac|ios|all]`.

업로드는 `xcodebuild -exportArchive -destination upload`가 두 가지 이유로 막혀서 (① 자동 서명 세션은 업로드 API 인증까지 못 미침 — `IDEDistribution.DistributionCredentialedProviderLocatorError`, ② App Store Connect API 키(`~/.appstoreconnect/private_keys/AuthKey_TMC3PCHDCF.p8`, Key ID `TMC3PCHDCF`)는 인증서를 새로 발급하는 권한이 없어 iOS Cloud 서명이 거부됨), 대신 **이미 서명까지 끝난 `.pkg`/`.ipa`를 `xcrun altool --upload-app`으로 업로드**했다 (서명과 업로드를 분리 — 서명은 앞서 `-allowProvisioningUpdates`로 이미 끝나 있었고, altool은 인증서 발급 권한 없이 업로드 API 권한만 있으면 됨):

```
xcrun altool --upload-app -f "build/export/mac/CCTV for Mac.pkg" -t macos \
  --apiKey TMC3PCHDCF --apiIssuer 0d693e18-2317-4107-8b26-26afd98e64ae
# Delivery UUID: 8871917e-5464-4fed-b897-0a99b7fcbc86 — build 1, processingState VALID

xcrun altool --upload-app -f "build/export/ios/CCTV Companion.ipa" -t ios \
  --apiKey TMC3PCHDCF --apiIssuer 0d693e18-2317-4107-8b26-26afd98e64ae
# Delivery UUID: c907cc59-3789-4af7-951e-60675b06049b — build 1, processingState VALID
# (first two iOS delivery attempts failed silently on Apple's backend — error 90683,
#  missing NSCameraUsageDescription; WebRTC.framework references camera APIs even
#  though this app never calls them. Fixed in apps/ios/CCTVCompanion/Support/Info.plist.)
```

- [x] 두 빌드 App Store Connect에 업로드 완료, 둘 다 `processingState: VALID`
- [x] **사람 작업 완료**: TestFlight에서 두 빌드 각각 "내부 테스트" 그룹에 배정함
- [ ] **사람 작업**: 외부 테스터 초대 전 베타 검토(Beta App Review) 통과 확인 — Export Compliance 질문(암호화 사용 여부)이 뜨면 이 앱은 표준 HTTPS/TLS 외 자체 암호화가 없으므로 "표준 암호화만 사용"으로 응답
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
