#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
output_dir="${OUTPUT_DIR:-${project_root}/build/release}"
derived_data_path="${DERIVED_DATA_PATH:-${project_root}/build/DerivedData-release}"
background_path="${project_root}/scripts/assets/dmg-background.png"

if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 必须使用 x.y.z 格式，当前值：${version}"
    exit 1
fi

if [[ ! -f "${background_path}" ]]; then
    print -u2 "没有找到 DMG 背景图片：${background_path}"
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
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/little-watch-dmg.XXXXXX")"
writable_dmg_path="${work_dir}/LittleWatch-writable.dmg"
mount_dir=""
mounted_device=""
is_mounted=false

cleanup() {
    if [[ "${is_mounted}" == true ]]; then
        hdiutil detach "${mounted_device}" >/dev/null 2>&1 || true
    fi
    rm -rf "${work_dir}"
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

hdiutil create \
    -size 64m \
    -fs HFS+ \
    -volname "Little Watch" \
    "${writable_dmg_path}"
attach_output="$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "${writable_dmg_path}")"
mounted_device="$(print -r -- "${attach_output}" | awk '/Apple_HFS/ { print $1; exit }')"
mount_dir="$(print -r -- "${attach_output}" | awk -F '\t' '/Apple_HFS/ { print $3; exit }')"

if [[ -z "${mounted_device}" || -z "${mount_dir}" || ! -d "${mount_dir}" ]]; then
    print -u2 "无法识别 DMG 挂载位置"
    exit 1
fi
is_mounted=true

ditto "${app_path}" "${mount_dir}/LittleWatch.app"
ln -s /Applications "${mount_dir}/Applications"
mkdir -p "${mount_dir}/.background"
ditto "${background_path}" "${mount_dir}/.background/dmg-background.png"
SetFile -a V "${mount_dir}/.background"

osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Little Watch"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}

        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 14
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:dmg-background.png"

        set position of item "LittleWatch.app" to {150, 190}
        set position of item "Applications" to {450, 190}

        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "${mounted_device}" >/dev/null
is_mounted=false

rm -f "${dmg_path}" "${checksum_path}"
hdiutil convert \
    "${writable_dmg_path}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${dmg_path}"
hdiutil verify "${dmg_path}"

(
    cd "${output_dir}"
    shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256"
)

print "Release package: ${dmg_path}"
print "Checksum: ${checksum_path}"
print "Architectures: ${architectures}"
