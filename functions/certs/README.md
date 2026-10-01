# 애플 루트 인증서

`SignedDataVerifier`(functions/index.js의 `createSignedDataVerifier`)가 실행 시
이 폴더의 `.cer` 파일들을 읽어 신뢰 루트로 사용합니다. 없으면 verifyPurchase /
appStoreServerNotifications 둘 다 명확한 에러를 던지며 실패합니다.

## 받아야 할 파일

https://www.apple.com/certificateauthority/ 에서 아래를 다운로드해 이 폴더에 그대로 넣으세요.

- Apple Root CA - G3 Root (`AppleRootCA-G3.cer`)

## 왜 커밋해도 되는가

이 파일들은 애플이 공개 배포하는 **공개 인증서**로, 비밀키가 아닙니다.
(비밀키인 `.p8`는 반드시 Secret Manager로만 관리하고 여기 두지 마세요 —
`functions/.gitignore`에서 `*.p8`을 이미 차단하고 있습니다.)
