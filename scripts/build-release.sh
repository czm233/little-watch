#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
output_dir="${OUTPUT_DIR:-${project_root}/build/release}"
derived_data_path="${DERIVED_DATA_PATH:-${project_root}/build/DerivedData-release}"

if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 必须使用 x.y.z 格式，当前值：${version}"
    exit 1
fi

mkdir -p "${output_dir}" "${derived_data_path}"

xcodebuild \
    -project "${project_root}/LittleWatch.xcodeproj" \
    -scheme LittleWatch \
    -configuration Release \
    -derivedDataPath "${derived_data_path}" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="${version}" \
    CURRENT_PROJECT_VERSION="${build_number}" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

app_path="${derived_data_path}/Build/Products/Release/LittleWatch.app"
executable_path="${app_path}/Contents/MacOS/LittleWatch"
dmg_name="LittleWatch-${version}-macOS-universal.dmg"
dmg_path="${output_dir}/${dmg_name}"
checksum_path="${dmg_path}.sha256"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/little-watch-dmg.XXXXXX")"

cleanup() {
    rm -rf "${staging_dir}"
}
trap cleanup EXIT

if [[ ! -d "${app_path}" || ! -f "${executable_path}" ]]; then
    print -u2 "没有找到 Release 应用：${app_path}"
    exit 1
fi

architectures="$(lipo -archs "${executable_path}")"
if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " != *" x86_64 "* ]]; then
    print -u2 "应用不是通用架构，当前架构：${architectures}"
    exit 1
fi

codesign --force --deep --sign - "${app_path}"
codesign --verify --deep --strict "${app_path}"

ditto "${app_path}" "${staging_dir}/LittleWatch.app"
ln -s /Applications "${staging_dir}/Applications"

rm -f "${dmg_path}" "${checksum_path}"
hdiutil create \
    -volname "Little Watch" \
    -srcfolder "${staging_dir}" \
    -format UDZO \
    -ov \
    "${dmg_path}"
hdiutil verify "${dmg_path}"

(
    cd "${output_dir}"
    shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256"
)

print "Release package: ${dmg_path}"
print "Checksum: ${checksum_path}"
print "Architectures: ${architectures}"
