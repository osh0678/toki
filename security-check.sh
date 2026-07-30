#!/usr/bin/env bash
# Toki security gate — run after every build.
#
# Enforces the guarantees documented in SECURITY.md by inspecting both the source
# tree and the linked binary:
#
#   1. No networking API is referenced      -> nothing can be exfiltrated
#   2. No Keychain / Security API           -> OAuth tokens are unreachable
#   3. No subprocess execution              -> no shelling out to credential tools
#   4. No credential file paths             -> auth.json / credentials never opened
#   5. Binary links no network frameworks   -> guarantee holds after compilation
#   6. Bundle is signed with the hardened runtime and no entitlements
set -uo pipefail
cd "$(dirname "$0")"

SOURCES="Sources"
BUNDLE="build/Toki.app"
BINARY="${BUNDLE}/Contents/MacOS/Toki"
failures=0

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$((failures + 1)); }

# Every check captures its input into a variable before grepping it. Piping a
# command straight into `grep -q` lets grep close the pipe on first match, killing
# the producer with SIGPIPE — which `pipefail` then reports as a failed pipeline,
# inverting the result of the check.

# Fails when `pattern` appears in the Swift sources. Comment-only lines are
# stripped first, so prose such as "never reads auth.json" does not trip this.
forbid_source() {
    local label="$1" pattern="$2" hits
    hits=$(grep -rn --include='*.swift' -E "$pattern" "$SOURCES" 2>/dev/null || true)
    hits=$(printf '%s\n' "$hits" | grep -vE '^[^:]+:[0-9]+: *(//|///|\*)' || true)
    if [ -n "$hits" ]; then
        fail "$label"
        printf '%s\n' "$hits" | sed 's/^/      /'
    else
        pass "$label"
    fi
}

# Fails when `pattern` appears in any Swift file other than `allowed`.
# Used for capabilities that are permitted in exactly one audited place.
confine_source() {
    local label="$1" pattern="$2" allowed="$3" hits
    hits=$(grep -rn --include='*.swift' -E "$pattern" "$SOURCES" 2>/dev/null || true)
    hits=$(printf '%s\n' "$hits" | grep -vE '^[^:]+:[0-9]+: *(//|///|\*)' || true)
    hits=$(printf '%s\n' "$hits" | grep -v "$allowed" || true)
    if [ -n "$hits" ]; then
        fail "$label"
        printf '%s\n' "$hits" | sed 's/^/      /'
    else
        pass "$label"
    fi
}

# Fails when `pattern` appears in captured `text`.
forbid_text() {
    local label="$1" pattern="$2" text="$3" hits
    hits=$(printf '%s\n' "$text" | grep -E "$pattern" || true)
    if [ -n "$hits" ]; then
        fail "$label"
        printf '%s\n' "$hits" | sed 's/^/      /'
    else
        pass "$label"
    fi
}

# Fails when `pattern` is missing from captured `text`.
require_text() {
    local label="$1" pattern="$2" text="$3" hits
    hits=$(printf '%s\n' "$text" | grep -E "$pattern" || true)
    if [ -n "$hits" ]; then pass "$label"; else fail "$label"; fi
}

echo "── 소스 검사 ──────────────────────────────────────"
forbid_source "네트워크 API 미사용 (URLSession/Network/CFStream)" \
    '\b(URLSession|NSURLConnection|CFStreamCreate|NWConnection|NWBrowser|CFSocket)\b'
forbid_source "Keychain/Security API 미사용" \
    '\b(SecItem[A-Za-z]*|SecKeychain[A-Za-z]*|kSecClass|LAContext)\b|import +Security'
forbid_source "자격증명 파일 경로 미참조" \
    'auth\.json|credentials|id_[rd]sa|\.netrc|\.ssh|ANTHROPIC_API_KEY|OPENAI_API_KEY'
forbid_source "셸 경유 실행 없음" \
    '/bin/(sh|bash|zsh)|NSUserUnixTask'
confine_source "외부 프로세스는 ClaudeOfficialUsage.swift 에서만" \
    '\b(Process\(\)|NSTask|posix_spawn|execv[pe]?|NSAppleScript)\b|popen\(|Darwin\.system\(' \
    'ClaudeOfficialUsage.swift'
confine_source "파일 쓰기는 SettingsWriter.swift 에서만" \
    'FileHandle\(forWritingTo|FileHandle\(forUpdating|\.write\(to:|createFile\(atPath' \
    'SettingsWriter.swift'
confine_source "URL 열기·클립보드는 InstallHelpCard.swift 에서만" \
    'NSWorkspace[^\n]*open|NSPasteboard' \
    'InstallHelpCard.swift'
forbid_source "클립보드 읽기 없음" \
    'pasteboardItems|\.string\(forType:|readObjects\(forClasses'
forbid_source "전역 키보드 감시 없음" \
    'CGEventTap|IOHIDManager|addGlobalMonitorForEvents\(matching: \[\.key'

echo
echo "── 바이너리 검사 ──────────────────────────────────"
if [ ! -f "$BINARY" ]; then
    fail "바이너리 없음 — 먼저 ./build.sh 실행"
else
    linked=$(otool -L "$BINARY" 2>/dev/null || true)
    undefined=$(nm -u "$BINARY" 2>/dev/null || true)
    literals=$(strings -a "$BINARY" 2>/dev/null || true)
    signature=$(codesign -dv "$BUNDLE" 2>&1 || true)
    entitlements=$(codesign -d --entitlements - "$BUNDLE" 2>/dev/null | tr -d '\0' || true)

    forbid_text "CFNetwork / Network / Security 프레임워크 미링크" \
        'CFNetwork|/Network\.framework|Security\.framework' "$linked"
    forbid_text "Keychain / URLSession 심볼 미임포트" \
        'SecItemCopyMatching|SecKeychain|NSURLSession' "$undefined"
    forbid_text "바이너리에 자격증명 문자열 없음" \
        'auth\.json|sk-ant-|sk-proj-|id_rsa' "$literals"
    forbid_text "네트워크 entitlement 없음" \
        'network\.client' "$entitlements"

    require_text "hardened runtime 적용" 'flags=0x[0-9a-f]+\([^)]*runtime' "$signature"

    if codesign --verify --strict "$BUNDLE" 2>/dev/null; then
        pass "코드 서명 검증 통과"
    else
        fail "코드 서명 검증 실패"
    fi
fi

echo
if [ "$failures" -eq 0 ]; then
    printf '\033[32m전체 통과 — 자격증명 접근·네트워크 경로 없음\033[0m\n'
    exit 0
fi
printf '\033[31m실패 %d건 — SECURITY.md 의 보증이 깨졌습니다\033[0m\n' "$failures"
exit 1
