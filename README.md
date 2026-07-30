<div align="center">

# 🐰 Toki

**Claude Code 와 Codex CLI 의 남은 사용량을 macOS 메뉴바에서 바로 확인하세요.**

[![Download](https://img.shields.io/badge/download-latest%20dmg-D97757?style=flat-square)](https://github.com/osh0678/toki/releases/latest/download/Toki.dmg)
[![Release](https://img.shields.io/github/v/release/osh0678/toki?style=flat-square&color=black)](https://github.com/osh0678/toki/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-black?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-26%2B-black?style=flat-square)](#요구-사항)

</div>

---

`/usage` 를 확인하려고 세션을 열었다 닫는 일, 한도에 걸린 뒤에야 알아채는 일을 없애려고
만들었습니다. 메뉴바에 남은 여유가 항상 떠 있고, 클릭하면 두 도구의 창별 잔량과 초기화
시각이 한 화면에 보입니다.

```
메뉴바:                        🐰 76%   🔋 ᯤ 🔍 ⌃
                                ↑ 좌클릭
╭───────────────────────────────────╮
│ 🐰 Toki              ⟳   ⚙   ✕   │
│ ╭─ ✳ Claude Code ──── Max 5x ──╮ │
│ │ 5시간                     76 % │ │
│ │ ▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍░░░░░░░ │ │
│ │ 2시간 31분 후 초기화   공식     │ │
│ │ 주간                      79 % │ │
│ │ ▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍░░░░░░ │ │
│ │ ───────────────────────────── │ │
│ │ 오늘 18.2M 토큰   API 환산 $17 │ │
│ ╰───────────────────────────────╯ │
│ ╭─ ⬢ Codex CLI ─────── Plus ───╮ │
│ │ 주간                      72 % │ │
│ │ ▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍▍░░░░░░░░ │ │
│ ╰───────────────────────────────╯ │
│ 11:42 기준 · 로컬 60초 · 공식 10분 │
╰───────────────────────────────────╯
```

<!-- 실제 스크린샷을 넣으려면 docs/screenshot.png 로 저장하고 아래 줄의 주석을 해제하세요.
<img src="docs/screenshot.png" width="360" alt="Toki 패널">
-->

## 이런 걸 합니다

- **남은 양으로 보여줍니다.** 소비량이 아니라 잔량이 헤드라인입니다 — 지금 계속 작업해도
  되는지가 핵심이니까요. 25% 아래면 주황, 10% 아래면 빨강으로 바뀝니다.
- **공식 수치입니다.** 두 도구 모두 서버가 계산한 사용률을 씁니다. 추측이 아닙니다.
- **초기화 시각을 알려줍니다.** "2시간 31분 후 초기화" 처럼 언제 풀리는지 같이 나옵니다.
- **오늘 쓴 토큰과 API 환산 비용**을 함께 보여줍니다(구독 청구액이 아닌 참고치).
- **Liquid Glass.** macOS 26 네이티브 `glassEffect` 로 그렸고, 소비된 구간을 회색으로 덮지
  않아 패널 뒤 배경이 그래프를 통과합니다.
- **조용합니다.** Dock 아이콘 없음, 자격증명 접근 없음. 네트워크는 하루 1회 업데이트
  확인뿐이고 끌 수 있습니다.

## 설치

1. [**최신 dmg 다운로드**](https://github.com/osh0678/toki/releases/latest/download/Toki.dmg)
   — 항상 가장 최신 릴리스를 가리킵니다 ([릴리스 목록](https://github.com/osh0678/toki/releases))
2. dmg 를 열고 **Toki 를 Applications 로 드래그**
3. Launchpad 에서 Toki 실행 → 메뉴바에 🐰 가 나타납니다

### 처음 열 때 "확인되지 않은 개발자" 라고 나오면

Apple 공증(연 $99 개발자 프로그램)을 받지 않은 무료 앱이라 그렇습니다. 둘 중 하나로
한 번만 허용하면 됩니다.

- **Applications 폴더에서 Toki 우클릭 → 열기 → 열기**
- 또는 터미널에서:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Toki.app
  ```

### 로그인할 때 자동 실행

**시스템 설정 → 일반 → 로그인 항목** 에서 `+` 로 Toki 를 추가하세요.

## 요구 사항

| 항목 | 필요 |
|---|---|
| macOS | **26 (Tahoe) 이상** — Liquid Glass API 때문입니다 |
| Claude Code | Claude 카드를 쓰려면 설치 + 로그인 필요 |
| Codex CLI | Codex 카드를 쓰려면 설치 + 최근 세션 1개 이상 |

둘 중 하나만 있어도 됩니다. 없는 쪽은 카드가 뜨지 않고, 둘 다 없으면 설정 화면에서
이유를 알려줍니다.

## 쓰는 법

| 하고 싶은 것 | 방법 |
|---|---|
| 패널 열기 / 닫기 | 메뉴바 🐰 **좌클릭** |
| 패널 닫기 | 다른 곳 클릭, 또는 아이콘 재클릭 |
| 지금 바로 새로고침 | 패널의 ⟳ |
| 설정 | 패널의 ⚙ |
| 새로고침 · 설정 · 종료 메뉴 | 메뉴바 🐰 **우클릭**, 또는 패널 우클릭 |
| 완전히 종료 | 메뉴바 우클릭 → **Toki 종료** |

키보드 단축키는 제공하지 않습니다. Dock 아이콘이 없는 accessory 앱이라 패널이 키 윈도우가
되지 않고, 키 이벤트가 앱에 도달하지 않기 때문입니다. 전역 키보드 감시로 우회할 수는
있지만 머신 전체의 입력을 관찰해야 해서 택하지 않았습니다.

메뉴바 숫자는 두 도구의 모든 창 중 **가장 빡빡한 잔량**입니다. 듀얼 모니터에서는 클릭한
화면의 메뉴바 아래에 열립니다.

## 숫자는 어디서 오나

정확히 어떤 값을 보고 있는지 알 수 있어야 하니 밝혀둡니다.

### Codex CLI — 추가 호출 없음

Codex 는 매 턴 서버가 계산한 사용률을 자기 세션 로그에 적어둡니다. Toki 는 최신 값만
읽습니다. 네트워크 호출도, 요청 소모도 없습니다.

### Claude Code — `claude` CLI 에 물어봅니다

Anthropic 은 구독 창 한도를 공개 API 로 제공하지 않습니다. 대신 `claude` CLI 가 `/usage`
를 알고 있으므로 Toki 는 그걸 비대화형으로 호출합니다.

```bash
claude -p "/usage" --output-format json
```

**인증은 CLI 가 자기 프로세스에서 처리합니다.** Toki 는 Keychain 도, 네트워크도 건드리지
않고 출력의 숫자만 읽습니다.

> ⚠️ **호출 1회당 요청 1건이 소모됩니다.** 그래서 기본 주기가 **10분**(하루 약 144건)입니다.
> 부담되면 설정에서 주기를 늘리거나 공식 수치를 끄면 됩니다. 토큰·비용 집계는 로그만 읽어서
> 공짜이므로 60초마다 따로 갱신합니다.

### 공식 수치를 못 가져오면

CLI 가 없거나 출력 형식이 바뀌면 세션 로그의 토큰을 직접 집계한 **추정치**로 자동
전환하고, 바 옆에 `추정` 이라고 표시합니다. 추정은 실제와 꽤 어긋날 수 있습니다(실측 예:
공식 24%/21% vs 추정 39%/94%) — 분모를 "관측된 최대치" 로 잡기 때문입니다. 실제 한도를
안다면 설정 파일에 직접 넣는 편이 정확합니다.

### `API 환산 $` 는 청구서가 아닙니다

구독 사용분은 토큰 단위로 과금되지 않습니다. "같은 작업을 API 로 했다면" 을 공식 정가로
환산한 참고치입니다(캐시 배수 반영: 5분 쓰기 1.25×, 1시간 쓰기 2×, 읽기 0.1×).

## 설정

⚙ 또는 `⌘,` → **Claude Code / Codex CLI / 공통** 으로 나뉘어 있습니다. 값을 바꾸면 즉시
반영되고 `~/.config/toki/config.json` 에 **자동 저장**됩니다(저장 버튼 없음). 파일을 직접
편집해도 됩니다.

```json
{
  "refreshSeconds": 60,
  "officialRefreshSeconds": 600,
  "useClaudeCLI": true,
  "showClaude": true,
  "showCodex": true,
  "showMenuBarPercent": true,
  "panelOpacity": 0.35,
  "checkForUpdates": true,
  "lookbackDays": 14,
  "claude": { "fiveHourTokenLimit": null, "weeklyTokenLimit": null }
}
```

| 키 | 기본값 | 뜻 |
|---|---|---|
| `refreshSeconds` | `60` | 로컬 로그 재집계 주기(초). 요청 소모 없음 |
| `officialRefreshSeconds` | `600` | 공식 수치 갱신 주기(초). **호출마다 요청 1건** |
| `useClaudeCLI` | `true` | 끄면 공식 호출 없이 추정치만 사용 |
| `showClaude` / `showCodex` | `true` | 끈 도구는 읽지도 않습니다 |
| `showMenuBarPercent` | `true` | 끄면 메뉴바에 아이콘만(색으로만 경고) |
| `panelOpacity` | `0.35` | 패널 배경 불투명도(0–1). 0 이면 유리만, 1 이면 가장 진함 |
| `checkForUpdates` | `true` | 하루 1회 GitHub 릴리스 조회. **끄면 네트워크를 전혀 쓰지 않습니다** |
| `lookbackDays` | `14` | Claude 로그 조회 범위(1–90) |
| `claude.fiveHourTokenLimit` | `null` | 추정 모드의 5시간 창 한도를 직접 지정 |
| `claude.weeklyTokenLimit` | `null` | 추정 모드의 주간 창 한도를 직접 지정 |

경로나 URL 을 받는 키는 **의도적으로 없습니다.** 읽는 위치는 모두 코드에 하드코딩되어
있어, 설정을 조작해도 임의 파일을 열게 만들 수 없습니다.

## 업데이트

하루 1회 GitHub 릴리스를 확인하고, 새 버전이 있으면 설정 화면 맨 위에 카드가 뜹니다.
**다운로드**를 누르면 브라우저로 최신 dmg 를 받고, 열어서 Toki 를 Applications 로 드래그하면
교체됩니다(실행 중이면 먼저 종료).

앱이 스스로 받아서 자기 번들을 덮어쓰지는 **않습니다.** 원격 파일이 실행 코드가 되는 통로를
만들지 않기 위한 선택이고, ad-hoc 서명이라 교체될 번들의 서명을 검증할 수단도 없기 때문입니다.

확인 요청은 인증 없는 GET 1건이고 업로드하는 데이터가 없습니다. 응답에서 읽는 것은 버전
문자열(`tag_name`) 하나뿐입니다. 원치 않으면 설정 → 공통 → **업데이트 확인**을 끄면
Toki 는 네트워크를 전혀 쓰지 않습니다.

## 문제 해결

| 증상 | 해결 |
|---|---|
| 메뉴바에 아이콘이 안 보임 | 메뉴바가 꽉 찼을 수 있습니다. 다른 항목을 `⌘`+드래그로 정리하거나 Bartender 류로 확인 |
| "확인되지 않은 개발자" | 위 [처음 열 때](#처음-열-때-확인되지-않은-개발자-라고-나오면) 참고 |
| 배경이 너무 비침 / 답답함 | 설정 → 공통 → **배경 불투명도** 슬라이더를 조절 |
| Claude 카드에 `추정` 만 나옴 | `claude` 가 `~/.local/bin`·`/opt/homebrew/bin`·`/usr/local/bin` 중 하나에 있는지 확인. 설정 화면 상단에 실패 사유가 표시됩니다 |
| 요청 수가 늘어나는 게 신경 쓰임 | 설정에서 공식 갱신 주기를 늘리거나 **공식 수치 사용**을 끄세요 |
| Codex 카드가 안 보임 | 최근 7일 안에 Codex 세션이 있어야 합니다 |
| 값이 안 맞는 것 같음 | ⟳ 로 강제 새로고침(스로틀 무시). 그래도 다르면 `claude -p "/usage"` 결과와 비교해보세요 |

## 직접 빌드

Xcode 프로젝트도 개발자 계정도 필요 없습니다. 외부 의존성 0개.

```bash
git clone https://github.com/osh0678/toki.git
cd toki
./package-dmg.sh        # 빌드 → 보안 게이트 → dist/Toki-1.0.0.dmg
```

단계별로:

```bash
./build.sh              # build/Toki.app (ad-hoc 서명 + hardened runtime)
./security-check.sh     # 보안 보증 검증
open build/Toki.app
```

`package-dmg.sh` 는 **보안 게이트를 통과하지 못하면 dmg 를 만들지 않습니다.**
필요한 것은 macOS 26+ 와 Swift 6.3+ 툴체인입니다.

## 보안

이 앱은 자격증명 근처의 파일을 읽는 도구이므로, 신뢰 근거를 검증 가능하게 만들었습니다.

- **네트워크는 업데이트 확인 1건뿐이고, 끄면 0건입니다** — 하루 1회 GitHub 릴리스 조회.
  인증 없음, 업로드 본문 없음, 응답에서 버전 문자열 하나만 읽습니다. `URLSession` 은
  `UpdateChecker.swift` 한 파일로 고정되어 있고(다른 파일에 넣으면 검사 실패), 저수준
  소켓과 `Network.framework` 는 전면 금지입니다.
- **앱이 자기 자신을 교체하지 않습니다** — 다운로드 버튼은 dmg URL 을 브라우저로 넘길
  뿐입니다. 원격 파일이 실행 코드가 되는 통로를 만들지 않기 위한 선택입니다.
- **Keychain 을 건드리지 않습니다** — `Security.framework` 미링크. Codex 의
  `~/.codex/auth.json` 은 경로조차 코드에 없습니다.
- **외부 프로세스는 한 곳**(`ClaudeOfficialUsage.swift`)에서만, 절대경로 허용목록 +
  리터럴 인자 + 셸 미사용.
- **디스크 쓰기는 설정 파일 하나**뿐입니다.
- `./security-check.sh` 가 소스와 **컴파일된 바이너리** 양쪽에서 매 빌드 검증합니다
  (소스 10 + 바이너리 6).

전체 위협 모델과 잔여 리스크: **[SECURITY.md](SECURITY.md)**

## 프로젝트 구조

```
Sources/Toki/
  App/          메뉴바 아이템, 글라스 패널, 앱 델리게이트
  Models/       스냅샷 모델, 설정 읽기/쓰기
  Providers/    JSONL 리더, 가격표, 5시간 창 집계,
                claude CLI 공식 수치, Codex rate_limits
  Store/        @Observable 상태 · 이중 주기 갱신
  Views/        Theme, 잔량 계기, 카드, 설정, 루트 패널
build.sh · package-dmg.sh · security-check.sh
```

## 기여

버그 리포트와 PR 환영합니다. 코드를 고칠 때는 `./security-check.sh` 를 꼭 통과시켜 주세요 —
실패는 README 와 SECURITY.md 에 적어둔 보증이 깨졌다는 뜻입니다.

## 라이선스

[MIT](LICENSE) — 자유롭게 쓰고, 고치고, 배포하세요.

---

<div align="center">

Toki 는 개인이 만든 **비공식** 도구입니다. Anthropic, OpenAI 와 제휴·후원 관계가 없습니다.<br>
Claude Code 와 Codex CLI 의 로컬 출력에 의존하므로, 해당 도구가 업데이트되면 동작이 바뀔 수 있습니다.

</div>
