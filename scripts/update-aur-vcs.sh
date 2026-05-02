#!/usr/bin/env bash
set -euo pipefail

pkgbase="${PKGBASE:-chrony-git}"
aur_remote="${AUR_REMOTE:-ssh://aur@aur.archlinux.org/${pkgbase}.git}"
workdir="${WORKDIR:-${RUNNER_TEMP:-/tmp}/aur-update-${pkgbase}}"
aur_dir="${workdir}/${pkgbase}"
dry_run="${DRY_RUN:-0}"

if [[ -z "${workdir}" || "${workdir}" == "/" ]]; then
    printf 'Refusing unsafe WORKDIR: %s\n' "${workdir}" >&2
    exit 1
fi

rm -rf -- "${workdir}"
mkdir -p -- "${workdir}"

git clone "${aur_remote}" "${aur_dir}"
cd "${aur_dir}"

old_pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"

makepkg --nobuild --nodeps --noconfirm
makepkg --printsrcinfo > .SRCINFO

new_pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"

if git diff --quiet -- PKGBUILD .SRCINFO; then
    printf 'No AUR metadata update needed. pkgver is still %s.\n' "${new_pkgver}"
    exit 0
fi

printf 'AUR metadata changed: %s -> %s\n' "${old_pkgver}" "${new_pkgver}"
git diff -- PKGBUILD .SRCINFO

if [[ "${dry_run}" == "1" ]]; then
    printf 'DRY_RUN=1 set; skipping commit and push.\n'
    exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-chrony-git updater}"
git config user.email "${GIT_AUTHOR_EMAIL:-actions@github.com}"

git add PKGBUILD .SRCINFO
git commit -m "Update ${pkgbase} to ${new_pkgver}"
git push origin HEAD:master
