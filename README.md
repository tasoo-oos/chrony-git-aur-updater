# chrony-git AUR updater

This repository contains GitHub Actions automation for periodically updating the AUR `chrony-git` package metadata.

The workflow does not build or publish binary packages. It only refreshes the VCS package version in `PKGBUILD`, regenerates `.SRCINFO`, and pushes those metadata changes back to AUR when upstream Chrony has moved.

## How it works

1. GitHub Actions starts on a cron schedule or manual dispatch.
2. The job runs inside an `archlinux:latest` container.
3. It installs the minimal tools needed for AUR packaging metadata updates.
4. It configures an SSH key from the `AUR_SSH_PRIVATE_KEY` repository secret.
5. It clones `ssh://aur@aur.archlinux.org/chrony-git.git`.
6. It runs `makepkg --nobuild --nodeps --noconfirm`, which fetches the VCS source and lets `pkgver()` update `PKGBUILD`.
7. It regenerates `.SRCINFO` with `makepkg --printsrcinfo`.
8. It commits and pushes only when `PKGBUILD` or `.SRCINFO` changed.

## Required GitHub secret

Add this repository secret:

```text
AUR_SSH_PRIVATE_KEY
```

Use a private SSH key whose public key is registered in your AUR account. The key only needs access to the `chrony-git` AUR package.

## Schedule

The workflow currently runs daily at `03:17 UTC` and can also be triggered manually from the GitHub Actions UI.

Manual runs default to `dry_run=true`, which updates metadata in the runner but skips commit and push. Set `dry_run=false` when you want the manual run to publish changes to AUR.

## Local dry run

From this repository:

```bash
PKGBASE=chrony-git \
AUR_REMOTE=ssh://aur@aur.archlinux.org/chrony-git.git \
DRY_RUN=1 \
./scripts/update-aur-vcs.sh
```

`DRY_RUN=1` performs the clone and metadata refresh but skips commit and push.

## Notes

This is intentionally separate from the AUR package repository. The AUR repo remains the source of truth for the package, while this repo only stores automation.
