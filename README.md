# chrony-git AUR updater

This repository contains GitHub Actions automation for periodically updating the AUR `chrony-git` package metadata.

The workflow does not publish binary packages. It refreshes the VCS package version in `PKGBUILD`, builds the package in a current Arch container to record linked shared library SONAMEs, regenerates `.SRCINFO`, and pushes metadata changes back to AUR when upstream Chrony has moved or a dependency ABI rebuild is needed.

## How it works

1. GitHub Actions starts on a cron schedule or manual dispatch.
2. The job runs inside an `archlinux:latest` container.
3. It installs the tools needed for AUR packaging and package builds.
4. It configures an SSH key from the `AUR_SSH_PRIVATE_KEY` repository secret.
5. It clones `ssh://aur@aur.archlinux.org/chrony-git.git`.
6. It runs `makepkg --nobuild --nodeps --noconfirm`, which fetches the VCS source and lets `pkgver()` update `PKGBUILD`.
7. It builds the package with `makepkg --syncdeps --noconfirm --needed`.
8. It extracts the built package and records ELF `NEEDED` shared library SONAMEs in `.aur-link-signature`.
9. If `pkgver` changed, it resets `pkgrel` to `1`; otherwise, if the link signature changed, it bumps `pkgrel` so AUR helpers rebuild the package.
10. It regenerates `.SRCINFO` with `makepkg --printsrcinfo`.
11. It commits and pushes only when `PKGBUILD`, `.SRCINFO`, or `.aur-link-signature` changed.

## Required GitHub secret

Add this repository secret:

```text
AUR_SSH_PRIVATE_KEY
```

Use a private SSH key whose public key is registered in your AUR account. The key only needs access to the `chrony-git` AUR package.

## Schedule

The workflow currently runs every 6 hours and can also be triggered manually from the GitHub Actions UI.

Manual runs default to `dry_run=true`, which updates metadata in the runner but skips commit and push. Set `dry_run=false` when you want the manual run to publish changes to AUR.

## Local dry run

From this repository:

```bash
PKGBASE=chrony-git \
AUR_REMOTE=ssh://aur@aur.archlinux.org/chrony-git.git \
DRY_RUN=1 \
./scripts/update-aur-vcs.sh
```

`DRY_RUN=1` performs the clone, metadata refresh, package build, and link signature check, but skips commit and push.

## Notes

This is intentionally separate from the AUR package repository. The AUR repo remains the source of truth for the package, while this repo only stores automation.
