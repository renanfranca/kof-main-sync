# Skip problematic Kof releases and recover WSL

## Purpose and success

Implement the approved plan: parse `SKIP_KOF_VERSIONS` in the existing data-only
configuration, prevent ignored release activation, and restore the recorded
previous installation when the active compiler is ignored. Deliver a validated
WSL installation with Kof 0.6.6 active and 0.6.7 blocked, plus local Kof `main`
and the personal fork aligned to the upstream commit observed during recovery.

## Context and limits

Source: `/home/renanfranca/projects/kof-main-sync`. Managed checkout:
`/home/renanfranca/projects/kof`. Configuration:
`~/.config/kof-main-sync/config`. State and shared lock:
`~/.local/state/kof-main-sync/{installed.state,sync.lock}`. Installations:
`~/.local/share/kof/`; compiler link: `~/.local/bin/kof`.

Inspection on 2026-10-29 confirmed Kof 0.6.7 active, previous Kof 0.6.6 recorded
and healthy with embedded JDK, a clean Kof `main`, and fork sync enabled.
Implementation uses branch `skip-kof-versions`. Do not delete distributions.
Automatic Git updates remain fast-forward only. The user's authorization allows
separate, one-time local reset and fork update with an explicit observed remote
SHA lease. No Kof source changes, upstream push, or release promotion is in scope.

## Milestones

1. Implement configuration, recovery, shared locking, skip diagnostics/status,
   and forced remote tracking fetches in `bin/kof-main-sync`. Update `install.sh`
   to preserve the skip list and replace the executable atomically under lock.
   Extend `tests/run.sh` around public commands and observable state.
2. Update `config/config.example`, `README.md`, and `README.pt_BR.md`. Validate
   shell syntax, ShellCheck, isolated tests, and assertion sensitivity to
   incorrect behavior. Reconcile every approved acceptance scenario.
3. Deploy the validated executable and block 0.6.7 under the cron lock. Exercise
   dry-run and recovery, then re-query upstream/fork heads and perform the
   authorized one-time Git realignment. Verify compiler version/info, link,
   installation state, logs, and remote alignment.

## Progress

- [x] Inspect source, tests, installer, configuration, cron, Kof sources and
      installed distributions; create the implementation branch.
- [x] Implement behavior through isolated public-command tests: 24 scenarios pass.
- [x] Update both READMEs and the configuration example; ShellCheck passes using
      the existing official `koalaman/shellcheck:stable` Docker image.
- [x] Complete syntax/suite final pass and assertion sensitivity audit: all 24
      scenarios pass and all nine deliberately incorrect variants are rejected.
- [x] Deploy atomically under the cron lock, recover Kof 0.6.6, align local/fork
      main, and capture operational proof.

## Validation

Required commands: `bash -n install.sh uninstall.sh bin/kof-main-sync tests/run.sh`,
`shellcheck install.sh uninstall.sh bin/kof-main-sync tests/run.sh`, and
`tests/run.sh`. Tests use temporary HOME, local bare remotes, fake releases,
and command shims, without touching the real installation or GitHub fork.

Exercise absent/empty/multiple/invalid skip values, exact matching, ignored
release before API/download or disk activation, successful recovery and repeated
runs, recovery before dirty/network Git failure, unavailable/ignored/mismatched
or failing predecessor, rollback refusal, dry-run immutability, shared locking,
later allowed release, reinstall preservation, and rewritten remote history.
Validate checksums and tag/commit gates remain effective for allowed releases.

Milestone 1 evidence: `tests/run.sh` exits 0 (24 scenarios), including actual
installer runs in the isolated fixture. ShellCheck exits 0 through the official
container. The skip list is parsed without shell evaluation, recovery precedes
Git validation/fetch, and both restoration commands use the same predecessor
validation path and lock. Fetches now force only remote tracking refs.

Milestone 2 evidence: syntax parsing and ShellCheck exit 0; 24 public-command
scenarios pass. An independent temporary-copy assertion audit rejects release
queries before skipping, absent recovery, accepted predecessor version mismatch,
ignored `info` failure, modifying dry-run, rollback bypassing the list or lock,
discarding a divergent local branch, and reinstall clearing the list. The audit
script/log are in `/tmp/kof-main-sync-assertion-audit.{py,log}`. Structural review
found no additional refactor necessary within the implemented contract.

Final validation on 2026-10-29: `bash -n` exits 0; ShellCheck in the official
Docker image exits 0; `tests/run.sh` exits 0 with 24 scenarios after the final
code changes. `git diff --check` passes. All requested behavioral acceptance
criteria have evidence. Later allowed release installation, malformed
predecessors, network failure, and competing lock holders were exercised in the
isolated suite; no real future release was installed as part of verification.

Operational evidence at 16:04 America/Bahia:

- The installed executable matches `bin/kof-main-sync` byte for byte, and the
  existing config contains `SKIP_KOF_VERSIONS=0.6.7` with fork sync enabled.
- The real dry-run reported recovery of 0.6.6 while preserving the symlink and
  `installed.state`. The real recovery restored 0.6.6 before the Git divergence
  stop (exit 10).
- `kof version` prints `kof 0.6.6`; `kof info` succeeds and reports Eclipse
  Adoptium 25.0.4.1 `(embedded)`. The symlink points to
  `~/.local/share/kof/kof-0.6.6-linux-x86_64/bin/kof`. State records active SHA
  `7c237861a9035d84b1f7ec4cfddd89daef4c6ddd` and previous version 0.6.7.
- The one-time operation re-observed upstream as
  `b7112fd1db25531da02970ac528ddb00bffe2ccd` and origin as
  `df27d89fc94b56344984ac42579bc8bb40809150`. Only the fork's `main` was pushed,
  with `--force-with-lease=refs/heads/main:df27d89fc94b56344984ac42579bc8bb40809150`.
  Afterwards local `main`, both tracking refs, and both live remote `main` heads
  were independently verified at `b7112fd1db25531da02970ac528ddb00bffe2ccd`.
- Two subsequent normal runs and a dry-run return 10 exclusively because the
  0.6.7 release is ignored; compiler link and state remain unchanged. Real
  `rollback` refuses 0.6.7 with exit 20 and also preserves both.
- The Kof working tree is clean. Cron remains active and its complete crontab
  matches the saved original. Distribution directories remain intact.

Backups and command output are retained in
`/home/renanfranca/.local/state/kof-main-sync/skip-versions-recovery.fSnfjX/`;
`sync.log` records deployment, recovery, the explicit one-time Git operation,
and later blocks. The former local main is also retained at
`refs/kof-main-sync/before-main-realignment-20261029T160352` in the Kof checkout.
Source changes and validation evidence are grouped on `skip-kof-versions`.

## Rollout and recovery

Use the same `sync.lock` as cron for executable/config deployment and one-time
Git realignment. Preserve backups of installed command/config for diagnosis.
Deploy with temporary files and rename. First run with `--dry-run` and compare
compiler link and state; then run normally and verify recovery even if Git is
divergent. Re-query upstream and origin immediately before realignment, require
a clean Kof checkout, and push only `main` using
`--force-with-lease=refs/heads/main:<observed-origin-sha>`. Abort on lease rejection;
subsequent automatic runs use normal push. Keep old distributions available.
