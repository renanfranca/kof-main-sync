#!/usr/bin/env bash
set -euo pipefail

PROGRAM="kof-main-sync"
UPSTREAM_REPO="KofLang/Kof4j"
REPO_DIR="$HOME/projects/kof"
ORIGIN_REPO="auto"
INSTALL_KOF="true"
SKIP_KOF_VERSIONS=""
INTERVAL_MINUTES="5"
DRY_RUN="false"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$CONFIG_HOME/$PROGRAM"
CONFIG_FILE="$CONFIG_DIR/config"
STATE_DIR="$STATE_HOME/$PROGRAM"
KOF_DATA_DIR="$DATA_HOME/kof"
KOF_BIN_LINK="$BIN_DIR/kof"

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --repo-dir <path>       Managed Kof checkout (default: $HOME/projects/kof)
  --origin <owner/repo>   Explicit personal Kof fork
  --no-origin             Disable fork synchronization
  --no-kof-install        Disable official Kof release installation
  --interval <minutes>    Cron interval from 1 to 59 (default: 5)
  --dry-run               Validate and print actions without changing state
  --help                  Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; REPO_DIR=$2; shift 2 ;;
        --origin) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; ORIGIN_REPO=$2; shift 2 ;;
        --no-origin) ORIGIN_REPO=""; shift ;;
        --no-kof-install) INSTALL_KOF="false"; shift ;;
        --interval) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; INTERVAL_MINUTES=$2; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$INTERVAL_MINUTES" in ''|*[!0-9]*) printf 'Invalid interval: %s\n' "$INTERVAL_MINUTES" >&2; exit 2 ;; esac
if [ "$INTERVAL_MINUTES" -lt 1 ] || [ "$INTERVAL_MINUTES" -gt 59 ]; then
    printf 'Interval must be between 1 and 59.\n' >&2
    exit 2
fi
case "$REPO_DIR" in /*) ;; *) REPO_DIR="$PWD/$REPO_DIR" ;; esac

if [ "$(uname -s)" != Linux ]; then
    printf 'This release supports Linux only.\n' >&2
    exit 20
fi
if [ ! -f /etc/debian_version ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    printf 'Warning: only Debian, Ubuntu, and WSL2 are tested.\n' >&2
fi

missing=0
for dependency in bash git gh flock crontab curl tar sha256sum awk sed stat mktemp install; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$dependency" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    printf 'Install the missing packages for your distribution and run this installer again.\n' >&2
    exit 20
fi

cron_active=false
if command -v systemctl >/dev/null 2>&1 && systemctl is-active cron >/dev/null 2>&1; then
    cron_active=true
elif command -v service >/dev/null 2>&1 && service cron status >/dev/null 2>&1; then
    cron_active=true
fi
if [ "$cron_active" != true ]; then
    printf 'The cron service is not active. Start it for your system, then run this installer again.\n' >&2
    exit 20
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    printf 'GitHub CLI is not authenticated. Run: gh auth login\n' >&2
    exit 20
fi

if [ "$ORIGIN_REPO" = auto ]; then
    login=$(gh api user --jq .login)
    candidate="$login/Kof4j"
    parent=$(gh api "repos/$candidate" --jq '.parent.full_name // ""' 2>/dev/null || true)
    if [ "$parent" = "$UPSTREAM_REPO" ]; then
        ORIGIN_REPO=$candidate
    else
        ORIGIN_REPO=""
    fi
fi

case "$ORIGIN_REPO" in
    '') ;;
    */*)
        parent=$(gh api "repos/$ORIGIN_REPO" --jq '.parent.full_name // ""' 2>/dev/null || true)
        if [ "$parent" != "$UPSTREAM_REPO" ] && [ "$ORIGIN_REPO" != "$UPSTREAM_REPO" ]; then
            printf '%s is not a fork of %s.\n' "$ORIGIN_REPO" "$UPSTREAM_REPO" >&2
            exit 20
        fi
        ;;
    *) printf 'Invalid origin repository: %s\n' "$ORIGIN_REPO" >&2; exit 20 ;;
esac

printf 'Kof main sync installation\n'
printf '  checkout: %s\n' "$REPO_DIR"
printf '  upstream: %s\n' "$UPSTREAM_REPO"
printf '  origin: %s\n' "${ORIGIN_REPO:-disabled}"
printf '  install Kof releases: %s\n' "$INSTALL_KOF"
printf '  cron interval: %s minutes\n' "$INTERVAL_MINUTES"
printf '  command: %s/%s\n' "$BIN_DIR" "$PROGRAM"
printf '  configuration: %s\n' "$CONFIG_FILE"

if [ "$DRY_RUN" = true ]; then
    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null
        printf 'Dry run: existing checkout is a Git worktree.\n'
    else
        printf 'Dry run: would clone %s into %s.\n' "$UPSTREAM_REPO" "$REPO_DIR"
    fi
    printf 'Dry run complete; no files, remotes, or cron entries changed.\n'
    exit 0
fi

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
exec 8>"$STATE_DIR/sync.lock"
chmod 600 "$STATE_DIR/sync.lock"
if ! flock -n 8; then
    printf '%s: another run holds the lock\n' "$PROGRAM" >&2
    exit 11
fi
# Preserve the list as data when reinstalling, including optional entry spaces.
if [ -f "$CONFIG_FILE" ]; then
    SKIP_KOF_VERSIONS=$(awk '/^SKIP_KOF_VERSIONS=/ { value = substr($0, index($0, "=") + 1) } END { print value }' "$CONFIG_FILE")
fi

mkdir -p "$(dirname "$REPO_DIR")"
if [ ! -e "$REPO_DIR" ]; then
    git clone "https://github.com/$UPSTREAM_REPO.git" "$REPO_DIR"
    git -C "$REPO_DIR" remote rename origin upstream
elif [ ! -d "$REPO_DIR/.git" ]; then
    printf 'Checkout path exists but is not a Git repository: %s\n' "$REPO_DIR" >&2
    exit 20
fi

expected_upstream="https://github.com/$UPSTREAM_REPO.git"
if git -C "$REPO_DIR" remote get-url upstream >/dev/null 2>&1; then
    actual_upstream=$(git -C "$REPO_DIR" remote get-url upstream)
    case "$actual_upstream" in
        "$expected_upstream"|"https://github.com/$UPSTREAM_REPO"|"git@github.com:$UPSTREAM_REPO.git") ;;
        *) printf 'Unexpected upstream URL: %s\n' "$actual_upstream" >&2; exit 20 ;;
    esac
else
    git -C "$REPO_DIR" remote add upstream "$expected_upstream"
fi

if [ -n "$ORIGIN_REPO" ]; then
    expected_origin="https://github.com/$ORIGIN_REPO.git"
    if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
        actual_origin=$(git -C "$REPO_DIR" remote get-url origin)
        case "$actual_origin" in
            "$expected_origin"|"https://github.com/$ORIGIN_REPO"|"git@github.com:$ORIGIN_REPO.git") ;;
            *) printf 'Unexpected origin URL: %s\n' "$actual_origin" >&2; exit 20 ;;
        esac
    else
        git -C "$REPO_DIR" remote add origin "$expected_origin"
    fi
fi

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$STATE_DIR" "$KOF_DATA_DIR"
chmod 700 "$CONFIG_DIR" "$STATE_DIR"
temporary_command=$(mktemp "$BIN_DIR/.$PROGRAM.XXXXXX")
install -m 0755 "$SOURCE_DIR/bin/$PROGRAM" "$temporary_command"
mv -f -- "$temporary_command" "$BIN_DIR/$PROGRAM"

temporary_config=$(mktemp "$CONFIG_DIR/config.XXXXXX")
{
    printf 'REPO_DIR=%s\n' "$REPO_DIR"
    printf 'UPSTREAM_REPO=%s\n' "$UPSTREAM_REPO"
    printf 'ORIGIN_REPO=%s\n' "$ORIGIN_REPO"
    printf 'BRANCH=main\n'
    printf 'INSTALL_KOF=%s\n' "$INSTALL_KOF"
    printf 'SKIP_KOF_VERSIONS=%s\n' "$SKIP_KOF_VERSIONS"
    printf 'INTERVAL_MINUTES=%s\n' "$INTERVAL_MINUTES"
    printf 'KOF_DATA_DIR=%s\n' "$KOF_DATA_DIR"
    printf 'KOF_BIN_LINK=%s\n' "$KOF_BIN_LINK"
} > "$temporary_config"
chmod 600 "$temporary_config"
mv -f "$temporary_config" "$CONFIG_FILE"
flock -u 8
exec 8>&-

"$BIN_DIR/$PROGRAM" run --dry-run || result=$?
result=${result:-0}
if [ "$result" -ge 20 ]; then
    printf 'Initial dry run failed; cron was not installed.\n' >&2
    exit "$result"
fi
"$BIN_DIR/$PROGRAM" install

printf '\nInstalled successfully.\n'
printf 'Run now: %s/%s run\n' "$BIN_DIR" "$PROGRAM"
printf 'Inspect: %s/%s status\n' "$BIN_DIR" "$PROGRAM"
