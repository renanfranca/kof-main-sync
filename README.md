# kof-main-sync

Keep a local [Kof](https://github.com/KofLang/Kof4j) `main` checkout, an existing personal fork, and a validated Linux installation in sync.

[Leia em português](README.pt_BR.md)

## What it does

`kof-main-sync` runs three independent phases:

1. Fast-forwards a clean local `main` checkout from `upstream/main`, keeping source code and documentation current for other projects.
2. Fast-forwards an existing personal fork when its `main` is an ancestor of the synchronized commit.
3. Installs an official Linux Kof release only when its tag points to that exact `main` commit and its checksum and package layout validate.

With `INSTALL_KOF=true`, each run first restores the recorded previous installation if the active compiler is listed in `SKIP_KOF_VERSIONS`. Recovery runs under the shared installation lock before checking the working tree or accessing Git remotes, so a dirty checkout or network failure does not prevent recovery.

A release failure never rolls back current documentation. There is no local-build fallback: if Kof's release CI does not publish an artifact, the currently installed compiler remains active.

The tool never uses hard reset, rebase, merge commits, force push, or automatic commit deletion.

## Supported systems and requirements

The initial supported environments are Debian, Ubuntu, and WSL2. Required commands:

```text
bash git gh flock crontab curl tar sha256sum
```

Authenticate GitHub CLI before installation:

```bash
gh auth login
```

The installer validates dependencies and cron availability but never invokes `sudo`, installs packages, starts services, or creates a GitHub fork.

## Install

Reviewable installation from a local clone is the supported method:

```bash
git clone https://github.com/renanfranca/kof-main-sync.git \
  ~/projects/kof-main-sync
cd ~/projects/kof-main-sync
./install.sh --dry-run
./install.sh
```

By default it:

- manages Kof at `$HOME/projects/kof`;
- uses `KofLang/Kof4j` as `upstream`;
- detects `$GITHUB_USER/Kof4j` only if it is an existing fork of the upstream repository;
- installs the command at `$HOME/.local/bin/kof-main-sync`;
- writes XDG configuration and state;
- schedules a run every five minutes.

The installer performs an initial synchronization dry-run. The first real synchronization happens when cron runs or when you invoke:

```bash
kof-main-sync run
```

### Installer options

```text
--repo-dir <path>       use another Kof checkout
--origin <owner/repo>   use an explicit existing fork
--no-origin             disable personal fork synchronization
--no-kof-install        update source/docs without changing the installed Kof
--interval <minutes>    cron interval from 1 to 59
--dry-run               validate without changing files, remotes, or cron
```

If the checkout does not exist, the installer clones upstream and configures the remotes. Existing remotes are validated and never silently replaced.

## Commands

```bash
kof-main-sync run
kof-main-sync run --dry-run
kof-main-sync status
kof-main-sync logs
kof-main-sync logs --follow
kof-main-sync rollback
kof-main-sync install
kof-main-sync uninstall
```

`install` and `uninstall` manage only the marked cron entry. The repository-level `uninstall.sh` also removes the installed command and configuration while preserving Kof checkouts, distributions, and logs.

Exit status:

| Code | Meaning |
|---:|---|
| `0` | All enabled phases succeeded or were already current |
| `10` | A phase was safely skipped, such as dirty checkout, pending release, or ignored version |
| `11` | Another run holds the lock |
| `20+` | Configuration, network, authentication, integrity, or installation error |

## Configuration and paths

Defaults follow the XDG base directory specification:

```text
Command:       $HOME/.local/bin/kof-main-sync
Configuration:${XDG_CONFIG_HOME:-$HOME/.config}/kof-main-sync/config
State and log: ${XDG_STATE_HOME:-$HOME/.local/state}/kof-main-sync/
Kof installs:  ${XDG_DATA_HOME:-$HOME/.local/share}/kof/
Kof command:   $HOME/.local/bin/kof
```

Configuration is parsed as data and is never sourced as shell code. See [`config/config.example`](config/config.example).

To ignore a problematic Kof release, edit the existing configuration:

```ini
SKIP_KOF_VERSIONS=0.6.7
```

Multiple exact versions can be separated by commas, for example `SKIP_KOF_VERSIONS=0.6.7, 0.6.5`. Spaces around entries are optional. Each version must start with a digit and contain only ASCII letters, digits, dots, underscores, or hyphens. Empty entries between commas, shell expressions, and other invalid values produce a diagnostic and exit `20` without changing the installation. An absent key or empty value keeps the existing behavior. Reinstalling preserves the configured list.

Ignoring `0.6.7` does not ignore `0.6.70` or a future `0.6.8`. An allowed later version still installs automatically once the existing release, checksum, package, and tag/commit checks pass. Ignored versions are rejected before tag/release queries, asset downloads, or activation of distributions already on disk; a skipped release returns `10`. `status` displays the list and warns when the actual active compiler is ignored. Logs record blocks and recoveries.

The marked crontab line is:

```cron
*/5 * * * * /home/<user>/.local/bin/kof-main-sync run >/dev/null 2>&1 # kof-main-sync
```

All other crontab entries are preserved byte-for-byte.

## Release verification and rollback

For Kof version `<version>`, the tool requires the tag:

```text
kof-<version>-linux-x86_64
```

The tag must resolve to the current synchronized commit. The release must contain the matching archive and `SHA256SUMS`; the checksum, archive paths, distribution layout, embedded JDK, `kof version`, and `kof info` must all validate before activation.

Activation replaces only the `~/.local/bin/kof` symlink through an atomic rename. Previous distributions remain on disk. Restore the last one with:

```bash
kof-main-sync rollback
```

Both automatic recovery and `rollback` validate the actual previous compiler version against `PREVIOUS_VERSION` in `installed.state`, run `version` and `info`, and require the embedded JDK. A blocked, missing, mismatched, or failing previous installation causes exit `20` with a diagnostic, preserving the active symlink and installation state. The tool never searches for or downloads a different recovery candidate. Recovery records the restored distribution as active and retains the replaced distribution as previous; `rollback` refuses to reactivate it while it is ignored.

`run`, `run --dry-run`, and `rollback` share a lock and return `11` if it is occupied. The installer also uses this lock when replacing the executable and configuration. `run --dry-run` reports planned recovery and release blocks without changing the Kof symlink or `installed.state`. It can update remote tracking references and logs. `INSTALL_KOF=false` disables automatic recovery and release installation; an explicit `rollback` still enforces the skip list.

Old distributions are never deleted automatically. After confirming a version is no longer needed for rollback, remove its specific directory manually from `~/.local/share/kof/`.

## Safety stops and recovery

The checkout phase is skipped when:

- the working tree has tracked or untracked changes;
- the current branch is not `main` or HEAD is detached;
- merge, rebase, cherry-pick, revert, or bisect is in progress;
- local `main` has exclusive commits or diverges from upstream.

The fork phase is skipped when its `main` is ahead or divergent. Resolve these Git conditions manually; the tool will retry on the next run.

Fetches accept rewritten history in local remote tracking references (`upstream/main` and `origin/main`). The working branch and fork still advance only by fast-forward; divergence requires manual recovery. Automatic synchronization never resets a working branch or force pushes the fork.

An unavailable release is expected while Kof's CI is running. Documentation and the fork can advance while the installed compiler remains on the last validated version.

Use `kof-main-sync status` and `kof-main-sync logs` to diagnose a stop. Logs rotate at 5 MiB with five previous files retained and never include GitHub tokens.

## WSL2

Cron runs only while the WSL2 distribution is active. Missed schedules are not replayed, but the next scheduled run converges directly to the latest safe state. With systemd-enabled WSL, verify cron using:

```bash
systemctl is-active cron
```

## Development

Run the isolated suite:

```bash
tests/run.sh
```

It uses temporary HOME, Git repositories, release packages, and command shims; it does not touch the real Kof checkout, fork, crontab, or installation.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
