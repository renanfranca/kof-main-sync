# Deliver a safe Kof main synchronizer

## Purpose and success

Create and publish `renanfranca/kof-main-sync`, a reusable Debian/Ubuntu/WSL2 tool that keeps a clean local Kof `main` checkout current for documentation consumers, fast-forwards an existing personal fork when safe, and atomically activates only an official Linux Kof release whose tag matches the synchronized commit. Success means the installer, command, cron integration, rollback, bilingual documentation, and automated tests work without modifying tracked files in the Kof checkout or installing system packages.

## Context and limits

The source repository lives at `/home/renanfranca/projects/kof-main-sync`; the default managed Kof checkout is `$HOME/projects/kof`. Runtime files follow XDG defaults under `$HOME/.config`, `$HOME/.local/state`, and `$HOME/.local/share`. The tool may clone and configure a missing Kof checkout, but it must not create forks, use destructive Git operations, compile unreleased Kof commits, silently invoke `sudo`, or alter unrelated crontab entries. Initial supported systems are Debian, Ubuntu, and WSL2.

## Milestones

1. Establish the public tool contract and installer. Add the executable, configuration example, installer, uninstaller, license, and ignore rules. Validate shell syntax and dry-run installation behavior.
2. Implement and exercise synchronization behavior. Cover Git safety gates, optional fork detection/push, exact-SHA release validation, atomic activation, status, logs, locking, and rollback with isolated fixtures.
3. Reconcile bilingual documentation and automation. Add English and Portuguese usage/recovery documentation plus CI for ShellCheck and tests; run the complete local validation suite.
4. Install and publish. Create the public GitHub repository, commit and push the validated source, install it locally, run the real dry-run and synchronization, then verify cron, Kof version, status, logs, and rollback availability without performing a rollback.

## Progress

- [x] Target path and GitHub repository name verified as available.
- [x] Milestone 1 complete: installer, XDG configuration, command, license, and safe cron management implemented.
- [x] Milestone 2 complete: isolated behavioral suite passes all synchronization, release activation, rollback, lock, and safety-stop scenarios.
- [x] Milestone 3 complete: bilingual documentation, CI, shell parsing, and ShellCheck validation are green.
- [x] Milestone 4 complete: public repository created, source published, tool installed, cron active, fork converged, and Kof 0.4.7-beta activated with 0.4.2-beta retained for rollback.

## Validation

- `bash -n install.sh uninstall.sh bin/kof-main-sync tests/run.sh` exits 0.
- `tests/run.sh` exits 0 using temporary HOME, Git repositories, release fixtures, and command shims.
- ShellCheck exits 0 locally through the official `koalaman/shellcheck:stable` container; CI runs the packaged Ubuntu ShellCheck command.
- `./install.sh --dry-run` reports intended paths and dependencies without changing user state.
- Installed `kof-main-sync run --dry-run`, `status`, and `logs` succeed in the real environment.
- The real managed run converges the clean Kof checkout and fork, installs the exact official release when available, and leaves `kof version` and `kof info` healthy.
- GitHub Actions completes successfully on the public `main` branch.

Observed final evidence:

- `bash -n install.sh uninstall.sh bin/kof-main-sync tests/run.sh`: exit 0.
- ShellCheck through the official container: exit 0.
- `tests/run.sh`: 9 scenarios passed.
- `./install.sh --dry-run`: exit 0 without user-state changes.
- Installed `kof-main-sync run`: exit 0; checkout, upstream, and origin converged to `af743ef4ece04a247386ffb790f4c4a85bcf2b9e`.
- Installed `kof version` reports `0.4.7-beta`; `kof info` reports the embedded JDK; previous `0.4.2-beta` installation remains recorded.
- Public GitHub Actions run for the implementation and CI correction completed successfully.

## Decisions

- Use an existing authenticated user's fork only after verifying its parent is `KofLang/Kof4j`; never create a fork implicitly. This preserves a reusable default without surprising external mutations.
- Keep documentation/fork synchronization independent from binary activation. A missing or failed release must not roll back current documentation.
- Require an exact release-tag-to-commit match and official checksums, with no local-build fallback. This makes GitHub's release gate the trust boundary for executable installation.
- Retain old validated Kof installations. Automatic deletion would make rollback destructive and could consume user-owned installations.

## Risks

- The working checkout may be dirty or on another branch; the tool must skip its update instead of disrupting user work.
- Cron has a minimal environment; installed paths and configuration discovery must not depend on an interactive shell.
- Release archives are external input; extraction must reject unsafe member paths before activation.
- Initial origin is hundreds of commits behind; only normal fast-forward push is allowed, and any concurrent remote update must fail safely.

## Documentation

`README.md` and `README.pt_BR.md` will explain installation, the three independent synchronization phases, configuration, WSL2 scheduling limits, release gating, status/log interpretation, rollback, manual cleanup, and uninstall semantics.

## Rollout and recovery

The installer first validates and performs a dry run, then writes only XDG-owned files and one marked crontab entry. Binary activation uses a temporary symlink followed by atomic rename. The prior verified target is recorded and can be restored with `rollback`. Uninstall removes only the managed cron entry and installed command/config, leaving Kof checkouts, logs, and distributions intact.
