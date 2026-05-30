#!/usr/bin/env bash
set -euo pipefail

pkgbase="${PKGBASE:-chrony-git}"
aur_remote="${AUR_REMOTE:-ssh://aur@aur.archlinux.org/${pkgbase}.git}"
workdir="${WORKDIR:-${RUNNER_TEMP:-/tmp}/aur-update-${pkgbase}}"
aur_dir="${workdir}/${pkgbase}"
dry_run="${DRY_RUN:-0}"
link_signature_file="${LINK_SIGNATURE_FILE:-.aur-link-signature}"

bump_pkgrel() {
    local old_pkgrel new_pkgrel

    old_pkgrel="$(sed -n 's/^pkgrel=//p' PKGBUILD | head -n1)"
    if [[ ! "${old_pkgrel}" =~ ^[0-9]+$ ]]; then
        printf 'Cannot auto-bump non-integer pkgrel: %s\n' "${old_pkgrel}" >&2
        exit 1
    fi

    new_pkgrel="$((old_pkgrel + 1))"
    sed -i "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" PKGBUILD
    printf 'Bumped pkgrel: %s -> %s\n' "${old_pkgrel}" "${new_pkgrel}"
}

reset_pkgrel() {
    local old_pkgrel

    old_pkgrel="$(sed -n 's/^pkgrel=//p' PKGBUILD | head -n1)"
    sed -i 's/^pkgrel=.*/pkgrel=1/' PKGBUILD
    printf 'Reset pkgrel for new pkgver: %s -> 1\n' "${old_pkgrel}"
}

signatures_match() {
    local old_signature_file new_signature_file normalized_new

    old_signature_file="$1"
    new_signature_file="$2"

    if cmp -s "${old_signature_file}" "${new_signature_file}"; then
        return 0
    fi

    # Support migration from the original path-only signature format.
    if grep -q '^/' "${old_signature_file}"; then
        normalized_new="$(mktemp --tmpdir="${workdir}" normalized-signature.XXXXXX)"
        sed 's|^[^/]*/|/|' "${new_signature_file}" > "${normalized_new}"
        if cmp -s "${old_signature_file}" "${normalized_new}"; then
            rm -f -- "${normalized_new}"
            return 0
        fi
        rm -f -- "${normalized_new}"
    fi

    return 1
}

signature_exists() {
    [[ -s "${link_signature_file}" ]]
}

write_link_signature() {
    local extract_dir package package_dir package_name signature_tmp

    extract_dir="$(mktemp -d --tmpdir="${workdir}" link-signature.XXXXXX)"
    signature_tmp="$(mktemp --tmpdir="${workdir}" link-signature-output.XXXXXX)"
    trap 'rm -rf -- "${extract_dir}" "${signature_tmp}"' RETURN

    while IFS= read -r package; do
        package_name="$(bsdtar -xOf "${package}" .PKGINFO | sed -n 's/^pkgname = //p' | head -n1)"
        if [[ -z "${package_name}" ]]; then
            printf 'Cannot read pkgname from package: %s\n' "${package}" >&2
            return 1
        fi

        package_dir="${extract_dir}/${package_name}"
        mkdir -p -- "${package_dir}"
        bsdtar -xf "${package}" -C "${package_dir}"

        find "${package_dir}" -type f -print0 |
            while IFS= read -r -d '' file; do
                if readelf -h "${file}" >/dev/null 2>&1; then
                    readelf -d "${file}" 2>/dev/null |
                        awk -v package="${package_name}" -v path="${file#"${package_dir}"}" '/Shared library:/ {
                            lib = $0
                            sub(/^.*Shared library: \[/, "", lib)
                            sub(/\].*$/, "", lib)
                            print package path ": " lib
                        }'
                fi
            done >> "${signature_tmp}"
    done < <(makepkg --packagelist)

    LC_ALL=C sort -u "${signature_tmp}" > "${link_signature_file}"
    rm -rf -- "${extract_dir}" "${signature_tmp}"
    trap - RETURN
}

if [[ -z "${workdir}" || "${workdir}" == "/" ]]; then
    printf 'Refusing unsafe WORKDIR: %s\n' "${workdir}" >&2
    exit 1
fi

rm -rf -- "${workdir}"
mkdir -p -- "${workdir}"

git clone "${aur_remote}" "${aur_dir}"
cd "${aur_dir}"

old_pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"
old_signature="$(mktemp --tmpdir="${workdir}" old-signature.XXXXXX)"
if [[ -f "${link_signature_file}" ]]; then
    cp -- "${link_signature_file}" "${old_signature}"
else
    : > "${old_signature}"
fi

makepkg --nobuild --nodeps --noconfirm
makepkg --syncdeps --noconfirm --needed
write_link_signature

new_pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -n1)"

if [[ "${old_pkgver}" != "${new_pkgver}" ]]; then
    reset_pkgrel
elif signature_exists && ! signatures_match "${old_signature}" "${link_signature_file}"; then
    printf 'Link signature changed while pkgver stayed at %s. Rebuild release needed.\n' "${new_pkgver}"
    bump_pkgrel
fi

makepkg --printsrcinfo > .SRCINFO

if git diff --quiet -- PKGBUILD .SRCINFO "${link_signature_file}"; then
    printf 'No AUR metadata update needed. pkgver is still %s.\n' "${new_pkgver}"
    exit 0
fi

printf 'AUR metadata changed: %s -> %s\n' "${old_pkgver}" "${new_pkgver}"
git diff -- PKGBUILD .SRCINFO "${link_signature_file}"
git status --short -- "${link_signature_file}"

if [[ "${dry_run}" == "1" ]]; then
    printf 'DRY_RUN=1 set; skipping commit and push.\n'
    exit 0
fi

git config user.name "${GIT_AUTHOR_NAME:-chrony-git updater}"
git config user.email "${GIT_AUTHOR_EMAIL:-actions@github.com}"

git add PKGBUILD .SRCINFO "${link_signature_file}"
git commit -m "Update ${pkgbase} to ${new_pkgver}"
git push origin HEAD:master
