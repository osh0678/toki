# Toki 보안 검토

목표는 하나입니다. **API 키나 OAuth 토큰이 Toki 를 통해 유출될 수 없게 만든다.**
검토 시점: 2026-07-30 / 대상: 이 저장소 전체.

## 1. 자격증명이 실제로 어디 있는지

Toki 가 다루는 두 도구의 자격증명 위치를 먼저 확인했습니다.

| 자격증명 | 실제 위치 | Toki 의 접근 |
|---|---|---|
| Codex OAuth 토큰 | `~/.codex/auth.json` (권한 `-rw-------`) | **없음.** 코드에 이 경로가 등장하지 않음 |
| Codex 설정 | `~/.codex/config.toml` (권한 `-rw-------`) | **없음** |
| Claude Code 토큰 | macOS Keychain 항목 `Claude Code-credentials` | **없음.** Security.framework 미링크 |
| Anthropic API 키 | 환경변수 / `~/.config/anthropic/` 프로필 | **없음.** 환경변수를 읽지 않음 |

즉 Toki 는 자격증명을 **획득할 수단 자체가 없습니다.** 탈취 방지를 "잘 보관한다"로
푸는 대신 "애초에 만지지 않는다"로 풀었습니다.

## 2. Toki 가 읽는 것 — 전부

읽기 전용 접근이며 경로는 모두 코드에 하드코딩되어 있습니다.

| 경로 | 추출하는 필드 | 목적 |
|---|---|---|
| `~/.claude/projects/*/*.jsonl` | `type`, `timestamp`, `requestId`/`uuid`, `message.model`, `message.usage.*` 의 토큰 수치 | 5시간/주간 창 집계 |
| `~/.claude.json` | `oauthAccount.organizationRateLimitTier` 또는 `userRateLimitTier` **단 1개** | 플랜 배지("Max 5x") |
| `~/.codex/sessions/**/*.jsonl` | `payload.rate_limits.*`, `payload.info.total_token_usage.total_tokens` | 공식 사용률 · 토큰 수 |
| `~/.config/toki/config.json` | 정수·불리언 몇 개 | 사용자 설정 (유일한 **쓰기** 대상) |
| `claude -p "/usage" --output-format json` | stdout 의 `result` 문자열에서 `N% used` 와 초기화 시각 | Claude 공식 사용률 |

### `claude` CLI 호출 — 왜 이게 더 안전한가

Claude 공식 수치를 얻는 다른 방법은 Keychain 의 OAuth 토큰으로 비공개 엔드포인트를
직접 부르는 것뿐입니다. 그러면 Toki 가 살아있는 토큰을 들고 네트워크를 열어야 하므로
아래 G1·G2 가 동시에 깨집니다. CLI 에 위임하면 **인증과 통신이 CLI 프로세스 안에서**
일어나고 Toki 는 stdout 의 숫자만 읽으므로 두 보증이 그대로 유지됩니다.

대신 서브프로세스 실행 1건이 생기고, 그 지점은 다음과 같이 좁혀두었습니다
(`ClaudeOfficialUsage.swift`):

- 실행 파일은 **절대경로 허용목록**에서만 찾습니다 — `PATH` 나 환경변수, 설정 파일로
  다른 바이너리를 가리킬 수 없습니다.
- 인자는 컴파일 타임 리터럴(`-p`, `/usage`, `--output-format`, `json`)이라 호출자
  입력이 섞일 여지가 없습니다.
- **셸을 경유하지 않습니다.** 인용·이스케이프 문제가 원천적으로 없습니다.
- stdin 은 `/dev/null`, stdout 은 256KB 로 상한, 30초 후 강제 종료합니다.

### 명시적으로 읽지 않는 것

- 세션 로그의 **프롬프트 본문, 도구 출력, 파일 내용** — provider 는 위 숫자 필드만
  꺼내고 나머지는 파싱 결과에서 버립니다. 바이트 사전 필터(`cache_read_input_tokens`,
  `rate_limits`)로 해당 줄만 골라 JSON 파싱합니다.
- `~/.claude.json` 의 PII — 이 파일에는 `emailAddress`, `accountUuid`,
  `organizationUuid`, `displayName`, `organizationName` 등이 있지만 Toki 는
  **rate-limit tier 문자열 하나만** 읽고 그것도 `"Max 5x"` 같은 라벨로 변환해 씁니다.
  원본 문자열은 UI 에 도달하지 않습니다.
- Keychain, 환경변수, `.netrc`, SSH 키 — 전부 미접근.

## 3. 보증 목록

| # | 보증 | 근거 |
|---|---|---|
| G1 | 네트워크 송수신 없음 | `URLSession`/`Network`/`CFStream` 미사용, `CFNetwork`·`Network.framework` 미링크, 네트워크 entitlement 없음 |
| G2 | Keychain 접근 없음 | `SecItem*`/`SecKeychain*` 미사용, `Security.framework` 미링크, `SecItemCopyMatching` 심볼 미임포트 |
| G3 | 외부 프로세스 실행은 **`ClaudeOfficialUsage.swift` 한 곳**뿐 | 다른 파일에서 `Process`/`NSTask`/`posix_spawn`/`popen`/`NSAppleScript` 가 나타나면 검사 실패. 셸(`/bin/sh` 등) 경유는 전면 금지 |
| G4 | 디스크 쓰기는 **설정 파일 하나**뿐 | `SettingsWriter.swift` 외의 파일에서 쓰기 API 가 나타나면 검사 실패. 대상은 하드코딩된 `~/.config/toki/config.json`, 원자적 쓰기, 비밀정보 미포함. 그 외 모든 파일 접근은 읽기 전용 |
| G5 | 자격증명 경로 미참조 | 소스·바이너리 문자열 모두에 `auth.json`, `sk-ant-`, `sk-proj-`, `id_rsa` 없음 |
| G6 | 경로 이탈 불가 | 심볼릭 링크 스킵 + 후보 파일이 루트 안에 있는지 정규화 경로로 재확인 |
| G7 | 설정으로 경로 조작 불가 | 설정 스키마에 경로/URL 필드가 없고, 수치는 클램프됨 |
| G8 | hardened runtime, entitlement 없음 | `flags=0x10002(adhoc,runtime)`, entitlement 미부여 |

**G1 이 핵심입니다.** 네트워크 경로가 존재하지 않으면, 설령 Toki 가 민감한 데이터를
읽더라도 밖으로 내보낼 방법이 없습니다.

## 4. 검증 방법 — 자동화

`./security-check.sh` 가 매 빌드 후 위 보증을 기계적으로 검증합니다. 소스 검사 6건 +
컴파일된 바이너리 검사 6건, 하나라도 깨지면 종료 코드 1. `package-dmg.sh` 는 이 게이트를
통과하지 못하면 dmg 를 만들지 않습니다.

```
── 소스 검사 ──────────────────────────────────────
  ✓ 네트워크 API 미사용 (URLSession/Network/CFStream)
  ✓ Keychain/Security API 미사용
  ✓ 자격증명 파일 경로 미참조
  ✓ 셸 경유 실행 없음
  ✓ 외부 프로세스는 ClaudeOfficialUsage.swift 에서만
  ✓ 파일 쓰기는 SettingsWriter.swift 에서만

── 바이너리 검사 ──────────────────────────────────
  ✓ CFNetwork / Network / Security 프레임워크 미링크
  ✓ Keychain / URLSession 심볼 미임포트
  ✓ 바이너리에 자격증명 문자열 없음
  ✓ 네트워크 entitlement 없음
  ✓ hardened runtime 적용
  ✓ 코드 서명 검증 통과

전체 통과 — 자격증명 접근·네트워크 경로 없음
```

소스 검사만으로는 부족하기 때문에 **컴파일 결과물도 함께** 검사합니다. 누군가 나중에
네트워크 호출을 추가하면 `otool -L` 단계에서 걸립니다.

## 5. 잔여 리스크 (숨기지 않고 명시)

| 리스크 | 평가 | 대응 |
|---|---|---|
| **App Sandbox 미적용** | 샌드박스를 켜면 `~/.claude`·`~/.codex` 를 읽을 수 없어 위젯이 성립하지 않습니다. 대신 네트워크·Keychain 경로를 제거해 "읽을 수는 있지만 내보낼 수 없는" 상태로 만들었습니다. | G1–G3 로 완화 |
| **사용자 권한으로 홈 디렉터리 읽기 가능** | Toki 는 사용자가 이미 읽을 수 있는 파일만 읽습니다. 권한 상승은 없습니다. | 설계상 수용 |
| **ad-hoc 서명 (공증 없음)** | 로컬 빌드용이므로 Apple 공증을 받지 않습니다. 배포하려면 Developer ID 서명 + notarization 이 필요합니다. | 로컬 사용 전제 |
| **접근성/화면 권한 불필요** | 패널 자동 닫기를 전역 이벤트 감시 대신 `hidesOnDeactivate` 로 구현했습니다. 따라서 접근성·화면 기록 권한을 요구하지 않으며, 다른 앱의 입력을 관찰할 수단이 없습니다. | 설계상 제거 |
| **로그 포맷 변경 시 오탐** | 필드가 사라지면 해당 카드가 "기록 없음"으로 표시됩니다. 잘못된 숫자를 자신 있게 보여주는 것보다 안전한 실패 방향입니다. | 설계상 의도 |
| **툴체인/의존성 공급망** | 외부 SwiftPM 의존성이 **0개**입니다. Apple SDK 만 사용합니다. | 공격면 최소 |

## 6. OAuth 로 공식 수치를 가져오는 방안 — 검토 결과

"Claude 쪽도 공식 수치를 쓸 수 없나"에 대한 답입니다.

| 방안 | 가능성 | 보안 영향 |
|---|---|---|
| **A. 현재 방식** (로컬 로그 집계) | 동작함. 단 비율은 자체 보정 추정치 | 자격증명 0, 네트워크 0 |
| **B. 공개 API 키** (`sk-ant-…`) | **불가.** 공개 API 에 구독제 5시간/주간 창을 주는 엔드포인트가 없음 | — |
| **C. Admin API** (`sk-ant-admin…`) | **부적합.** `/v1/organizations/usage_report/messages` 는 조직의 **API** 토큰 소비량이라 구독 세션 한도와 다른 지표 | 조직 전체 권한 키를 위젯이 보유해야 함 — 리스크 상승 |
| **D. Keychain OAuth 토큰 + 내부 엔드포인트** | 정확한 수치 획득 가능. Claude Code `/usage` 가 쓰는 **비공개** 경로 | **G1·G2 가 모두 깨짐.** 앱이 살아있는 액세스 토큰을 보유하고 네트워크를 열게 됨 |
| **E. 로컬 캐시 재활용** | **불가.** `~/.claude.json` 의 `clientDataCacheSlots` 를 확인했으나 GrowthBook 기능 플래그(`tengu_*`, `cedar_*`)만 있고 한도/사용량 필드가 없음 | — |

| **F. `claude` CLI 위임** (채택) | 동작함. 공식 수치를 그대로 얻음 | **G1·G2 유지.** 자격증명은 CLI 프로세스가 관리하고 Toki 는 stdout 만 읽음. 비용은 서브프로세스 1건(G3 로 좁힘) |

현재 구현은 **F** 입니다. D 와 같은 정확도를 얻으면서 네트워크·Keychain 보증을 지킵니다.
남는 대가는 두 가지이고 둘 다 문서화했습니다: 호출 1회가 요청 1건을 소모한다는 점(그래서
기본 10분 주기), 그리고 `/usage` 출력이 사람이 읽는 형식이라 Claude Code 업데이트로 문구가
바뀌면 파싱이 실패할 수 있다는 점(실패 시 조용히 추정치로 되돌아가고 카드에 사유 표시).

정확도가 더 필요하고 호출도 줄이고 싶다면, `/usage` 를 한 번 확인해 실제 한도를
`config.json` 에 넣고 `useClaudeCLI` 를 끄는 조합(A)도 그대로 가능합니다.

## 7. 변경 시 체크리스트

이 저장소에 손을 댈 때:

1. 네트워크·Keychain·서브프로세스 API 를 추가하지 마세요. 추가하면
   `security-check.sh` 가 실패하며, 실패는 곧 위 보증이 깨졌다는 뜻입니다.
2. 새 파일을 읽으려면 경로를 코드에 하드코딩하고, 설정에서 경로를 받지 마세요.
3. 로그에서 새 필드를 꺼낼 때는 숫자/열거형만 꺼내세요. 자유 텍스트를 UI 로 올리면
   프롬프트 내용이 화면에 노출될 수 있습니다.
4. 빌드 후 항상 `./security-check.sh` 를 돌리세요.
