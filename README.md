# 칼캘 (CalCal) — 칼로리 캘린더

하루 섭취 칼로리와 탄·단·지를 캘린더로 기록하고, 목표 대비 진행 상황을 확인하는 Flutter 앱입니다.

## 주요 기능

- **식단 기록**: 날짜별 식사 기록, 칼로리·탄수화물·단백질·지방 대시보드
- **음식 검색**: 식약처 식품영양성분DB(공공데이터포털) 기반 검색 + 서버 캐시
- **영양성분표 스캔**: 카메라/앨범 사진을 Gemini로 인식해 영양성분 자동 입력 (일일 무료 한도)
- **목표 설정**: 온보딩에서 신체 정보·목표를 받아 칼로리/매크로 목표 자동 계산
- **알림**: 식사 기록 리마인더(로컬 알림), 매일 20:00 리마인더 푸시(FCM)
- **로그인**: Google · Apple · Kakao 소셜 로그인, 닉네임, 회원 탈퇴
- **기타**: 첫 실행 도움말 튜토리얼, 고객지원 문의, 약관/개인정보처리방침

> 광고(AdMob)와 인앱결제(구독)는 무료 출시를 위해 현재 비활성화되어 있습니다.
> 코드는 남아 있으며 `pubspec.yaml`의 주석을 해제하면 복구할 수 있습니다.

## 기술 스택

| 영역 | 사용 기술 |
|---|---|
| 앱 | Flutter (Dart ^3.11), iOS / Android |
| 인증 | Firebase Auth (Google, Apple, Kakao → Custom Token) |
| 데이터 | Cloud Firestore, Firebase App Check |
| 서버 | Cloud Functions for Firebase (Node.js 20) |
| 외부 API | 공공데이터포털 식품영양성분DB, Google Gemini, App Store Server API |
| 알림 | Firebase Cloud Messaging, flutter_local_notifications |

## 프로젝트 구조

```
lib/                  # Flutter 앱 소스
  main.dart           # 진입점 (Firebase/App Check/Kakao SDK 초기화)
  *_screen.dart       # 화면
  *_service.dart      # Auth, Firestore, 알림, 구독 등 서비스 계층
functions/            # Cloud Functions
  index.js            # 함수 정의 (아래 표 참고)
  certs/              # Apple 루트 인증서(공개 인증서)
assets/help/          # 도움말 튜토리얼 이미지
docs/                 # 개인정보처리방침, 이용약관, 운영 로그
firestore.rules       # Firestore 보안 규칙
```

### Cloud Functions

| 함수 | 역할 |
|---|---|
| `searchFood` | 식약처 API 음식 검색 (Firestore 캐시) |
| `parseNutritionLabel` | Gemini로 영양성분표 이미지 인식 |
| `kakaoSignIn` | 카카오 토큰 검증 후 Firebase Custom Token 발급 |
| `registerAppleRefreshToken` | Apple 로그인 refresh token 저장 (탈퇴 시 revoke용) |
| `updateNickname` | 닉네임 중복 확인 및 변경 |
| `deleteAccount` | 회원 탈퇴 (데이터 삭제 + Apple 토큰 revoke) |
| `sendDailyReminderPush` | 매일 20:00(KST) 리마인더 푸시 |
| `getOrCreateAppAccountToken` / `verifyPurchase` / `appStoreServerNotifications` | 인앱결제 구독 검증 (현재 비활성) |

## 개발 환경 설정

비밀값과 Firebase 설정 파일은 저장소에 포함되어 있지 않습니다. 아래 파일을 직접 준비해야 합니다.

### 1. Firebase 설정 파일

[FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)로 생성합니다.

```bash
flutterfire configure --project=cal-cal-app
```

생성되는 파일 (모두 `.gitignore` 대상):

- `lib/firebase_options.dart`
- `ios/Runner/GoogleService-Info.plist`
- `android/app/google-services.json`

### 2. Cloud Functions 환경 변수

```bash
cp functions/.env.example functions/.env
```

`functions/.env`에 값을 채웁니다.

| 변수 | 설명 |
|---|---|
| `FOOD_API_KEY` | 공공데이터포털 식품영양성분DB 인증키 (Encoding 키) |
| `GEMINI_API_KEY` | Google AI Studio API 키 |
| `APP_STORE_ENVIRONMENT` | `sandbox`(기본) 또는 `production` |

### 3. Secret Manager

`.p8` 비밀키 등은 `.env`가 아닌 Secret Manager로 관리합니다.

```bash
firebase functions:secrets:set APPLE_SIGNIN_KEY_ID
firebase functions:secrets:set APPLE_SIGNIN_PRIVATE_KEY
firebase functions:secrets:set APP_STORE_ISSUER_ID
firebase functions:secrets:set APP_STORE_KEY_ID
firebase functions:secrets:set APP_STORE_PRIVATE_KEY
```

### 4. Kakao

Kakao 네이티브 앱 키는 앱에 포함되는 공개 키이며 아래 세 곳의 값이 일치해야 합니다.

- `lib/main.dart`의 `_kakaoNativeAppKey`
- `ios/Runner/Info.plist`의 URL scheme `kakao{키}`
- `android/app/src/main/AndroidManifest.xml`의 scheme `kakao{키}`

Kakao Developers 콘솔 **[앱] → [플랫폼 키] → [네이티브 앱 키]**에 iOS 번들 ID와 Android 패키지명/키 해시를 등록해야 로그인이 동작합니다.

## 실행

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### Cloud Functions 배포

```bash
cd functions && npm install
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes
```

## 보안 메모

- API 키·비밀키는 절대 커밋하지 않습니다. `.env*`, `*.p8`, `*.p12`, `*.jks`, Firebase 설정 파일은 `.gitignore`로 차단되어 있습니다.
- 클라이언트는 외부 API 키를 갖지 않으며, 모든 외부 API 호출은 Cloud Functions를 거칩니다.
- Firestore 규칙상 사용자는 본인 데이터만 접근할 수 있고, 구독 상태·스캔 한도·닉네임 인덱스는 서버(Admin SDK)만 쓸 수 있습니다.

## 문서

- [개인정보처리방침](docs/privacy_policy.md)
- [이용약관](docs/terms_of_service.md)
