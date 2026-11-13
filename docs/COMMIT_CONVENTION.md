# 커밋 메시지 규칙

이 저장소의 모든 커밋은 [Conventional Commits 1.0.0](https://www.conventionalcommits.org/ko/v1.0.0/) 형식으로 씁니다.
사람이 쓰든 AI 도구(Claude Code, Cursor 등)가 쓰든 같은 규칙을 따릅니다.

## 형식

```
<type>(<scope>): <제목>

<본문>

<꼬리말>
```

- 첫 줄(헤더)은 꼭 써야 하고, 본문과 꼬리말은 필요할 때만 씁니다.
- 헤더와 본문, 본문과 꼬리말 사이에는 빈 줄을 하나 둡니다.

## type

| type | 언제 쓰나 |
|---|---|
| `feat` | 사용자가 느끼는 새 기능 |
| `fix` | 버그 수정, 보안 패치 |
| `refactor` | 동작은 그대로 두고 코드 구조만 바꿈 |
| `perf` | 성능 개선 |
| `style` | 포맷, 공백, 세미콜론 등 동작과 무관한 변경 |
| `test` | 테스트 추가·수정 |
| `docs` | 문서(README, docs/, 주석만 바꾼 경우) |
| `build` | 의존성, 빌드 설정(pubspec, Podfile, Gradle, Package.resolved) |
| `ci` | CI 설정 |
| `chore` | 그 밖의 잡일(설정 파일, 에셋 정리 등) |
| `revert` | 이전 커밋 되돌리기 |

헷갈리면 이렇게 고릅니다.
- 의존성을 올린 이유가 **보안·버그 수정**이면 `fix(deps)`, 그냥 최신화면 `build(deps)`를 씁니다.
- 사용자가 보기에 달라지는 게 있으면 `feat`/`fix`, 없으면 `refactor`/`chore`를 씁니다.

## scope (선택)

- 바뀐 영역을 소문자 영어로 짧게 적습니다. 여러 영역에 걸치면 생략합니다.
- 자주 쓰는 scope: `auth`, `onboarding`, `dashboard`, `food-search`, `scan`, `notification`, `firestore`, `functions`, `deps`, `ios`, `android`, `readme`

## 제목

- 한국어로, 무엇을 했는지 짧게 씁니다. 50자 안쪽을 권장합니다.
- 끝에 마침표를 찍지 않습니다.
- "~추가", "~수정", "~정리"처럼 명사형으로 끝냅니다.

## 본문 (선택)

- **왜** 바꿨는지, 그리고 제목만으로 알기 어려운 **무엇**을 적습니다.
- 문장은 "~한다" 체로 씁니다. 한 줄은 72자 안쪽으로 줄바꿈합니다.
- 항목이 여러 개면 `- `로 나열합니다.

## 꼬리말 (선택)

- 하위 호환이 깨지면 헤더의 type 뒤에 `!`를 붙이고(`feat(auth)!: ...`), 꼬리말에 `BREAKING CHANGE: <설명>`을 적습니다.
- 공동 작성자는 `Co-Authored-By: 이름 <이메일>` 형식으로 맨 끝에 둡니다.

## 커밋 단위

- 한 커밋에는 한 가지 목적만 담습니다. `fix`와 `feat`가 섞이면 커밋을 나눕니다.
- 관계없는 작업 중 변경은 따로 커밋합니다.

## 예시

```
fix(deps): Firestore eMudhra 인증서 보안 패치 적용

eMudhra 중간 CA 키 유출로 예전 Firestore iOS SDK가 위조 인증서를
믿을 수 있어, 패치가 들어간 FlutterFire 4.x 버전으로 올린다.
- firebase_core 4.15.2, cloud_firestore 6.10.2 (Firebase iOS SDK 12.19.3)
```

```
feat: Remote Config 기반 강제 업데이트 화면 추가
```

```
refactor(food-search): 리전 상수의 불필요한 null 처리 제거
```

```
docs(readme): 추천 대상과 기능 제목 정리
```
