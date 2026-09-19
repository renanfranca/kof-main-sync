#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d /tmp/kof-main-sync-tests.XXXXXX)
trap 'rm -rf -- "$TMP_ROOT"' EXIT

pass_count=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { pass_count=$((pass_count + 1)); printf 'ok %d - %s\n' "$pass_count" "$*"; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$1] = [$2]${3:+ ($3)}"; }
assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_contains() { grep -Fq "$2" "$1" || fail "$1 does not contain: $2"; }

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export KOF_MAIN_SYNC_TEST_MODE=1
export MOCK_CRONTAB_FILE="$TMP_ROOT/crontab"
export FIXTURE_RELEASE_DIR="$TMP_ROOT/release-assets"
mkdir -p "$HOME/.local/bin" "$TMP_ROOT/mock-bin" "$FIXTURE_RELEASE_DIR"

cat > "$TMP_ROOT/mock-bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
    "auth status"|"auth setup-git") exit 0 ;;
    "release view")
        printf '%s\n' 'kof-1.1.0-linux-x86_64.tar.gz' 'SHA256SUMS'
        ;;
    "release download")
        destination=""
        while [ "$#" -gt 0 ]; do
            if [ "$1" = --dir ]; then destination=$2; shift 2; else shift; fi
        done
        cp "$FIXTURE_RELEASE_DIR/kof-1.1.0-linux-x86_64.tar.gz" "$destination/"
        cp "$FIXTURE_RELEASE_DIR/SHA256SUMS" "$destination/"
        ;;
    *) printf 'unexpected gh invocation: %s\n' "$*" >&2; exit 1 ;;
esac
MOCK_GH

cat > "$TMP_ROOT/mock-bin/crontab" <<'MOCK_CRONTAB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = -l ]; then
    if [ -f "$MOCK_CRONTAB_FILE" ]; then cat "$MOCK_CRONTAB_FILE"; exit 0; fi
    printf 'no crontab for test\n' >&2
    exit 1
fi
cp "$1" "$MOCK_CRONTAB_FILE"
MOCK_CRONTAB
chmod +x "$TMP_ROOT/mock-bin/gh" "$TMP_ROOT/mock-bin/crontab"
export KOF_MAIN_SYNC_GH_BIN="$TMP_ROOT/mock-bin/gh"
export KOF_MAIN_SYNC_CRONTAB_BIN="$TMP_ROOT/mock-bin/crontab"

git init --bare --initial-branch=main "$TMP_ROOT/upstream.git" >/dev/null
git init --bare --initial-branch=main "$TMP_ROOT/origin.git" >/dev/null
git init --initial-branch=main "$TMP_ROOT/seed" >/dev/null
git -C "$TMP_ROOT/seed" config user.name Test
git -C "$TMP_ROOT/seed" config user.email test@example.com
printf '1.0.0\n' > "$TMP_ROOT/seed/VERSION"
printf '# Kof docs 1.0.0\n' > "$TMP_ROOT/seed/README.md"
git -C "$TMP_ROOT/seed" add VERSION README.md
git -C "$TMP_ROOT/seed" commit -m initial >/dev/null
initial_sha=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
git -C "$TMP_ROOT/seed" remote add upstream "$TMP_ROOT/upstream.git"
git -C "$TMP_ROOT/seed" remote add origin "$TMP_ROOT/origin.git"
git -C "$TMP_ROOT/seed" push upstream main >/dev/null
git -C "$TMP_ROOT/seed" push origin main >/dev/null

git clone "$TMP_ROOT/upstream.git" "$HOME/projects/kof" >/dev/null
git -C "$HOME/projects/kof" remote rename origin upstream
git -C "$HOME/projects/kof" remote add origin "$TMP_ROOT/origin.git"

printf '1.1.0\n' > "$TMP_ROOT/seed/VERSION"
printf '# Kof docs 1.1.0\n' > "$TMP_ROOT/seed/README.md"
git -C "$TMP_ROOT/seed" add VERSION README.md
git -C "$TMP_ROOT/seed" commit -m update >/dev/null
latest_sha=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
git -C "$TMP_ROOT/seed" tag kof-1.1.0-linux-x86_64
git -C "$TMP_ROOT/seed" push upstream main --tags >/dev/null

dist="$TMP_ROOT/dist/kof-1.1.0-linux-x86_64"
mkdir -p "$dist/bin" "$dist/lib" "$dist/jdk/bin"
cat > "$dist/bin/kof" <<'FAKE_KOF'
#!/usr/bin/env bash
case "${1:-}" in
    version) printf 'kof 1.1.0\n' ;;
    info) printf 'Kof 1.1.0\nJVM: Test JDK 25 (embedded)\n' ;;
    *) exit 1 ;;
esac
FAKE_KOF
cat > "$dist/jdk/bin/java" <<'FAKE_JAVA'
#!/usr/bin/env bash
exit 0
FAKE_JAVA
chmod +x "$dist/bin/kof" "$dist/jdk/bin/java"
: > "$dist/lib/kof.jar"
printf '1.1.0\n' > "$dist/VERSION"
(cd "$TMP_ROOT/dist" && tar -czf "$FIXTURE_RELEASE_DIR/kof-1.1.0-linux-x86_64.tar.gz" kof-1.1.0-linux-x86_64)
(cd "$FIXTURE_RELEASE_DIR" && sha256sum kof-1.1.0-linux-x86_64.tar.gz > SHA256SUMS)

old_install="$XDG_DATA_HOME/kof/kof-1.0.0-linux-x86_64"
mkdir -p "$old_install/bin"
cat > "$old_install/bin/kof" <<'OLD_KOF'
#!/usr/bin/env bash
case "${1:-}" in
    version) printf 'kof 1.0.0\n' ;;
    info) printf 'Kof 1.0.0\nJVM: Old JDK 25 (embedded)\n' ;;
    *) exit 1 ;;
esac
OLD_KOF
chmod +x "$old_install/bin/kof"
ln -s "$old_install/bin/kof" "$HOME/.local/bin/kof"

mkdir -p "$XDG_CONFIG_HOME/kof-main-sync"
cat > "$XDG_CONFIG_HOME/kof-main-sync/config" <<EOF
REPO_DIR=$HOME/projects/kof
UPSTREAM_REPO=fixture/Kof4j
ORIGIN_REPO=fixture/Kof4j
BRANCH=main
INSTALL_KOF=true
INTERVAL_MINUTES=5
KOF_DATA_DIR=$XDG_DATA_HOME/kof
KOF_BIN_LINK=$HOME/.local/bin/kof
EOF

tool="$ROOT/bin/kof-main-sync"
"$tool" --help >/dev/null
pass "help is available"

"$tool" run --dry-run >/dev/null
assert_eq "$(git -C "$HOME/projects/kof" rev-parse HEAD)" "$initial_sha" "dry run checkout"
assert_eq "$(git --git-dir="$TMP_ROOT/origin.git" rev-parse main)" "$initial_sha" "dry run origin"
assert_eq "$(readlink -f "$HOME/.local/bin/kof")" "$old_install/bin/kof" "dry run installation"
pass "dry run leaves checkout, origin, and installation unchanged"

"$tool" run >/dev/null
assert_eq "$(git -C "$HOME/projects/kof" rev-parse HEAD)" "$latest_sha" "checkout update"
assert_eq "$(git --git-dir="$TMP_ROOT/origin.git" rev-parse main)" "$latest_sha" "origin update"
assert_eq "$("$HOME/.local/bin/kof" version)" "kof 1.1.0" "release activation"
assert_file "$XDG_STATE_HOME/kof-main-sync/installed.state"
assert_contains "$XDG_STATE_HOME/kof-main-sync/installed.state" "PREVIOUS_PATH=$old_install"
pass "run updates documentation, origin, and exact release"

"$tool" rollback >/dev/null
assert_eq "$("$HOME/.local/bin/kof" version)" "kof 1.0.0" "rollback"
pass "rollback restores the previous validated installation"

printf '15 2 * * * /usr/bin/true # unrelated\n' > "$MOCK_CRONTAB_FILE"
"$tool" install >/dev/null
"$tool" install >/dev/null
assert_eq "$(grep -c '# kof-main-sync$' "$MOCK_CRONTAB_FILE")" "1" "cron idempotency"
assert_contains "$MOCK_CRONTAB_FILE" '# unrelated'
"$tool" uninstall >/dev/null
assert_eq "$(grep -c '# kof-main-sync$' "$MOCK_CRONTAB_FILE" || true)" "0" "cron removal"
assert_contains "$MOCK_CRONTAB_FILE" '# unrelated'
pass "cron installation and removal are idempotent and preserve other jobs"

touch "$HOME/projects/kof/untracked"
set +e
"$tool" run >/dev/null
dirty_status=$?
set -e
assert_eq "$dirty_status" "10" "dirty checkout exit"
rm -f "$HOME/projects/kof/untracked"
pass "dirty checkout is skipped safely"

exec 8>"$XDG_STATE_HOME/kof-main-sync/sync.lock"
flock -n 8
set +e
"$tool" run >/dev/null 2>&1
busy_status=$?
set -e
assert_eq "$busy_status" "11" "lock exit"
flock -u 8
pass "concurrent runs are rejected by the lock"

"$tool" status > "$TMP_ROOT/status.out"
assert_contains "$TMP_ROOT/status.out" 'Working tree: clean'
"$tool" logs > "$TMP_ROOT/logs.out"
assert_contains "$TMP_ROOT/logs.out" 'event=end'
pass "status and logs expose operational state"

bash -n "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/bin/kof-main-sync" "$ROOT/tests/run.sh"
pass "all shell entrypoints parse"

printf '1..%d\n' "$pass_count"
