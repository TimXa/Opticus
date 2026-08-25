#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
build_root="${OPTICUS_BUILD_ROOT:-${PWD}/.build/release-build}"
mkdir -p "${build_root}"
swift build -c release --scratch-path "${build_root}"

app_dir="${build_root}/release-app/Opticus.app"
rm -rf "${app_dir}"
mkdir -p "${app_dir}/Contents/MacOS"
cp "${build_root}/release/Opticus" "${app_dir}/Contents/MacOS/Opticus"
cp Support/Info.plist "${app_dir}/Contents/Info.plist"
mkdir -p "${app_dir}/Contents/Resources"
ditto Sources/Opticus/Resources "${app_dir}/Contents/Resources"
cp THIRD_PARTY_NOTICES.md "${app_dir}/Contents/Resources/THIRD_PARTY_NOTICES.md"

signing_identity="${OPTICUS_SIGNING_IDENTITY:--}"
if [[ "${signing_identity}" == "-" ]]; then
  discovered_identity="$({ security find-identity -v -p codesigning 2>/dev/null || true; } \
    | awk -F'"' '/Apple Development:/ { print $2; exit }')"
  if [[ -n "${discovered_identity}" ]]; then
    signing_identity="${discovered_identity}"
  fi
fi
xattr -cr "${app_dir}"
xattr -dr com.apple.FinderInfo "${app_dir}" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "${app_dir}" 2>/dev/null || true
xattr -d com.apple.FinderInfo "${app_dir}" 2>/dev/null || true
xattr -d com.apple.FinderInfo \
  "${app_dir}/Contents/Resources/EyeglassesClassifier.mlmodelc" 2>/dev/null || true
codesign --force --deep --sign "${signing_identity}" \
  --entitlements Support/Opticus.entitlements "${app_dir}"
codesign --verify --deep --strict "${app_dir}"

mkdir -p "${PWD}/dist"
archive="${PWD}/dist/Opticus-macOS.zip"
rm -f "${archive}"
ditto -c -k --keepParent --norsrc "${app_dir}" "${archive}"

echo "Built ${app_dir}"
echo "Release archive ${archive} (signed: ${signing_identity})"
