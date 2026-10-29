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
assert_not_contains() { if grep -Fq "$2" "$1"; then fail "$1 unexpectedly contains: $2"; fi; }
assert_exit() {
    local expected=$1 actual=0
    shift
    "$@" > "$TMP_ROOT/command.out" 2>&1 || actual=$?
    if [ "$actual" != "$expected" ]; then cat "$TMP_ROOT/command.out" >&2; fail "exit $actual, expected $expected: $*"; fi
}

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export KOF_MAIN_SYNC_TEST_MODE=1
export MOCK_CRONTAB_FILE="$TMP_ROOT/crontab"
export FIXTURE_RELEASE_DIR="$TMP_ROOT/release-assets"
export MOCK_GH_CALLS="$TMP_ROOT/gh.calls"
export MOCK_GIT_CALLS="$TMP_ROOT/git.calls"
mkdir -p "$HOME/.local/bin" "$TMP_ROOT/mock-bin" "$FIXTURE_RELEASE_DIR"

cat > "$TMP_ROOT/mock-bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_GH_CALLS"
case "${1:-} ${2:-}" in
    "auth status"|"auth setup-git") exit 0 ;;
    "api repos/KofLang/Kof4j") exit 0 ;;
    "release view")
        printf '%s\n' "$3.tar.gz" 'SHA256SUMS'
        ;;
    "release download")
        asset="$3.tar.gz" destination=""
        while [ "$#" -gt 0 ]; do
            if [ "$1" = --dir ]; then destination=$2; shift 2; else shift; fi
        done
        cp "$FIXTURE_RELEASE_DIR/$asset" "$destination/"
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

cat > "$HOME/.local/bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GIT_CALLS"
if [ "${MOCK_GIT_NETWORK_FAILURE:-0}" = 1 ]; then
    case " $* " in *' fetch '*|*' ls-remote '*) exit 1 ;; esac
fi
if [ "${MOCK_INSTALLER_URL:-0}" = 1 ]; then
    case "$*" in *'remote get-url upstream') printf 'https://github.com/KofLang/Kof4j.git\n'; exit 0 ;; esac
fi
exec /usr/bin/git "$@"
MOCK_GIT
chmod +x "$HOME/.local/bin/git"

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

# Keep a known active/previous pair and reset it before each independent case.
config="$XDG_CONFIG_HOME/kof-main-sync/config"
state="$XDG_STATE_HOME/kof-main-sync/installed.state"
link="$HOME/.local/bin/kof"
new_install="$XDG_DATA_HOME/kof/kof-1.1.0-linux-x86_64"
"$tool" run >/dev/null
cp "$config" "$TMP_ROOT/base.config"
cp "$state" "$TMP_ROOT/base.state"
cp "$old_install/bin/kof" "$TMP_ROOT/old.kof"
reset_case() {
    cp "$TMP_ROOT/base.config" "$config"
    cp "$TMP_ROOT/base.state" "$state"
    cp "$TMP_ROOT/old.kof" "$old_install/bin/kof"
    ln -sfn "$new_install/bin/kof" "$link"
    : > "$MOCK_GH_CALLS"
    : > "$MOCK_GIT_CALLS"
}
set_skip() { printf 'SKIP_KOF_VERSIONS=%s\n' "$1" >> "$config"; }
assert_install_unchanged() {
    assert_eq "$(readlink "$link")" "$new_install/bin/kof" "active symlink preserved"
    cmp -s "$TMP_ROOT/base.state" "$state" || fail "installation state changed"
}

reset_case
set_skip ''
assert_exit 0 "$tool" run
assert_eq "$("$link" version)" 'kof 1.1.0'
assert_contains "$MOCK_GH_CALLS" 'release view'
pass "empty skip list preserves normal release behavior"

reset_case
set_skip ' 1.1.00 , 0.6.70 , 2.0.0-beta '
assert_exit 0 "$tool" run
assert_contains "$MOCK_GH_CALLS" 'release view'
"$tool" status > "$TMP_ROOT/status.out"
assert_contains "$TMP_ROOT/status.out" 'Skipped Kof versions: 1.1.00,0.6.70,2.0.0-beta'
pass "multiple entries trim spaces and compare complete versions exactly"

# The shell expression is intentionally literal untrusted configuration data.
# shellcheck disable=SC2016
for invalid in ',1.1.0' '1.1.0,' '1.0.0,,1.1.0' '1.1.0 1.0.0' 'v1.1.0' '../1.1.0' '$(touch PWNED)' '1.1.0;touch PWNED'; do
    reset_case
    set_skip "$invalid"
    assert_exit 20 "$tool" run
    assert_contains "$TMP_ROOT/command.out" 'invalid SKIP_KOF_VERSIONS entry'
    assert_install_unchanged
    if [ -s "$MOCK_GH_CALLS" ] || [ -s "$MOCK_GIT_CALLS" ]; then
        fail "invalid config reached Git or release API"
    fi
done
[ ! -e "$ROOT/PWNED" ] || fail "configuration executed shell code"
pass "invalid lists diagnose exit 20 before any installation or Git changes"

reset_case
set_skip '1.1.0'
"$tool" status > "$TMP_ROOT/status.out"
assert_contains "$TMP_ROOT/status.out" 'Warning: active Kof 1.1.0 is blocked'
assert_exit 10 "$tool" run --dry-run
assert_contains "$TMP_ROOT/command.out" 'Would restore previous Kof 1.0.0'
assert_contains "$TMP_ROOT/command.out" 'release skipped by SKIP_KOF_VERSIONS: 1.1.0'
assert_install_unchanged
[ ! -s "$MOCK_GH_CALLS" ] || fail "blocked dry run called release API"
assert_not_contains "$MOCK_GIT_CALLS" 'refs/tags/'
pass "dry run reports recovery and release block without changing link or state"

reset_case
set_skip ' 0.6.7, 1.1.0 '
assert_exit 10 "$tool" run
assert_eq "$("$link" version)" 'kof 1.0.0'
assert_contains "$state" "ACTIVE_PATH=$old_install"
assert_contains "$state" 'ACTIVE_VERSION=1.0.0'
assert_contains "$state" "PREVIOUS_PATH=$new_install"
assert_contains "$XDG_STATE_HOME/kof-main-sync/sync.log" 'phase=recovery result=restored version=1.0.0'
cp "$state" "$TMP_ROOT/recovered.state"
assert_exit 10 "$tool" run
cmp -s "$TMP_ROOT/recovered.state" "$state" || fail "second run rewrote recovered state"
[ ! -s "$MOCK_GH_CALLS" ] || fail "blocked installed release called release API"
assert_not_contains "$MOCK_GIT_CALLS" 'refs/tags/'
assert_exit 20 "$tool" rollback
assert_contains "$TMP_ROOT/command.out" 'blocked by SKIP_KOF_VERSIONS'
assert_eq "$("$link" version)" 'kof 1.0.0'
cmp -s "$TMP_ROOT/recovered.state" "$state" || fail "refused rollback rewrote state"
pass "recovery restores previous version and repeated runs and rollback cannot reactivate the blocked release"

reset_case
set_skip '1.1.0'
touch "$HOME/projects/kof/untracked"
assert_exit 10 "$tool" run
assert_eq "$("$link" version)" 'kof 1.0.0'
rm "$HOME/projects/kof/untracked"
pass "recovery precedes a dirty checkout safety stop"

reset_case
set_skip '1.1.0'
assert_exit 20 env MOCK_GIT_NETWORK_FAILURE=1 "$tool" run
assert_eq "$("$link" version)" 'kof 1.0.0'
assert_contains "$state" 'ACTIVE_VERSION=1.0.0'
assert_contains "$XDG_STATE_HOME/kof-main-sync/sync.log" 'reason=fetch-upstream'
pass "recovery precedes a failed network fetch"

for failure in blocked missing unrecorded mismatch version info no-embedded; do
    reset_case
    set_skip '1.1.0'
    case "$failure" in
        blocked) set_skip '1.1.0,1.0.0'; reason='blocked by SKIP_KOF_VERSIONS' ;;
        missing) sed -i "s|^PREVIOUS_PATH=.*|PREVIOUS_PATH=$TMP_ROOT/missing|" "$state"; reason='no valid previous installation' ;;
        unrecorded) sed -i 's/^PREVIOUS_VERSION=.*/PREVIOUS_VERSION=/' "$state"; reason='invalid recorded previous version' ;;
        mismatch) sed -i 's/kof 1.0.0/kof 1.0.1/' "$old_install/bin/kof"; reason='previous version mismatch' ;;
        version) sed -i "s/version) .*/version) printf 'kof 1.0.0\\\\n'; exit 1 ;;/" "$old_install/bin/kof"; reason='failed version check' ;;
        info) sed -i "s/info) .*/info) printf '(embedded)\\\\n'; exit 1 ;;/" "$old_install/bin/kof"; reason='failed info check' ;;
        no-embedded) sed -i 's/(embedded)/(system)/' "$old_install/bin/kof"; reason='no embedded JDK' ;;
    esac
    cp "$state" "$TMP_ROOT/failed.state"
    for mode in normal dry-run; do
        if [ "$mode" = normal ]; then assert_exit 20 "$tool" run; else assert_exit 20 "$tool" run --dry-run; fi
        assert_contains "$TMP_ROOT/command.out" "$reason"
        assert_eq "$(readlink "$link")" "$new_install/bin/kof"
        cmp -s "$TMP_ROOT/failed.state" "$state" || fail "$failure recovery changed state"
    done
    if [ -s "$MOCK_GH_CALLS" ] || [ -s "$MOCK_GIT_CALLS" ]; then
        fail "failed recovery continued into Git or release phases"
    fi
done
pass "invalid predecessors preserve active link/state and fail before synchronization"

reset_case
set_skip '1.1.0'
printf 'INSTALL_KOF=false\n' >> "$config"
assert_exit 0 "$tool" run
assert_install_unchanged
pass "INSTALL_KOF=false disables automatic recovery"

reset_case
set_skip '1.1.0'
exec 8>"$XDG_STATE_HOME/kof-main-sync/sync.lock"
flock -n 8
assert_exit 11 "$tool" run
assert_exit 11 "$tool" run --dry-run
assert_exit 11 "$tool" rollback
assert_install_unchanged
flock -u 8
exec 8>&-
pass "recovery, dry run, and rollback honor the same held lock"

reset_case
set_skip '1.1.0'
assert_exit 10 "$tool" run
mv "$new_install" "$TMP_ROOT/blocked-dist"
assert_exit 10 "$tool" run
[ ! -e "$new_install" ] || fail "blocked release was downloaded"
[ ! -s "$MOCK_GH_CALLS" ] || fail "blocked absent release reached release API"
mv "$TMP_ROOT/blocked-dist" "$new_install"
pass "blocked release is skipped before consulting or downloading release assets"

# A new allowed release must still pass the existing tag, checksum and layout gates.
printf '1.2.0\n' > "$TMP_ROOT/seed/VERSION"
git -C "$TMP_ROOT/seed" commit -am 'later release' >/dev/null
later_sha=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
git -C "$TMP_ROOT/seed" push upstream main >/dev/null
assert_exit 10 "$tool" run
assert_eq "$("$link" version)" 'kof 1.0.0'
git -C "$TMP_ROOT/seed" tag kof-1.2.0-linux-x86_64 "$latest_sha"
git -C "$TMP_ROOT/seed" push upstream refs/tags/kof-1.2.0-linux-x86_64 >/dev/null
assert_exit 10 "$tool" run
assert_contains "$TMP_ROOT/command.out" 'Release does not yet match main'
git -C "$TMP_ROOT/seed" tag -f kof-1.2.0-linux-x86_64 "$later_sha" >/dev/null
git -C "$TMP_ROOT/seed" push --force upstream refs/tags/kof-1.2.0-linux-x86_64 >/dev/null
later_dist="$TMP_ROOT/dist/kof-1.2.0-linux-x86_64"
cp -a "$dist" "$later_dist"
sed -i 's/1.1.0/1.2.0/g' "$later_dist/bin/kof" "$later_dist/VERSION"
(cd "$TMP_ROOT/dist" && tar -czf "$FIXTURE_RELEASE_DIR/kof-1.2.0-linux-x86_64.tar.gz" kof-1.2.0-linux-x86_64)
printf '%064d  kof-1.2.0-linux-x86_64.tar.gz\n' 0 > "$FIXTURE_RELEASE_DIR/SHA256SUMS"
assert_exit 20 "$tool" run
assert_eq "$("$link" version)" 'kof 1.0.0'
assert_contains "$XDG_STATE_HOME/kof-main-sync/sync.log" 'package-validation-2'
(cd "$FIXTURE_RELEASE_DIR" && sha256sum kof-1.2.0-linux-x86_64.tar.gz > SHA256SUMS)
assert_exit 0 "$tool" run
assert_eq "$("$link" version)" 'kof 1.2.0'
assert_contains "$state" "ACTIVE_SHA=$later_sha"
assert_eq "$(git --git-dir="$TMP_ROOT/origin.git" rev-parse main)" "$later_sha"
pass "later allowed release installs only after tag and checksum validation"

# The tracking ref may rewind, but the user's local branch must never reset.
git --git-dir="$TMP_ROOT/upstream.git" update-ref refs/heads/main "$initial_sha"
assert_exit 10 "$tool" run
assert_eq "$(git -C "$HOME/projects/kof" rev-parse upstream/main)" "$initial_sha"
assert_eq "$(git -C "$HOME/projects/kof" rev-parse main)" "$later_sha"
assert_contains "$XDG_STATE_HOME/kof-main-sync/sync.log" 'reason=local-exclusive-or-diverged'
pass "rewritten upstream updates tracking reference and preserves divergent local main"

git --git-dir="$TMP_ROOT/upstream.git" update-ref refs/heads/main "$later_sha"
git -C "$TMP_ROOT/seed" checkout --orphan rewritten >/dev/null 2>&1
git -C "$TMP_ROOT/seed" commit -am rewritten >/dev/null
rewritten_sha=$(git -C "$TMP_ROOT/seed" rev-parse HEAD)
git -C "$TMP_ROOT/seed" push origin rewritten:main --force >/dev/null
assert_exit 10 "$tool" run
assert_eq "$(git -C "$HOME/projects/kof" rev-parse origin/main)" "$rewritten_sha"
assert_eq "$(git --git-dir="$TMP_ROOT/origin.git" rev-parse main)" "$rewritten_sha"
assert_contains "$XDG_STATE_HOME/kof-main-sync/sync.log" 'reason=ahead-or-diverged'
pass "rewritten fork updates tracking reference without forcing the remote branch"
git --git-dir="$TMP_ROOT/origin.git" update-ref refs/heads/main "$later_sha"

# Exercise the actual installer twice with command shims, without real cron/GitHub.
cp "$config" "$TMP_ROOT/pre-install.config"
sed -i '/^SKIP_KOF_VERSIONS=/d' "$config"
set_skip '0.6.7, 1.1.0'
cp "$HOME/.local/bin/git" "$TMP_ROOT/mock-bin/git"
cat > "$TMP_ROOT/mock-bin/systemctl" <<'MOCK_SYSTEMCTL'
#!/usr/bin/env bash
exit 0
MOCK_SYSTEMCTL
chmod +x "$TMP_ROOT/mock-bin/systemctl"
for attempt in 1 2; do
    assert_exit 0 env PATH="$TMP_ROOT/mock-bin:/usr/bin:/bin" MOCK_INSTALLER_URL=1 "$ROOT/install.sh" --no-origin
    assert_contains "$config" 'SKIP_KOF_VERSIONS=0.6.7, 1.1.0'
    cmp -s "$tool" "$HOME/.local/bin/kof-main-sync" || fail "installer attempt $attempt did not deploy current command"
done
assert_eq "$(grep -c '# kof-main-sync$' "$MOCK_CRONTAB_FILE")" 1
cp "$TMP_ROOT/pre-install.config" "$config"
pass "reinstall preserves the existing skip list and deploys the current executable"

bash -n "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/bin/kof-main-sync" "$ROOT/tests/run.sh"
pass "all shell entrypoints parse"

printf '1..%d\n' "$pass_count"
