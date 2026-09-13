#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="CakeBox"
RELEASE_REPO="${CAKEBOX_RELEASE_REPO:-hashultra/cakebox}"
RELEASE_TAG="${CAKEBOX_VERSION:-latest}"
RELEASE_BRANCH="${CAKEBOX_RELEASE_BRANCH:-main}"
RELEASE_PLATFORM="${CAKEBOX_RELEASE_PLATFORM:-}"
SERVICE_NAME="${CAKEBOX_SERVICE:-cakebox}"
INSTALL_DIR="${CAKEBOX_HOME:-/opt/cakebox}"
STATE_DIR="${CAKEBOX_STATE_DIR:-${INSTALL_DIR}/state}"
LOG_DIR="${CAKEBOX_LOG_DIR:-${INSTALL_DIR}/logs}"
BACKUP_DIR="${CAKEBOX_BACKUP_DIR:-${INSTALL_DIR}/backup}"
BIN_PATH="${INSTALL_DIR}/cakebox"
INSTALL_ENV="${STATE_DIR}/install.env"
NOISE_PATH="${CAKEBOX_NOISE_PATH:-${INSTALL_DIR}/cakebox-noise}"
SIDECAR_PATH="${CAKEBOX_SIDECAR_PATH:-${INSTALL_DIR}/factory-telemetry-agent}"
LISTEN_PORT="${CAKEBOX_LISTEN_PORT:-18082}"
WEB_BIND="${CAKEBOX_WEB_BIND:-}"
WEB_TOKEN="${CAKEBOX_WEB_TOKEN:-}"
MINER_LISTEN="${CAKEBOX_MINER_LISTEN:-}"
ADVERTISED_IP="${CAKEBOX_ADVERTISED_IP:-}"
URL_PREFIX="${CAKEBOX_URL_PREFIX:-}"
START_AFTER_INSTALL="${CAKEBOX_START_AFTER_INSTALL:-1}"
BUILD_FEATURES="${CAKEBOX_FEATURES:-}"
SING_BOX_VERSION="${SING_BOX_VERSION:-}"
SING_BOX_DOWNLOAD_URL="${SING_BOX_DOWNLOAD_URL:-}"
SING_BOX_ARCHIVE_SHA256="${SING_BOX_ARCHIVE_SHA256:-}"
SIDECAR_BIN_SHA256="${SIDECAR_BIN_SHA256:-}"
SIDECAR_REQUIREMENT_JSON=""
SIDECAR_PLATFORM=""
SIDECAR_ARCHIVE_NAME=""
OFFICIAL_SIDECAR_ARCHIVE_SHA256=""
OFFICIAL_SIDECAR_BIN_SHA256=""
TRUSTED_SIDECAR_SHA256=""
WEB_PORT_MIN="${CAKEBOX_WEB_PORT_MIN:-10000}"
WEB_PORT_MAX="${CAKEBOX_WEB_PORT_MAX:-60000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

red=$'\033[31m'
green=$'\033[32m'
yellow=$'\033[33m'
blue=$'\033[34m'
reset=$'\033[0m'

log() { printf '%s\n' "${blue}==>${reset} $*"; }
ok() { printf '%s\n' "${green}完成:${reset} $*"; }
warn() { printf '%s\n' "${yellow}注意:${reset} $*"; }
die() { printf '%s\n' "${red}错误:${reset} $*" >&2; exit 1; }

detect_release_platform() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64|Linux:amd64) printf 'linux-amd64' ;;
    Linux:aarch64|Linux:arm64) printf 'linux-arm64' ;;
    Linux:armv7l|Linux:armv7) printf 'linux-armv7' ;;
    *) return 1 ;;
  esac
}

init_release_platform() {
  if [ -n "${RELEASE_PLATFORM}" ]; then
    return
  fi
  local detected
  detected="$(detect_release_platform)" || die "暂不支持的发布平台：$(uname -s)/$(uname -m)；请设置 CAKEBOX_RELEASE_PLATFORM 或 CAKEBOX_BIN_SOURCE"
  RELEASE_PLATFORM="${detected}"
  log "自动识别发布平台：${RELEASE_PLATFORM}"
}

can_download_release() {
  [ "$(uname -s)" = "Linux" ]
}

need_root() {
  [ "$(id -u)" = "0" ] || die "请使用 root 运行：sudo bash $0"
}

reject_space_path() {
  case "${INSTALL_DIR}${STATE_DIR}${LOG_DIR}${BIN_PATH}${NOISE_PATH}${SIDECAR_PATH}" in
    *[[:space:]]*) die "安装路径不能包含空格：${INSTALL_DIR}" ;;
  esac
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

random_segment() {
  local prefix="$1"
  local body
  if command -v openssl >/dev/null 2>&1; then
    body="$(openssl rand -hex 4)"
  else
    body="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  printf '%s-%s' "${prefix}" "${body}"
}

normalize_url_prefix() {
  local raw="$1"
  raw="${raw#/}"
  raw="${raw%/}"
  [ -n "${raw}" ] || die "安全访问路径不能为空"
  case "${raw}" in
    *[!a-z0-9-]*|*/*|*.*|*_*) die "安全访问路径只能包含小写字母、数字和连字符：${raw}" ;;
    -*|*-) die "安全访问路径不能以连字符开头或结尾：${raw}" ;;
  esac
  [ "${#raw}" -ge 2 ] && [ "${#raw}" -le 32 ] || die "安全访问路径长度必须是 2-32 位：${raw}"
  case "${raw}" in
    api|assets|admin|static|openapi.json|favicon.svg|index.html) die "安全访问路径不能使用保留名称：${raw}" ;;
  esac
  printf '%s' "${raw}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

port_in_use() {
  local port="$1"
  if command_exists ss; then
    ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q . && return 0
  elif command_exists lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  elif command_exists netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$" && return 0
  fi
  return 1
}

random_port() {
  local min="${WEB_PORT_MIN}" max="${WEB_PORT_MAX}" span port i rand
  [ "${min}" -ge 1 ] && [ "${max}" -le 65535 ] && [ "${min}" -le "${max}" ] || die "端口范围无效：${min}-${max}"
  span=$((max - min + 1))
  for i in $(seq 1 200); do
    if command_exists od; then
      rand="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    else
      rand="${RANDOM}${RANDOM}"
    fi
    port=$((min + rand % span))
    if ! port_in_use "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
  done
  die "无法在 ${min}-${max} 范围内找到空闲端口"
}

validate_port_value() {
  local port="$1"
  case "${port}" in
    ''|*[!0-9]*) die "端口必须是数字：${port}" ;;
  esac
  [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ] || die "端口必须在 1-65535 范围内：${port}"
}

validate_web_bind_for_install() {
  local port
  port="$(bind_port "${WEB_BIND}")"
  validate_port_value "${port}"
  if port_in_use "${port}"; then
    die "CakeBox Web 端口 ${port} 已被占用，请更换端口后再安装"
  fi
}

bind_port() {
  local bind="$1"
  printf '%s' "${bind##*:}"
}

host_from_bind() {
  local bind="$1"
  printf '%s' "${bind%:*}"
}

load_install_env() {
  if [ -f "${INSTALL_ENV}" ]; then
    # shellcheck disable=SC1090
    . "${INSTALL_ENV}"
  fi
  WEB_BIND="${CAKEBOX_WEB_BIND:-${WEB_BIND:-${SAVED_WEB_BIND:-}}}"
  URL_PREFIX="${CAKEBOX_URL_PREFIX:-${URL_PREFIX:-${SAVED_URL_PREFIX:-}}}"
  if [ -z "${TRUSTED_SIDECAR_SHA256}" ] && [ -n "${SAVED_SIDECAR_SHA256:-}" ]; then
    TRUSTED_SIDECAR_SHA256="${SAVED_SIDECAR_SHA256}"
  fi
  if [ -f "${SERVICE_FILE}" ]; then
    local exec_line
    exec_line="$(sed -n 's/^ExecStart=//p' "${SERVICE_FILE}" | tail -n 1)"
    if [ -z "${WEB_BIND}" ]; then
      WEB_BIND="$(printf '%s\n' "${exec_line}" | sed -n 's/.*--web-bind \([^ ]*\).*/\1/p')"
    fi
    if [ -z "${URL_PREFIX}" ]; then
      URL_PREFIX="$(printf '%s\n' "${exec_line}" | sed -n 's/.*--url-prefix \([^ ]*\).*/\1/p')"
    fi
    if [ -z "${TRUSTED_SIDECAR_SHA256}" ]; then
      TRUSTED_SIDECAR_SHA256="$(printf '%s\n' "${exec_line}" | sed -n 's/.*--sidecar-sha256 \([^ ]*\).*/\1/p')"
    fi
  fi
}

save_install_env() {
  validate_sha256_value "${TRUSTED_SIDECAR_SHA256}" "可信 sidecar"
  umask 077
  cat > "${INSTALL_ENV}" <<EOF
SAVED_WEB_BIND='${WEB_BIND}'
SAVED_URL_PREFIX='${URL_PREFIX}'
SAVED_SIDECAR_SHA256='${TRUSTED_SIDECAR_SHA256}'
EOF
}

configure_web_defaults_for_install() {
  [ -n "${WEB_BIND}" ] || WEB_BIND="0.0.0.0:$(random_port)"
  if [ -z "${URL_PREFIX}" ]; then
    URL_PREFIX="$(random_segment cb)"
  else
    URL_PREFIX="$(normalize_url_prefix "${URL_PREFIX}")"
  fi
}

configure_web_defaults_for_update() {
  load_install_env
  [ -n "${WEB_BIND}" ] || WEB_BIND="0.0.0.0:$(random_port)"
  [ -n "${URL_PREFIX}" ] || URL_PREFIX="$(random_segment cb)"
  URL_PREFIX="$(normalize_url_prefix "${URL_PREFIX}")"
}

is_installed() {
  [ -x "${BIN_PATH}" ] || [ -f "${SERVICE_FILE}" ] || [ -f "${INSTALL_ENV}" ]
}

running_processes() {
  pgrep -af "${BIN_PATH}|(^|/)cakebox( |$)" 2>/dev/null || true
}

check_no_running_conflict() {
  if has_systemd && systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    die "检测到 ${SERVICE_NAME}.service 正在运行；首次安装前请先停止，已安装请使用 update"
  fi
  local running
  running="$(running_processes | grep -v "pgrep -af" || true)"
  [ -z "${running}" ] || die "检测到正在运行的 CakeBox 进程，首次安装已停止：
${running}"
}

disable_firewall() {
  need_root
  if command_exists ufw; then
    ufw disable || true
    ok "已尝试关闭 ufw 防火墙"
  elif command_exists firewall-cmd || systemctl list-unit-files 2>/dev/null | grep -q '^firewalld\.service'; then
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    ok "已尝试关闭 firewalld 防火墙"
  else
    warn "未识别到 ufw/firewalld，已跳过系统防火墙关闭"
  fi
}

local_ip() {
  local ip=""
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "${ip:-服务器IP}"
}

web_url() {
  local host port
  host="$(host_from_bind "${WEB_BIND}")"
  port="$(bind_port "${WEB_BIND}")"
  case "${host}" in 0.0.0.0|::|\[::\]|"") host="$(local_ip)" ;; esac
  printf 'http://%s:%s/%s/' "${host}" "${port}" "${URL_PREFIX}"
}

github_api_get() {
  local url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "${url}"
  elif [ -n "${GH_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GH_TOKEN}" "${url}"
  else
    curl -fsSL "${url}"
  fi
}

download_repo_file() {
  local path="$1"
  local dst="$2"
  local url="https://api.github.com/repos/${RELEASE_REPO}/contents/${path}?ref=${RELEASE_BRANCH}"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.raw" "${url}" -o "${dst}"
  elif [ -n "${GH_TOKEN:-}" ]; then
    curl -fL -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github.raw" "${url}" -o "${dst}"
  else
    curl -fL -H "Accept: application/vnd.github.raw" "${url}" -o "${dst}"
  fi
}

asset_name_for_version() {
  local prefix="$1"
  if [ "${RELEASE_TAG}" != "latest" ]; then
    printf '%s-%s-%s' "${prefix}" "${RELEASE_TAG#v}" "${RELEASE_PLATFORM}"
    return
  fi
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法查询 latest Release"
  local name
  name="$(github_api_get "https://api.github.com/repos/${RELEASE_REPO}/contents/${RELEASE_PLATFORM}?ref=${RELEASE_BRANCH}" \
    | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -E "^${prefix}-[0-9][0-9A-Za-z._-]*-${RELEASE_PLATFORM}$" \
    | sort -V \
    | tail -n 1)"
  [ -n "${name}" ] || die "无法在 ${RELEASE_REPO}/${RELEASE_PLATFORM} 找到 ${prefix} 的发布文件；可改用 CAKEBOX_DOWNLOAD_URL"
  printf '%s' "${name}"
}

ensure_dirs() {
  need_root
  reject_space_path
  mkdir -p "${INSTALL_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${BACKUP_DIR}"
  chmod 700 "${INSTALL_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${BACKUP_DIR}"
}

migrate_legacy_account() {
  local account_file="${STATE_DIR}/account.json"
  local legacy_dir legacy_account
  if [ -s "${account_file}" ]; then
    return 0
  fi
  for legacy_dir in "/root/.cakebox" "${HOME}/.cakebox"; do
    legacy_account="${legacy_dir}/account.json"
    if [ -s "${legacy_account}" ]; then
      cp -a "${legacy_account}" "${account_file}"
      chmod 600 "${account_file}"
      ok "已从 ${legacy_account} 迁移管理员账户到 ${account_file}"
      return 0
    fi
  done
}

ensure_web_token() {
  local token_file="${STATE_DIR}/web-token"
  if [ -n "${WEB_TOKEN}" ]; then
    printf '%s\n' "${WEB_TOKEN}" > "${token_file}"
    chmod 600 "${token_file}"
    return
  fi
  if [ ! -s "${token_file}" ]; then
    random_secret > "${token_file}"
    chmod 600 "${token_file}"
  fi
}

build_cakebox_binary() {
  [ -f "${SOURCE_ROOT}/Cargo.toml" ] || die "当前脚本不在源码仓库内；请设置 CAKEBOX_BIN_SOURCE 或 CAKEBOX_DOWNLOAD_URL"
  command -v cargo >/dev/null 2>&1 || die "缺少 cargo，无法从源码构建"
  log "构建 cakebox release 二进制"
  if [ -n "${BUILD_FEATURES}" ]; then
    cargo build --release -p cakebox --features "${BUILD_FEATURES}"
  else
    cargo build --release -p cakebox
  fi
}

build_noise_binary() {
  [ -f "${SOURCE_ROOT}/Cargo.toml" ] || return 1
  command -v cargo >/dev/null 2>&1 || return 1
  log "构建 cakebox-noise release 二进制"
  cargo build --release -p cakebox-noise
}

build_binaries() {
  build_cakebox_binary
  build_noise_binary || die "缺少 cargo 或源码，无法构建 cakebox-noise"
}

# 注意：本函数被 `if download_cakebox; then` 调用，而 bash 规定「函数在 -e 被忽略
# 的上下文中执行时，其内部所有命令均不受 -e 影响」。因此这里**不能**依赖
# `set -Eeuo pipefail` 兜底，每一步都必须显式判错——此前正是因为漏了这一点，
# curl 失败、asset 解析失败、install 失败全部被吞掉后仍走到 `return 0`，
# 调用方照常打印「已安装下载的二进制」。
#
# `return 1` 的语义被保留为「本平台没有可下载的 release，请回退源码构建」；
# 真正的失败一律 `die`，绝不静默降级到旧二进制（CakeBox 与 HashCake 必须同批
# 部署，静默留用旧版会造成协议不兼容）。
download_cakebox() {
  local url="${CAKEBOX_DOWNLOAD_URL:-}"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 CAKEBOX_DOWNLOAD_URL"
  local candidate="${BIN_PATH}.download"
  rm -f -- "${candidate}"
  if [ -z "${url}" ]; then
    can_download_release || return 1
    local asset expected
    asset="$(asset_name_for_version cakebox)" \
      || die "无法解析 cakebox 发布资产名（GitHub API 不可达或已限流），请稍后重试或指定 CAKEBOX_VERSION"
    log "下载 cakebox 二进制：github.com/${RELEASE_REPO}/${RELEASE_PLATFORM}/${asset}"
    # `$( )` 是子 shell，被调函数里的 `die` 只结束子 shell、结束不了安装器，
    # 所以这里必须显式接住退出码。具体原因（SHA256SUMS 取不到 / 无该条目）
    # 已由子 shell 打到 stderr。先取摘要再下载：期望值都拿不到就不必浪费带宽。
    expected="$(repo_asset_sha256 "${RELEASE_PLATFORM}/${asset}")" \
      || die "无法取得 cakebox 二进制的官方 SHA-256，已拒绝安装未经校验的二进制"
    if ! download_repo_file "${RELEASE_PLATFORM}/${asset}" "${candidate}"; then
      rm -f -- "${candidate}"
      die "下载 cakebox 二进制失败：${RELEASE_PLATFORM}/${asset}"
    fi
    require_file_sha256 "${candidate}" "${expected}" "cakebox 二进制" >/dev/null
  else
    log "下载 cakebox 二进制：${url}"
    if ! curl -fL "${url}" -o "${candidate}"; then
      rm -f -- "${candidate}"
      die "下载 cakebox 二进制失败：${url}"
    fi
    if [ -n "${CAKEBOX_DOWNLOAD_SHA256:-}" ]; then
      require_file_sha256 "${candidate}" "${CAKEBOX_DOWNLOAD_SHA256}" "cakebox 二进制" >/dev/null
    else
      log "警告：CAKEBOX_DOWNLOAD_URL 指向自定义来源且未提供 CAKEBOX_DOWNLOAD_SHA256，跳过完整性校验"
    fi
  fi
  if ! install -m 0755 "${candidate}" "${BIN_PATH}"; then
    rm -f -- "${candidate}"
    die "安装 cakebox 二进制到 ${BIN_PATH} 失败"
  fi
  rm -f -- "${candidate}"
  return 0
}

# 与 download_cakebox 同构：被 `if download_noise; then` 调用，函数体内 -e 失效，
# 必须逐步显式判错；官方来源强制 SHA-256 校验且 fail-closed。
download_noise() {
  local url="${CAKEBOX_NOISE_DOWNLOAD_URL:-}"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 CAKEBOX_NOISE_DOWNLOAD_URL"
  local candidate="${NOISE_PATH}.download"
  rm -f -- "${candidate}"
  if [ -z "${url}" ]; then
    can_download_release || return 1
    local asset expected
    asset="$(asset_name_for_version cakebox-noise)" \
      || die "无法解析 cakebox-noise 发布资产名（GitHub API 不可达或已限流），请稍后重试或指定 CAKEBOX_VERSION"
    log "下载 cakebox-noise 二进制：github.com/${RELEASE_REPO}/${RELEASE_PLATFORM}/${asset}"
    # 同上：命令替换是子 shell，`die` 传不出来，必须显式接住退出码。
    expected="$(repo_asset_sha256 "${RELEASE_PLATFORM}/${asset}")" \
      || die "无法取得 cakebox-noise 二进制的官方 SHA-256，已拒绝安装未经校验的二进制"
    if ! download_repo_file "${RELEASE_PLATFORM}/${asset}" "${candidate}"; then
      rm -f -- "${candidate}"
      die "下载 cakebox-noise 二进制失败：${RELEASE_PLATFORM}/${asset}"
    fi
    require_file_sha256 "${candidate}" "${expected}" "cakebox-noise 二进制" >/dev/null
  else
    log "下载 cakebox-noise 二进制：${url}"
    if ! curl -fL "${url}" -o "${candidate}"; then
      rm -f -- "${candidate}"
      die "下载 cakebox-noise 二进制失败：${url}"
    fi
    if [ -n "${CAKEBOX_NOISE_DOWNLOAD_SHA256:-}" ]; then
      require_file_sha256 "${candidate}" "${CAKEBOX_NOISE_DOWNLOAD_SHA256}" "cakebox-noise 二进制" >/dev/null
    else
      log "警告：CAKEBOX_NOISE_DOWNLOAD_URL 指向自定义来源且未提供 CAKEBOX_NOISE_DOWNLOAD_SHA256，跳过完整性校验"
    fi
  fi
  if ! install -m 0755 "${candidate}" "${NOISE_PATH}"; then
    rm -f -- "${candidate}"
    die "安装 cakebox-noise 二进制到 ${NOISE_PATH} 失败"
  fi
  rm -f -- "${candidate}"
  return 0
}

install_noise_binary() {
  local noise_src="${CAKEBOX_NOISE_BIN_SOURCE:-}"
  if [ -n "${noise_src}" ]; then
    [ -x "${noise_src}" ] || die "CAKEBOX_NOISE_BIN_SOURCE 不存在或不可执行：${noise_src}"
    install -m 0755 "${noise_src}" "${NOISE_PATH}"
    ok "已安装混淆组件 ${NOISE_PATH}"
    return
  fi
  if [ -x "${SOURCE_ROOT}/target/release/cakebox-noise" ]; then
    install -m 0755 "${SOURCE_ROOT}/target/release/cakebox-noise" "${NOISE_PATH}"
    ok "已安装混淆组件 ${NOISE_PATH}"
    return
  fi
  if download_noise; then
    ok "已安装混淆组件 ${NOISE_PATH}"
    return
  fi
  if build_noise_binary; then
    install -m 0755 "${SOURCE_ROOT}/target/release/cakebox-noise" "${NOISE_PATH}"
    ok "已安装混淆组件 ${NOISE_PATH}"
    return
  fi
  die "无法安装 cakebox-noise；请设置 CAKEBOX_NOISE_BIN_SOURCE、CAKEBOX_NOISE_DOWNLOAD_URL，或提供源码与 cargo 环境"
}

install_binary() {
  init_release_platform
  local src="${CAKEBOX_BIN_SOURCE:-}"
  if [ -n "${src}" ]; then
    [ -x "${src}" ] || die "CAKEBOX_BIN_SOURCE 不存在或不可执行：${src}"
    install -m 0755 "${src}" "${BIN_PATH}"
    ok "已安装二进制 ${BIN_PATH}"
    install_noise_binary
    return
  fi

  if download_cakebox; then
    ok "已安装下载的二进制 ${BIN_PATH}"
    install_noise_binary
    return
  fi

  build_binaries
  install -m 0755 "${SOURCE_ROOT}/target/release/cakebox" "${BIN_PATH}"
  install -m 0755 "${SOURCE_ROOT}/target/release/cakebox-noise" "${NOISE_PATH}"
  ok "已安装二进制 ${BIN_PATH}"
  ok "已安装混淆组件 ${NOISE_PATH}"
}

singbox_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7) printf 'armv7' ;;
    *) die "暂不支持的 CPU 架构：$(uname -m)" ;;
  esac
}

validate_sidecar_version_value() {
  local version="$1"
  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
    die "SING_BOX_VERSION 格式无效：${version}"
  fi
}

validate_sha256_value() {
  local digest="$1" label="${2:-SHA-256}"
  [[ "${digest}" =~ ^[0-9A-Fa-f]{64}$ ]] \
    || die "${label} SHA-256 格式无效：${digest:-<空>}"
}

normalize_sha256_value() {
  local digest="$1" label="${2:-SHA-256}"
  validate_sha256_value "${digest}" "${label}"
  printf '%s' "${digest}" | tr 'A-F' 'a-f'
}

json_string_field() {
  local json="$1" key="$2" value
  value="$(printf '%s\n' "${json}" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")"
  [ -n "${value}" ] || die "sidecar requirement JSON 缺少字符串字段：${key}"
  printf '%s' "${value}"
}

json_u32_field() {
  local json="$1" key="$2" value
  value="$(printf '%s\n' "${json}" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p")"
  [ -n "${value}" ] || die "sidecar requirement JSON 缺少整数字段：${key}"
  printf '%s' "${value}"
}

resolve_sidecar_requirement() {
  local schema detected_platform
  [ -x "${BIN_PATH}" ] \
    || die "CakeBox 二进制尚未安装，无法确定 sidecar 完整性要求：${BIN_PATH}"
  SIDECAR_REQUIREMENT_JSON="$("${BIN_PATH}" sidecar-requirement 2>/dev/null)" \
    || die "无法从已安装的 CakeBox 读取 sidecar requirement：${BIN_PATH}"
  schema="$(json_u32_field "${SIDECAR_REQUIREMENT_JSON}" schema_version)"
  [ "${schema}" = "1" ] || die "不支持的 sidecar requirement schema：${schema}"

  local required
  required="$(json_string_field "${SIDECAR_REQUIREMENT_JSON}" version)"
  SIDECAR_PLATFORM="$(json_string_field "${SIDECAR_REQUIREMENT_JSON}" platform)"
  SIDECAR_ARCHIVE_NAME="$(json_string_field "${SIDECAR_REQUIREMENT_JSON}" archive_name)"
  OFFICIAL_SIDECAR_ARCHIVE_SHA256="$(normalize_sha256_value \
    "$(json_string_field "${SIDECAR_REQUIREMENT_JSON}" archive_sha256)" "官方 archive")"
  OFFICIAL_SIDECAR_BIN_SHA256="$(normalize_sha256_value \
    "$(json_string_field "${SIDECAR_REQUIREMENT_JSON}" binary_sha256)" "官方 binary")"

  validate_sidecar_version_value "${required}"
  case "${SIDECAR_PLATFORM}" in
    linux-amd64|linux-arm64|linux-armv7) ;;
    *) die "CakeBox requirement 平台不适用于 Linux 安装器：${SIDECAR_PLATFORM}" ;;
  esac
  case "${SIDECAR_ARCHIVE_NAME}" in
    ""|*/*|*..*) die "sidecar archive_name 不安全：${SIDECAR_ARCHIVE_NAME}" ;;
  esac
  [ "${SIDECAR_ARCHIVE_NAME}" = "sing-box-${required}-${SIDECAR_PLATFORM}.tar.gz" ] \
    || die "sidecar archive_name 与版本/平台不一致：${SIDECAR_ARCHIVE_NAME}"
  if detected_platform="$(detect_release_platform 2>/dev/null)"; then
    [ "${SIDECAR_PLATFORM}" = "${detected_platform}" ] \
      || die "CakeBox requirement 平台 ${SIDECAR_PLATFORM} 与当前主机 ${detected_platform} 不一致"
  elif [ "$(uname -s)" = "Linux" ]; then
    die "暂不支持的 sidecar 安装平台：$(uname -s)/$(uname -m)"
  fi
  if [ -n "${SING_BOX_VERSION}" ] && [ "${SING_BOX_VERSION}" != "${required}" ]; then
    die "SING_BOX_VERSION=${SING_BOX_VERSION} 与当前 CakeBox 要求 ${required} 不一致；请使用匹配的同批发布"
  fi
  SING_BOX_VERSION="${required}"
}

resolve_sidecar_version_requirement() {
  resolve_sidecar_requirement
}

sha256_file() {
  local path="$1" digest
  [ -f "${path}" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "${path}" | awk '{print $1}')" || return 1
  elif command -v shasum >/dev/null 2>&1; then
    digest="$(shasum -a 256 "${path}" | awk '{print $1}')" || return 1
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(openssl dgst -sha256 "${path}" | awk '{print $NF}')" || return 1
  else
    die "缺少 sha256sum、shasum 或 openssl，无法校验 sidecar 完整性"
  fi
  normalize_sha256_value "${digest}" "文件"
}

sidecar_version() {
  local binary="$1" output version
  [ -x "${binary}" ] || return 1
  output="$("${binary}" version 2>&1)" || return 1
  version="$(printf '%s\n' "${output}" | awk '$1 == "sing-box" && $2 == "version" && NF == 3 { print $3; exit }')"
  [ -n "${version}" ] || return 1
  printf '%s' "${version}"
}

require_sidecar_version() {
  local binary="$1" label="$2" actual
  validate_sidecar_version_value "${SING_BOX_VERSION}"
  actual="$(sidecar_version "${binary}")" \
    || die "无法识别 ${label} 的 sing-box 版本：${binary}"
  [ "${actual}" = "${SING_BOX_VERSION}" ] \
    || die "${label} 的 sing-box 版本不符合要求：检测到 ${actual}，要求精确为 ${SING_BOX_VERSION}"
}

require_file_sha256() {
  local path="$1" expected="$2" label="$3" actual
  expected="$(normalize_sha256_value "${expected}" "${label}")"
  actual="$(sha256_file "${path}")" || die "无法计算 ${label} 的 SHA-256：${path}"
  [ "${actual}" = "${expected}" ] \
    || die "${label} 的 SHA-256 不受信任：检测到 ${actual}，要求 ${expected}"
  printf '%s' "${actual}"
}

# 从发布仓库根目录的 SHA256SUMS 取出指定资产的期望摘要。
#
# 发布流水线一直在产出这份文件（scripts/prepare-releases.sh 的 write_sha256 生成、
# scripts/publish-releases.sh 提交到仓库根），但 CakeBox 与 CakeHub 的安装器此前
# 从不读取它——第三方 sing-box 被逐字节钉死，自己的二进制反而零校验落地成 root
# 可执行文件。这里补上，并且 **fail-closed**：拿不到 SHA256SUMS 或找不到条目一律
# 中止，绝不「取不到校验值就放行」，否则等于没有校验。
#
# 条目格式由 write_sha256 的 `sed 's#  \./#  #'` 决定，第二列正是
# "<platform>/<asset>"，与这里传入的 asset_path 一致。
repo_asset_sha256() {
  local asset_path="$1" sums_file expected
  sums_file="$(mktemp "${TMPDIR:-/tmp}/cakebox-SHA256SUMS.XXXXXX")" \
    || die "无法创建临时文件以下载 SHA256SUMS"
  if ! download_repo_file "SHA256SUMS" "${sums_file}"; then
    rm -f -- "${sums_file}"
    die "发布仓库 ${RELEASE_REPO} 缺少可下载的 SHA256SUMS，已拒绝安装未经校验的官方二进制"
  fi
  expected="$(awk -v wanted="${asset_path}" '$2 == wanted { print $1; exit }' "${sums_file}")"
  rm -f -- "${sums_file}"
  if [ "${#expected}" -ne 64 ] || [[ "${expected}" == *[!0-9A-Fa-f]* ]]; then
    die "SHA256SUMS 中缺少 ${asset_path} 的有效校验值，已拒绝安装"
  fi
  printf '%s' "${expected}"
}

validate_sidecar_archive_members() {
  local archive="$1" members member unsafe_type
  members="$(tar -tzf "${archive}")" || die "无法读取 sing-box 压缩包目录：${archive}"
  [ -n "${members}" ] || die "sing-box 压缩包为空：${archive}"
  while IFS= read -r member; do
    case "${member}" in
      ""|/*|..|../*|*/../*|*/..) die "sing-box 压缩包含不安全路径：${member:-<空>}" ;;
    esac
  done <<< "${members}"
  unsafe_type="$(tar -tvzf "${archive}" | awk 'substr($1,1,1) != "-" && substr($1,1,1) != "d" { print substr($1,1,1); exit }')" \
    || die "无法检查 sing-box 压缩包成员类型：${archive}"
  [ -z "${unsafe_type}" ] \
    || die "sing-box 压缩包含 symlink/hardlink 或其它不受支持的成员类型：${unsafe_type}"
}

require_sidecar_binary() {
  local binary="$1" label="$2" expected_sha256="$3"
  # Hash first: never execute an untrusted candidate merely to ask its version.
  require_file_sha256 "${binary}" "${expected_sha256}" "${label}" >/dev/null
  require_sidecar_version "${binary}" "${label}"
}

activate_sidecar_binary() {
  local src="$1" label="$2" expected_sha256="$3" stage
  expected_sha256="$(normalize_sha256_value "${expected_sha256}" "${label}")"
  require_sidecar_binary "${src}" "${label}" "${expected_sha256}" >/dev/null
  mkdir -p "$(dirname "${SIDECAR_PATH}")"

  if [ -e "${SIDECAR_PATH}" ] && [ ! -L "${SIDECAR_PATH}" ] \
    && [ "${src}" -ef "${SIDECAR_PATH}" ]; then
    chmod 0755 "${SIDECAR_PATH}"
    require_sidecar_binary "${SIDECAR_PATH}" "已安装 sidecar" "${expected_sha256}" >/dev/null
    TRUSTED_SIDECAR_SHA256="${expected_sha256}"
    ok "已确认 sidecar ${SIDECAR_PATH}（sing-box ${SING_BOX_VERSION}，SHA-256 ${expected_sha256:0:12}…）"
    return
  fi

  stage="$(mktemp "${SIDECAR_PATH}.new.XXXXXX")" \
    || die "无法为 sidecar 创建同目录暂存文件：${SIDECAR_PATH}"
  if ! install -m 0755 "${src}" "${stage}"; then
    rm -f -- "${stage}"
    die "无法暂存 sidecar：${src}"
  fi
  if ! require_sidecar_binary "${stage}" "sidecar 暂存文件" "${expected_sha256}" >/dev/null 2>&1; then
    rm -f -- "${stage}"
    die "sidecar 暂存后完整性或版本校验失败"
  fi
  if ! mv -f -- "${stage}" "${SIDECAR_PATH}"; then
    rm -f -- "${stage}"
    die "无法原子替换 sidecar：${SIDECAR_PATH}"
  fi
  [ ! -L "${SIDECAR_PATH}" ] || die "最终 sidecar 不能是 symlink：${SIDECAR_PATH}"
  require_sidecar_binary "${SIDECAR_PATH}" "最终 sidecar" "${expected_sha256}" >/dev/null
  TRUSTED_SIDECAR_SHA256="${expected_sha256}"
  ok "已安装 sidecar ${SIDECAR_PATH}（sing-box ${SING_BOX_VERSION}，SHA-256 ${expected_sha256:0:12}…）"
}

try_sidecar_candidate() {
  local src="$1" label="$2" expected_sha256="$3" actual_sha256 actual_version
  [ -x "${src}" ] || return 1
  actual_sha256="$(sha256_file "${src}")" || {
    warn "已忽略无法计算 SHA-256 的 ${label}：${src}"
    return 1
  }
  expected_sha256="$(normalize_sha256_value "${expected_sha256}" "${label}")"
  if [ "${actual_sha256}" != "${expected_sha256}" ]; then
    warn "已忽略 SHA-256 不受信任的 ${label}：${src}（检测到 ${actual_sha256}，要求 ${expected_sha256}）"
    return 1
  fi
  actual_version="$(sidecar_version "${src}")" || {
    warn "已忽略无法识别版本的 ${label}：${src}"
    return 1
  }
  if [ "${actual_version}" != "${SING_BOX_VERSION}" ]; then
    warn "已忽略版本不匹配的 ${label}：${src}（检测到 ${actual_version}，要求 ${SING_BOX_VERSION}）"
    return 1
  fi
  activate_sidecar_binary "${src}" "${label}" "${expected_sha256}"
}

download_sidecar() {
  resolve_sidecar_requirement
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 sing-box"
  command -v tar >/dev/null 2>&1 || die "缺少 tar，无法解压 sing-box"
  local url tmp archive found expected_archive_sha256 expected_binary_sha256
  if [ -n "${SING_BOX_DOWNLOAD_URL}" ]; then
    [ -n "${SING_BOX_ARCHIVE_SHA256}" ] \
      || die "自定义 SING_BOX_DOWNLOAD_URL 必须同时提供 SING_BOX_ARCHIVE_SHA256"
    url="${SING_BOX_DOWNLOAD_URL}"
    expected_archive_sha256="$(normalize_sha256_value "${SING_BOX_ARCHIVE_SHA256}" "自定义 archive")"
    if [ -n "${SIDECAR_BIN_SHA256}" ]; then
      expected_binary_sha256="$(normalize_sha256_value "${SIDECAR_BIN_SHA256}" "自定义 sidecar")"
    else
      expected_binary_sha256="${OFFICIAL_SIDECAR_BIN_SHA256}"
    fi
  else
    url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${SIDECAR_ARCHIVE_NAME}"
    expected_archive_sha256="${OFFICIAL_SIDECAR_ARCHIVE_SHA256}"
    expected_binary_sha256="${OFFICIAL_SIDECAR_BIN_SHA256}"
    if [ -n "${SING_BOX_ARCHIVE_SHA256}" ]; then
      [ "$(normalize_sha256_value "${SING_BOX_ARCHIVE_SHA256}" "archive")" = "${expected_archive_sha256}" ] \
        || die "官方下载地址的 SING_BOX_ARCHIVE_SHA256 与 CakeBox 内置 requirement 不一致"
    fi
    if [ -n "${SIDECAR_BIN_SHA256}" ]; then
      [ "$(normalize_sha256_value "${SIDECAR_BIN_SHA256}" "sidecar")" = "${expected_binary_sha256}" ] \
        || die "官方下载地址的 SIDECAR_BIN_SHA256 与 CakeBox 内置 requirement 不一致"
    fi
  fi
  tmp="$(mktemp -d)"
  archive="${tmp}/${SIDECAR_ARCHIVE_NAME}"
  log "下载 sing-box sidecar：${url}"
  curl -fL "${url}" -o "${archive}"
  require_file_sha256 "${archive}" "${expected_archive_sha256}" "sing-box 下载压缩包" >/dev/null
  validate_sidecar_archive_members "${archive}"
  tar -xzf "${archive}" -C "${tmp}"
  found="$(find "${tmp}" -type f -name 'sing-box' -print)"
  [ -n "${found}" ] || die "压缩包中没有找到 sing-box"
  case "${found}" in
    *$'\n'*) die "压缩包中发现多个 sing-box，拒绝选择不明确的候选" ;;
  esac
  chmod 0755 "${found}"
  activate_sidecar_binary "${found}" "下载的 sing-box 压缩包" "${expected_binary_sha256}"
  rm -rf "${tmp}"
}

install_sidecar() {
  local src="${SIDECAR_BIN_SOURCE:-}" existing_expected_sha256
  resolve_sidecar_requirement
  if [ -n "${src}" ]; then
    [ -x "${src}" ] || die "SIDECAR_BIN_SOURCE 不存在或不可执行：${src}"
    [ -n "${SIDECAR_BIN_SHA256}" ] \
      || die "显式 SIDECAR_BIN_SOURCE 必须同时提供 SIDECAR_BIN_SHA256"
    local explicit_sha256
    explicit_sha256="$(normalize_sha256_value "${SIDECAR_BIN_SHA256}" "SIDECAR_BIN_SOURCE")"
    # Explicit operator input is authoritative: reject it on mismatch instead
    # of silently falling back to another local binary or a download.
    activate_sidecar_binary "${src}" "SIDECAR_BIN_SOURCE" "${explicit_sha256}"
    return
  fi
  if [ -n "${SING_BOX_DOWNLOAD_URL}" ]; then
    # Explicit download input is authoritative just like SIDECAR_BIN_SOURCE;
    # do not silently keep an already-installed same-version binary.
    download_sidecar
    return
  fi
  existing_expected_sha256="${TRUSTED_SIDECAR_SHA256}"
  if [ -n "${SIDECAR_BIN_SHA256}" ]; then
    existing_expected_sha256="$(normalize_sha256_value "${SIDECAR_BIN_SHA256}" "sidecar")"
    [ "${existing_expected_sha256}" = "${OFFICIAL_SIDECAR_BIN_SHA256}" ] \
      || die "没有 SIDECAR_BIN_SOURCE 或 SING_BOX_DOWNLOAD_URL 时，SIDECAR_BIN_SHA256 只能用于断言官方摘要"
  fi
  if [ -x "${SIDECAR_PATH}" ] && [ -n "${existing_expected_sha256}" ] \
    && try_sidecar_candidate "${SIDECAR_PATH}" "已安装 sidecar" "${existing_expected_sha256}"; then
    return
  fi
  if try_sidecar_candidate "${SOURCE_ROOT}/factory-telemetry-agent" "仓库 sidecar" "${OFFICIAL_SIDECAR_BIN_SHA256}"; then
    return
  fi
  if try_sidecar_candidate "/usr/local/bin/factory-telemetry-agent" "系统 factory-telemetry-agent" "${OFFICIAL_SIDECAR_BIN_SHA256}"; then
    return
  fi
  if try_sidecar_candidate "/usr/local/bin/sing-box" "系统 sing-box" "${OFFICIAL_SIDECAR_BIN_SHA256}"; then
    return
  fi
  download_sidecar
}

ensure_trusted_sidecar_digest() {
  resolve_sidecar_requirement
  local expected="${TRUSTED_SIDECAR_SHA256:-${SIDECAR_BIN_SHA256:-${SAVED_SIDECAR_SHA256:-${OFFICIAL_SIDECAR_BIN_SHA256}}}}"
  expected="$(normalize_sha256_value "${expected}" "运行时 sidecar")"
  require_sidecar_binary "${SIDECAR_PATH}" "最终 sidecar" "${expected}" >/dev/null
  TRUSTED_SIDECAR_SHA256="${expected}"
}

token_args_from_input() {
  local raw="${CAKEBOX_TOKEN:-}"
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi
  if [ -n "${raw}" ]; then
    printf '%s\n' "${raw}" | tr ', ' '\n' | sed '/^[[:space:]]*$/d'
    return
  fi
  if [ -t 0 ]; then
    read -r -p "请输入隧道加密令牌；多个令牌用逗号分隔，留空跳过: " raw
    [ -n "${raw}" ] && printf '%s\n' "${raw}" | tr ', ' '\n' | sed '/^[[:space:]]*$/d'
  fi
}

install_token() {
  [ -x "${BIN_PATH}" ] || die "请先安装 cakebox 二进制"
  [ ! -s "${STATE_DIR}/state.json" ] || die "当前已安装隧道加密令牌；如需更换请使用 replace-token"
  mapfile -t tokens < <(token_args_from_input "$@")
  [ "${#tokens[@]}" -gt 0 ] || die "没有输入隧道加密令牌"
  local args=(install --state "${STATE_DIR}/state.json")
  local token
  for token in "${tokens[@]}"; do
    args+=(--token "${token}")
  done
  "${BIN_PATH}" "${args[@]}"
  ok "隧道加密令牌已安装到 ${STATE_DIR}/state.json"
}

replace_token() {
  [ -x "${BIN_PATH}" ] || die "请先安装 cakebox 二进制"
  [ -s "${STATE_DIR}/state.json" ] || die "当前还没有隧道加密令牌；请先使用 install-token"
  mapfile -t tokens < <(token_args_from_input "$@")
  [ "${#tokens[@]}" -gt 0 ] || die "没有输入新的隧道加密令牌"
  if [ "${CONFIRM_REPLACE_TOKEN:-}" != "yes" ]; then
    warn "替换会覆盖 ${STATE_DIR}/state.json 中现有隧道加密令牌"
    local confirm=""
    if [ -t 0 ]; then
      read -r -p "输入 yes 确认替换: " confirm
    else
      die "非交互替换隧道加密令牌需要设置 CONFIRM_REPLACE_TOKEN=yes"
    fi
    [ "${confirm}" = "yes" ] || die "已取消"
  fi
  local args=(install --state "${STATE_DIR}/state.json")
  local token
  for token in "${tokens[@]}"; do
    args+=(--token "${token}")
  done
  "${BIN_PATH}" "${args[@]}"
  ok "隧道加密令牌已替换到 ${STATE_DIR}/state.json"
  if has_systemd && systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    restart_service
  fi
}

write_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd，暂不写入服务"
  [ -n "${WEB_BIND}" ] || die "CakeBox Web 监听地址为空"
  URL_PREFIX="$(normalize_url_prefix "${URL_PREFIX}")"
  ensure_trusted_sidecar_digest
  save_install_env

  local miner_args=""
  [ -n "${MINER_LISTEN}" ] && miner_args=" --miner-listen ${MINER_LISTEN}"
  local advertised_args=""
  [ -n "${ADVERTISED_IP}" ] && advertised_args=" --advertised-ip ${ADVERTISED_IP}"
  local prefix_args=""
  [ -n "${URL_PREFIX}" ] && prefix_args=" --url-prefix ${URL_PREFIX}"
  ensure_web_token

  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=CakeBox HashCake Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH} run --state ${STATE_DIR}/state.json --sidecar-bin ${SIDECAR_PATH} --sidecar-sha256 ${TRUSTED_SIDECAR_SHA256} --sidecar-config ${STATE_DIR}/sidecar.json --listen-port ${LISTEN_PORT} --web-bind ${WEB_BIND} --web-token-store ${STATE_DIR}/web-token${miner_args}${advertised_args}${prefix_args}
Restart=always
RestartSec=2
TimeoutStopSec=10
KillMode=control-group
LimitNOFILE=1048576
StandardOutput=append:${LOG_DIR}/cakebox.service.log
StandardError=append:${LOG_DIR}/cakebox.err.log

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  ok "已写入 systemd 服务 ${SERVICE_FILE}"
}

print_install_result() {
  local token_file="${STATE_DIR}/web-token"
  cat <<EOF

========== CakeBox 安装结果 ==========
当前版本: $([ -x "${BIN_PATH}" ] && "${BIN_PATH}" --version 2>/dev/null || printf '未知')
混淆组件: $([ -x "${NOISE_PATH}" ] && "${NOISE_PATH}" --version 2>/dev/null || printf '未安装')
隧道 sidecar: $([ -x "${SIDECAR_PATH}" ] && sidecar_version "${SIDECAR_PATH}" || printf '未安装或版本不可识别')（要求 ${SING_BOX_VERSION}）
CakeBox 后台地址: $(web_url)
Web访问令牌: $([ -s "${token_file}" ] && cat "${token_file}" || printf '未生成')
Web访问令牌文件: ${token_file}
安全访问路径: /${URL_PREFIX}/
安装目录: ${INSTALL_DIR}
状态目录: ${STATE_DIR}
日志目录: ${LOG_DIR}
矿机入口: 由隧道加密令牌决定
提示: 已尝试关闭系统防火墙；云厂商安全组或局域网路由仍需自行确认端口 $(bind_port "${WEB_BIND}") 是否放行。
EOF
}

install_service() {
  need_root
  is_installed && die "检测到已安装 CakeBox，请使用 update 更新程序"
  check_no_running_conflict
  ensure_dirs
  migrate_legacy_account
  configure_web_defaults_for_install
  validate_web_bind_for_install
  disable_firewall
  ensure_web_token
  install_binary
  install_sidecar
  write_service
  systemctl enable "${SERVICE_NAME}.service"

  if [ ! -s "${STATE_DIR}/state.json" ]; then
    mapfile -t maybe_tokens < <(token_args_from_input)
    if [ "${#maybe_tokens[@]}" -gt 0 ]; then
      install_token "${maybe_tokens[@]}"
    else
      warn "还没有安装隧道加密令牌；服务已准备好，但不会自动启动"
      show_paths
      print_install_result
      return
    fi
  fi

  if [ "${START_AFTER_INSTALL}" = "1" ]; then
    restart_service
  else
    ok "已安装，未自动启动"
  fi
  print_install_result
}

update_service() {
  need_root
  is_installed || die "未检测到已安装 CakeBox，请先执行 install 首次安装"
  ensure_dirs
  migrate_legacy_account
  configure_web_defaults_for_update
  ensure_web_token
  install_binary
  install_sidecar
  write_service
  systemctl enable "${SERVICE_NAME}.service"

  if [ ! -s "${STATE_DIR}/state.json" ]; then
    warn "还没有安装隧道加密令牌；程序已更新，但不会自动启动"
    show_paths
    return
  fi

  if [ "${START_AFTER_INSTALL}" = "1" ]; then
    restart_service
  else
    ok "已更新，未自动启动"
  fi
  cat <<EOF

========== CakeBox 更新结果 ==========
当前版本: $([ -x "${BIN_PATH}" ] && "${BIN_PATH}" --version 2>/dev/null || printf '未知')
混淆组件: $([ -x "${NOISE_PATH}" ] && "${NOISE_PATH}" --version 2>/dev/null || printf '未安装')
隧道 sidecar: $([ -x "${SIDECAR_PATH}" ] && sidecar_version "${SIDECAR_PATH}" || printf '未安装或版本不可识别')（要求 ${SING_BOX_VERSION}）
CakeBox 后台地址: $(web_url)
安全访问路径: /${URL_PREFIX}/
提示: 更新已保留 Web 端口、安全访问路径、Web访问令牌、隧道加密令牌和状态目录。
EOF
}

start_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd"
  [ -s "${STATE_DIR}/state.json" ] || die "还没有安装隧道加密令牌，请先运行 install-token"
  systemctl start "${SERVICE_NAME}.service"
  sleep 2
  status_service
}

stop_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd"
  systemctl stop "${SERVICE_NAME}.service" || true
  ok "已停止 ${SERVICE_NAME}"
}

restart_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd"
  [ -s "${STATE_DIR}/state.json" ] || die "还没有安装隧道加密令牌，请先运行 install-token"
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
  sleep 2
  status_service
}

enable_service() {
  need_root
  systemctl enable "${SERVICE_NAME}.service"
  ok "已设置开机启动"
}

disable_service() {
  need_root
  systemctl disable "${SERVICE_NAME}.service" || true
  ok "已关闭开机启动"
}

status_service() {
  if has_systemd; then
    systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
  else
    pgrep -af "${BIN_PATH}" || true
  fi
  pgrep -af "$(basename "${SIDECAR_PATH}")" || true
  show_paths
}

log_files() {
  shopt -s nullglob
  local files=(
    "${LOG_DIR}/cakebox.service.log"
    "${LOG_DIR}/cakebox.err.log"
  )
  shopt -u nullglob
  printf '%s\n' "${files[@]}"
}

show_logs() {
  local lines="${LINES:-120}"
  local files
  mapfile -t files < <(log_files)
  [ "${#files[@]}" -gt 0 ] || die "还没有日志文件：${LOG_DIR}"
  tail -n "${lines}" "${files[@]}"
}

follow_logs() {
  local files
  mapfile -t files < <(log_files)
  [ "${#files[@]}" -gt 0 ] || die "还没有日志文件：${LOG_DIR}"
  tail -F "${files[@]}"
}

clear_logs() {
  need_root
  mkdir -p "${LOG_DIR}"
  find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log*' -exec sh -c ': > "$1"' _ {} \;
  ok "已清空 ${LOG_DIR} 下的日志文件"
}

show_web_token() {
  local token_file="${STATE_DIR}/web-token"
  [ -s "${token_file}" ] || die "Web访问令牌文件不存在：${token_file}"
  printf 'CakeBox Web访问令牌:\n%s\n' "$(cat "${token_file}")"
}

show_paths() {
  load_install_env
  cat <<EOF

安装目录: ${INSTALL_DIR}
状态目录: ${STATE_DIR}
日志目录: ${LOG_DIR}
二进制:   ${BIN_PATH}
混淆组件: ${NOISE_PATH}
Sidecar:  ${SIDECAR_PATH}
服务名:   ${SERVICE_NAME}
Web UI:   ${WEB_BIND:-未设置}
访问地址: $([ -n "${WEB_BIND:-}" ] && [ -n "${URL_PREFIX:-}" ] && web_url || printf '未设置')
安全访问路径: $([ -n "${URL_PREFIX:-}" ] && printf '/%s/' "${URL_PREFIX}" || printf '未设置')
矿机入口: 由隧道加密令牌决定；如需覆盖，用 CAKEBOX_MINER_LISTEN
发布仓库: https://github.com/${RELEASE_REPO}
EOF
  [ -s "${STATE_DIR}/web-token" ] && printf 'Web访问令牌文件: %s\n' "${STATE_DIR}/web-token"
  return 0
}

change_web_settings() {
  need_root
  ensure_dirs
  configure_web_defaults_for_update
  local current_port new_port new_prefix
  current_port="$(bind_port "${WEB_BIND}")"
  if [ -t 0 ]; then
    read -r -p "Web 端口 [${current_port}]: " new_port
    read -r -p "安全访问路径 [/${URL_PREFIX}/]: " new_prefix
  else
    new_port="${CAKEBOX_WEB_PORT:-}"
    new_prefix="${CAKEBOX_URL_PREFIX:-}"
  fi
  if [ -n "${new_port}" ]; then
    validate_port_value "${new_port}"
    if [ "${new_port}" != "${current_port}" ] && port_in_use "${new_port}"; then
      die "CakeBox Web 端口 ${new_port} 已被占用，请换一个端口"
    fi
    WEB_BIND="$(host_from_bind "${WEB_BIND}"):${new_port}"
  fi
  [ -n "${new_prefix}" ] && URL_PREFIX="$(normalize_url_prefix "${new_prefix}")"
  write_service
  if [ -s "${STATE_DIR}/state.json" ]; then
    restart_service
  fi
  show_paths
}

change_limit() {
  need_root
  log "设置 Linux 文件句柄上限"
  grep -q 'root soft nofile 1048576' /etc/security/limits.conf 2>/dev/null || echo 'root soft nofile 1048576' >> /etc/security/limits.conf
  grep -q 'root hard nofile 1048576' /etc/security/limits.conf 2>/dev/null || echo 'root hard nofile 1048576' >> /etc/security/limits.conf
  grep -q 'DefaultLimitNOFILE=1048576' /etc/systemd/system.conf 2>/dev/null || echo 'DefaultLimitNOFILE=1048576' >> /etc/systemd/system.conf
  systemctl daemon-reexec || true
  ok "已设置连接数上限，完整生效可能需要重启服务器"
}

uninstall() {
  need_root
  local confirm="${CONFIRM_UNINSTALL:-}"
  if [ "${confirm}" != "yes" ]; then
    if [ -t 0 ]; then
      read -r -p "确认卸载并删除 ${INSTALL_DIR}？输入 yes 继续: " confirm
    else
      die "非交互卸载需要设置 CONFIRM_UNINSTALL=yes"
    fi
  fi
  [ "${confirm}" = "yes" ] || die "已取消卸载"
  systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload 2>/dev/null || true
  rm -rf "${INSTALL_DIR}"
  ok "已卸载 ${APP_NAME}"
}

menu() {
  clear || true
  cat <<EOF
========== ${APP_NAME} 一键安装管理 ==========
安装目录: ${INSTALL_DIR}
服务名:   ${SERVICE_NAME}

1. 首次安装
2. 更新程序
3. 安装隧道加密令牌
4. 替换隧道加密令牌
5. 启动
6. 停止
7. 重启
8. 查看运行状态
9. 查看最近日志
10. 实时跟随日志
11. 清空日志
12. 设置开机启动
13. 关闭开机启动
14. 查看路径和访问地址
15. 修改 Web 访问设置
16. 显示 Web访问令牌
17. 关闭系统防火墙
18. 解除系统连接数限制
19. 卸载
0. 退出
EOF
  read -r -p "请选择 [0-19]: " choice
  case "${choice}" in
    1) install_service ;;
    2) update_service ;;
    3) shift || true; install_token ;;
    4) shift || true; replace_token ;;
    5) start_service ;;
    6) stop_service ;;
    7) restart_service ;;
    8) status_service ;;
    9) show_logs ;;
    10) follow_logs ;;
    11) clear_logs ;;
    12) enable_service ;;
    13) disable_service ;;
    14) show_paths ;;
    15) change_web_settings ;;
    16) show_web_token ;;
    17) disable_firewall ;;
    18) change_limit ;;
    19) uninstall ;;
    0) exit 0 ;;
    *) die "无效选择" ;;
  esac
}

if [ "${CAKEBOX_INSTALLER_SOURCE_ONLY:-0}" = "1" ]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

cmd="${1:-menu}"
case "${cmd}" in
  install) install_service ;;
  update) update_service ;;
  install-token) shift; install_token "$@" ;;
  replace-token) shift; replace_token "$@" ;;
  start) start_service ;;
  stop) stop_service ;;
  restart) restart_service ;;
  status) status_service ;;
  logs) show_logs ;;
  follow-logs) follow_logs ;;
  clear-logs) clear_logs ;;
  enable) enable_service ;;
  disable) disable_service ;;
  paths|show-url) show_paths ;;
  web-settings|configure-web) change_web_settings ;;
  web-token|show-web-token) show_web_token ;;
  disable-firewall) disable_firewall ;;
  limit) change_limit ;;
  write-service) ensure_dirs; configure_web_defaults_for_update; write_service ;;
  uninstall) uninstall ;;
  menu|"") menu ;;
  *) die "未知命令：${cmd}" ;;
esac
