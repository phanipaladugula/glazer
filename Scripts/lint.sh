#!/usr/bin/env bash
# Runs Glazer's static checks: the same ones CI runs.
#
# Usage: Scripts/lint.sh [--only CHECKS] [--strict]
#   --only CHECKS  Run only these checks, comma separated. Default: all of them.
#                    swift      Swift formatting (swift-format).
#                    shell      Syntax of every shell script, then ShellCheck.
#                    workflows  GitHub Actions workflows (actionlint).
#                    docs       Every relative link and image in the Markdown files exists.
#                    plists     Info.plist and entitlements parse.
#   --strict       Fail when an optional linter (shellcheck, actionlint) isn't installed,
#                  as CI does. Without it, those checks are skipped with a warning.
#   -h, --help     Show this help.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

readonly all_checks="swift,shell,workflows,docs,plists"
checks=$all_checks
strict=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only) checks="${2:?--only needs a list of checks}"; shift 2 ;;
        --strict) strict=true; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage_error "Unknown option: $1" ;;
    esac
done

IFS=, read -r -a selected <<<"$checks"
for check in "${selected[@]}"; do
    [[ ",$all_checks," == *",$check,"* ]] || usage_error "Unknown check: $check"
done

failures=()
fail() {
    printf '%sFAIL%s %s\n' "$_red$_bold" "$_reset" "$1" >&2
    failures+=("$1")
}
pass() { printf '%sPASS%s %s\n' "$_green$_bold" "$_reset" "$1" >&2; }

# Runs an optional tool's check, or skips it (failing under --strict) when not installed.
optional() {
    local tool=$1
    if command -v "$tool" >/dev/null 2>&1; then
        return 0
    elif $strict; then
        fail "$tool isn't installed"
    else
        warn "$tool isn't installed; skipping. Install it with: brew install $tool"
    fi
    return 1
}

shell_scripts() {
    printf '%s\n' install.sh Scripts/*.sh Scripts/lib/*.sh Tests/Install/*.sh 2>/dev/null |
        while read -r file; do [[ -f "$file" ]] && printf '%s\n' "$file"; done
}

lint_swift() {
    step "Swift formatting"
    if Scripts/format.sh --check >/dev/null 2>&1; then pass "swift-format"; else fail "swift-format: run Scripts/format.sh"; fi
}

lint_shell() {
    step "Shell scripts"
    local scripts=() file bad=0
    while read -r file; do scripts+=("$file"); done < <(shell_scripts)
    for file in "${scripts[@]}"; do
        bash -n "$file" || { fail "bash -n $file"; bad=1; }
        # install.sh runs with macOS's bash 3.2, as curl | bash does.
        if [[ "$file" == install.sh && -x /bin/bash ]]; then
            /bin/bash -n "$file" || { fail "/bin/bash -n $file"; bad=1; }
        fi
    done
    ((bad == 0)) && pass "syntax of ${#scripts[@]} scripts"

    if optional shellcheck; then
        if shellcheck --external-sources --source-path=SCRIPTDIR --severity=style "${scripts[@]}"; then
            pass "shellcheck"
        else
            fail "shellcheck"
        fi
    fi
}

lint_workflows() {
    step "GitHub Actions workflows"
    if optional actionlint; then
        if actionlint; then pass "actionlint"; else fail "actionlint"; fi
    fi
}

lint_docs() {
    step "Documentation links"
    require python3
    if python3 - <<'PYTHON'; then pass "Markdown links"; else fail "Markdown links"; fi
import pathlib, re, sys
from urllib.parse import unquote

root = pathlib.Path(".").resolve()
skip = {".build", "node_modules", ".git", "dist", ".claude"}
link = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|<img[^>]+src=\"([^\"]+)\"|srcset=\"([^\"]+)\"")
broken = 0
for path in sorted(root.rglob("*.md")):
    if skip & set(path.relative_to(root).parts):
        continue
    text = path.read_text(encoding="utf-8")
    # Ignore links inside fenced code blocks.
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for match in link.finditer(text):
        target = next(group for group in match.groups() if group)
        if re.match(r"^[a-z]+:|^#|^mailto:", target):
            continue
        target = unquote(target.split("#")[0])
        if not target:
            continue
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            print(f"  {path.relative_to(root)}: broken link to {target}", file=sys.stderr)
            broken += 1
sys.exit(1 if broken else 0)
PYTHON
}

lint_plists() {
    step "Property lists"
    if ! command -v plutil >/dev/null 2>&1; then
        note "plutil is macOS only; skipping."
        return
    fi
    local file bad=0
    for file in Resources/Info.plist Resources/Glazer.entitlements; do
        plutil -lint -s "$file" || { fail "plutil $file"; bad=1; }
    done
    ((bad == 0)) && pass "Info.plist and entitlements"
}

for check in "${selected[@]}"; do
    "lint_$check"
done

if ((${#failures[@]} > 0)); then
    die "${#failures[@]} check(s) failed: ${failures[*]}" "$EX_DATAERR"
fi
success "All checks passed."
