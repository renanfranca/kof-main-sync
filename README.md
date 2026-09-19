# kof-main-sync

Keep a local [Kof](https://github.com/KofLang/Kof4j) `main` checkout, an existing personal fork, and a validated Linux installation in sync.

[Leia em português](README.pt_BR.md)

## What it does

`kof-main-sync` runs three independent phases:

1. Fast-forwards a clean local `main` checkout from `upstream/main`, keeping source code and documentation current for other projects.
2. Fast-forwards an existing personal fork when its `main` is an ancestor of the synchronized commit.
3. Installs an official Linux Kof release only when its tag points to that exact `main` commit and its checksum and package layout validate.

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
| `10` | A phase was safely skipped, such as dirty checkout or pending release |
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

Old distributions are never deleted automatically. After confirming a version is no longer needed for rollback, remove its specific directory manually from `~/.local/share/kof/`.

## Safety stops and recovery

The checkout phase is skipped when:

- the working tree has tracked or untracked changes;
- the current branch is not `main` or HEAD is detached;
- merge, rebase, cherry-pick, revert, or bisect is in progress;
- local `main` has exclusive commits or diverges from upstream.

The fork phase is skipped when its `main` is ahead or divergent. Resolve these Git conditions manually; the tool will retry on the next run.

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
