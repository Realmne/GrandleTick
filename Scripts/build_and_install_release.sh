#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly PROJECT_ROOT="${SCRIPT_DIRECTORY:h}"
readonly PROJECT_PATH="${PROJECT_ROOT}/GrandleTick.xcodeproj"
readonly SCHEME_NAME="GrandleTick"
readonly EXPECTED_TEAM_IDENTIFIER="7PDMGBAPNH"
readonly INSTALLED_APP_PATH="/Applications/GrandleTick.app"

BUILD_DIRECTORY="$(mktemp -d /private/tmp/GrandleTickReleaseBuild.XXXXXX)"
STAGING_DIRECTORY="$(mktemp -d /private/tmp/GrandleTickReleaseInstall.XXXXXX)"
BACKUP_DIRECTORY="$(mktemp -d /private/tmp/GrandleTickReleaseBackup.XXXXXX)"
readonly BUILD_DIRECTORY
readonly STAGING_DIRECTORY
readonly BACKUP_DIRECTORY
readonly BUILT_APP_PATH="${BUILD_DIRECTORY}/Build/Products/Release/GrandleTick.app"
readonly STAGED_APP_PATH="${STAGING_DIRECTORY}/GrandleTick.app"
readonly BACKUP_APP_PATH="${BACKUP_DIRECTORY}/GrandleTick.app"

installation_started=false
installation_completed=false

cleanup() {
    local exit_status=$?

    # 安装中途失败时恢复旧应用，避免 /Applications 留下缺失或验签失败的半成品。
    if [[ "${installation_started}" == true && "${installation_completed}" == false ]]; then
        rm -rf "${INSTALLED_APP_PATH}"
        if [[ -d "${BACKUP_APP_PATH}" ]]; then
            mv "${BACKUP_APP_PATH}" "${INSTALLED_APP_PATH}"
        fi
    fi

    rm -rf "${BUILD_DIRECTORY}" "${STAGING_DIRECTORY}" "${BACKUP_DIRECTORY}"
    exit "${exit_status}"
}

trap cleanup EXIT

verify_developer_signature() {
    local app_path="$1"
    local signature_details

    # 1. 严格校验整个应用包，阻止资源被修改或只剩链接器临时签名的产物进入安装阶段。
    codesign --verify --deep --strict --verbose=2 "${app_path}"
    signature_details="$(codesign -dv --verbose=4 "${app_path}" 2>&1)"

    # 2. 个人开发证书必须保留稳定的 TeamIdentifier；ad-hoc 签名会让辅助功能权限随每次构建失效。
    if ! grep -q "TeamIdentifier=${EXPECTED_TEAM_IDENTIFIER}" <<< "${signature_details}"; then
        print -u2 "签名校验失败：${app_path} 未使用团队 ${EXPECTED_TEAM_IDENTIFIER} 的开发者证书。"
        return 1
    fi

    if grep -q "Signature=adhoc" <<< "${signature_details}"; then
        print -u2 "签名校验失败：${app_path} 使用了临时 ad-hoc 签名。"
        return 1
    fi
}

# 1. 在系统临时目录执行全新 Release 构建，避免项目所在的文件提供器目录给 .app 注入 FinderInfo。
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "${BUILD_DIRECTORY}" \
    clean build

# 2. 只有完整开发者签名通过严格校验，才准备无扩展属性的安装副本。
verify_developer_signature "${BUILT_APP_PATH}"
ditto --norsrc "${BUILT_APP_PATH}" "${STAGED_APP_PATH}"
verify_developer_signature "${STAGED_APP_PATH}"

# 3. 退出当前应用并保留可恢复备份，然后完整替换应用包，禁止只覆盖内部可执行文件。
osascript -e 'tell application id "YohanJx.GrandleTick" to quit' 2>/dev/null || true
for _ in {1..50}; do
    if ! pgrep -x "GrandleTick" >/dev/null; then
        break
    fi
    sleep 0.1
done

if pgrep -x "GrandleTick" >/dev/null; then
    print -u2 "安装已停止：GrandleTick 未能正常退出。"
    exit 1
fi

installation_started=true
if [[ -d "${INSTALLED_APP_PATH}" ]]; then
    mv "${INSTALLED_APP_PATH}" "${BACKUP_APP_PATH}"
fi

ditto --norsrc "${STAGED_APP_PATH}" "${INSTALLED_APP_PATH}"
verify_developer_signature "${INSTALLED_APP_PATH}"
installation_completed=true

# 4. 启动已经过二次验签的安装版本。
open "${INSTALLED_APP_PATH}"
print "GrandleTick 已使用稳定开发者签名构建、安装并启动。"
