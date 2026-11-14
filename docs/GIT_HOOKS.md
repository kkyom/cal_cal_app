# Git 훅

커밋 전에 CI와 같은 검사를 로컬에서 먼저 돌리는 `pre-commit` 훅이 [`.githooks/`](../.githooks)에 있습니다.

## 설치

저장소를 클론한 뒤 한 번만 실행합니다.

```bash
git config core.hooksPath .githooks
```

## 무엇을 검사하나

스테이징된 파일에 따라 필요한 검사만 돌립니다.

| 바뀐 파일 | 검사 |
|---|---|
| `*.dart`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` | `flutter analyze lib test`, `flutter test` |
| `functions/**/*.js`, `functions/**/*.json` | `node --check`로 문법 검사, `index.js` 로드 |

- 검사는 스테이징된 내용이 아니라 작업 트리 기준으로 돕니다. 일부만 스테이징했다면 결과가 커밋 내용과 다를 수 있습니다.
- `lib/firebase_options.dart`가 없으면 Flutter 검사를 하기 전에 멈춥니다. `flutterfire configure`로 만들어 주세요.
- `functions/node_modules`가 없으면 모듈 로드 검사만 건너뜁니다.

## 건너뛰기

급할 때만 `git commit --no-verify`를 씁니다. 같은 검사가 CI에서 다시 돌아갑니다.
