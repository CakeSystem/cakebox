#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="CakeBox"
RELEASE_REPO="${CAKEBOX_RELEASE_REPO:-CakeSystem/cakebox}"
RELEASE_TAG="${CAKEBOX_VERSION:-latest}"
RELEASE_BRANCH="${CAKEBOX_RELEASE_BRANCH:-main}"
RELEASE_PLATFORM="${CAKEBOX_RELEASE_PLATFORM:-linux-amd64}"
SERVICE_NAME="${CAKEBOX_SERVICE:-cakebox}"
INSTALL_DIR="${CAKEBOX_HOME:-/opt/cakebox}"
STATE_DIR="${CAKEBOX_STATE_DIR:-${INSTALL_DIR}/state}"
LOG_DIR="${CAKEBOX_LOG_DIR:-${INSTALL_DIR}/logs}"
BACKUP_DIR="${CAKEBOX_BACKUP_DIR:-${INSTALL_DIR}/backup}"
BIN_PATH="${INSTALL_DIR}/cakebox"
NOISE_PATH="${CAKEBOX_NOISE_PATH:-${INSTALL_DIR}/cakebox-noise}"
SIDECAR_PATH="${CAKEBOX_SIDECAR_PATH:-${INSTALL_DIR}/factory-telemetry-agent}"
LISTEN_PORT="${CAKEBOX_LISTEN_PORT:-18082}"
WEB_BIND="${CAKEBOX_WEB_BIND:-127.0.0.1:18080}"
WEB_TOKEN="${CAKEBOX_WEB_TOKEN:-}"
MINER_LISTEN="${CAKEBOX_MINER_LISTEN:-}"
ADVERTISED_IP="${CAKEBOX_ADVERTISED_IP:-}"
URL_PREFIX="${CAKEBOX_URL_PREFIX:-}"
START_AFTER_INSTALL="${CAKEBOX_START_AFTER_INSTALL:-1}"
BUILD_FEATURES="${CAKEBOX_FEATURES:-}"
SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.12}"

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

build_binaries() {
  [ -f "${SOURCE_ROOT}/Cargo.toml" ] || die "当前脚本不在源码仓库内；请设置 CAKEBOX_BIN_SOURCE 或 CAKEBOX_DOWNLOAD_URL"
  command -v cargo >/dev/null 2>&1 || die "缺少 cargo，无法从源码构建"
  log "构建 cakebox release 二进制"
  if [ -n "${BUILD_FEATURES}" ]; then
    cargo build --release -p cakebox --features "${BUILD_FEATURES}"
  else
    cargo build --release -p cakebox
  fi
  log "构建 cakebox-noise release 二进制"
  cargo build --release -p cakebox-noise
}

download_cakebox() {
  local url="${CAKEBOX_DOWNLOAD_URL:-}"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 CAKEBOX_DOWNLOAD_URL"
  if [ -z "${url}" ]; then
    case "$(uname -s):$(uname -m)" in
      Linux:x86_64|Linux:amd64) ;;
      *) return 1 ;;
    esac
    local asset
    asset="$(asset_name_for_version cakebox)"
    log "下载 cakebox 二进制：github.com/${RELEASE_REPO}/${RELEASE_PLATFORM}/${asset}"
    download_repo_file "${RELEASE_PLATFORM}/${asset}" "${BIN_PATH}.download"
  else
    log "下载 cakebox 二进制：${url}"
    curl -fL "${url}" -o "${BIN_PATH}.download"
  fi
  install -m 0755 "${BIN_PATH}.download" "${BIN_PATH}"
  rm -f "${BIN_PATH}.download"
  return 0
}

download_noise() {
  local url="${CAKEBOX_NOISE_DOWNLOAD_URL:-}"
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 CAKEBOX_NOISE_DOWNLOAD_URL"
  if [ -z "${url}" ]; then
    case "$(uname -s):$(uname -m)" in
      Linux:x86_64|Linux:amd64) ;;
      *) return 1 ;;
    esac
    local asset
    asset="$(asset_name_for_version cakebox-noise)"
    log "下载 cakebox-noise 二进制：github.com/${RELEASE_REPO}/${RELEASE_PLATFORM}/${asset}"
    download_repo_file "${RELEASE_PLATFORM}/${asset}" "${NOISE_PATH}.download"
  else
    log "下载 cakebox-noise 二进制：${url}"
    curl -fL "${url}" -o "${NOISE_PATH}.download"
  fi
  install -m 0755 "${NOISE_PATH}.download" "${NOISE_PATH}"
  rm -f "${NOISE_PATH}.download"
  return 0
}

install_binary() {
  local src="${CAKEBOX_BIN_SOURCE:-}"
  local noise_src="${CAKEBOX_NOISE_BIN_SOURCE:-}"
  if [ -n "${src}" ]; then
    [ -x "${src}" ] || die "CAKEBOX_BIN_SOURCE 不存在或不可执行：${src}"
    install -m 0755 "${src}" "${BIN_PATH}"
    ok "已安装二进制 ${BIN_PATH}"
    if [ -n "${noise_src}" ]; then
      [ -x "${noise_src}" ] || die "CAKEBOX_NOISE_BIN_SOURCE 不存在或不可执行：${noise_src}"
      install -m 0755 "${noise_src}" "${NOISE_PATH}"
      ok "已安装混淆组件 ${NOISE_PATH}"
    elif [ -x "${SOURCE_ROOT}/target/release/cakebox-noise" ]; then
      install -m 0755 "${SOURCE_ROOT}/target/release/cakebox-noise" "${NOISE_PATH}"
      ok "已安装混淆组件 ${NOISE_PATH}"
    else
      warn "未安装 cakebox-noise；需要时请设置 CAKEBOX_NOISE_BIN_SOURCE 或把 cakebox-noise 放到 PATH"
    fi
    return
  fi

  if download_cakebox; then
    if download_noise; then
      ok "已安装混淆组件 ${NOISE_PATH}"
    else
      warn "未设置 CAKEBOX_NOISE_DOWNLOAD_URL；本次只安装 cakebox 主程序"
    fi
    ok "已安装下载的二进制 ${BIN_PATH}"
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

download_sidecar() {
  command -v curl >/dev/null 2>&1 || die "缺少 curl，无法下载 sing-box"
  command -v tar >/dev/null 2>&1 || die "缺少 tar，无法解压 sing-box"
  local arch url tmp found
  arch="$(singbox_arch)"
  url="${SING_BOX_DOWNLOAD_URL:-https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${arch}.tar.gz}"
  tmp="$(mktemp -d)"
  log "下载 sing-box sidecar：${url}"
  curl -fL "${url}" -o "${tmp}/sing-box.tar.gz"
  tar -xzf "${tmp}/sing-box.tar.gz" -C "${tmp}"
  found="$(find "${tmp}" -type f -name 'sing-box' | head -n 1)"
  [ -n "${found}" ] || die "压缩包中没有找到 sing-box"
  install -m 0755 "${found}" "${SIDECAR_PATH}"
  rm -rf "${tmp}"
}

install_sidecar() {
  local src="${SIDECAR_BIN_SOURCE:-}"
  if [ -n "${src}" ]; then
    [ -x "${src}" ] || die "SIDECAR_BIN_SOURCE 不存在或不可执行：${src}"
    install -m 0755 "${src}" "${SIDECAR_PATH}"
    ok "已安装 sidecar ${SIDECAR_PATH}"
    return
  fi
  if [ -x "${SOURCE_ROOT}/factory-telemetry-agent" ]; then
    install -m 0755 "${SOURCE_ROOT}/factory-telemetry-agent" "${SIDECAR_PATH}"
    ok "已安装 sidecar ${SIDECAR_PATH}"
    return
  fi
  if [ -x "/usr/local/bin/factory-telemetry-agent" ]; then
    install -m 0755 "/usr/local/bin/factory-telemetry-agent" "${SIDECAR_PATH}"
    ok "已安装 sidecar ${SIDECAR_PATH}"
    return
  fi
  if [ -x "/usr/local/bin/sing-box" ]; then
    install -m 0755 "/usr/local/bin/sing-box" "${SIDECAR_PATH}"
    ok "已安装 sidecar ${SIDECAR_PATH}"
    return
  fi
  download_sidecar
  ok "已安装 sidecar ${SIDECAR_PATH}"
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
    read -r -p "请输入 Activation Token；多个 token 用逗号分隔，留空跳过: " raw
    [ -n "${raw}" ] && printf '%s\n' "${raw}" | tr ', ' '\n' | sed '/^[[:space:]]*$/d'
  fi
}

install_token() {
  [ -x "${BIN_PATH}" ] || die "请先安装 cakebox 二进制"
  mapfile -t tokens < <(token_args_from_input "$@")
  [ "${#tokens[@]}" -gt 0 ] || die "没有输入 Activation Token"
  if [ -s "${STATE_DIR}/state.json" ] && [ "${CONFIRM_REPLACE_TOKEN:-}" != "yes" ]; then
    warn "当前已有 ${STATE_DIR}/state.json；cakebox install 会替换 token 集合"
    local confirm=""
    if [ -t 0 ]; then
      read -r -p "输入 yes 继续替换: " confirm
    else
      die "非交互替换 Activation Token 需要设置 CONFIRM_REPLACE_TOKEN=yes"
    fi
    [ "${confirm}" = "yes" ] || die "已取消"
  fi
  local args=(install --state "${STATE_DIR}/state.json")
  local token
  for token in "${tokens[@]}"; do
    args+=(--token "${token}")
  done
  "${BIN_PATH}" "${args[@]}"
  ok "Activation Token 已安装到 ${STATE_DIR}/state.json"
}

write_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd，暂不写入服务"

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
ExecStart=${BIN_PATH} run --state ${STATE_DIR}/state.json --sidecar-bin ${SIDECAR_PATH} --sidecar-config ${STATE_DIR}/sidecar.json --listen-port ${LISTEN_PORT} --web-bind ${WEB_BIND} --web-token-store ${STATE_DIR}/web-token${miner_args}${advertised_args}${prefix_args}
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

install_or_update() {
  need_root
  ensure_dirs
  install_binary
  install_sidecar
  write_service
  systemctl enable "${SERVICE_NAME}.service"

  if [ ! -s "${STATE_DIR}/state.json" ]; then
    mapfile -t maybe_tokens < <(token_args_from_input)
    if [ "${#maybe_tokens[@]}" -gt 0 ]; then
      install_token "${maybe_tokens[@]}"
    else
      warn "还没有安装 Activation Token；服务已准备好，但不会自动启动"
      show_paths
      return
    fi
  fi

  if [ "${START_AFTER_INSTALL}" = "1" ]; then
    restart_service
  else
    ok "已安装，未自动启动"
  fi
}

start_service() {
  need_root
  has_systemd || die "当前系统没有可用 systemd"
  [ -s "${STATE_DIR}/state.json" ] || die "还没有安装 Activation Token，请先运行 install-token"
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
  [ -s "${STATE_DIR}/state.json" ] || die "还没有安装 Activation Token，请先运行 install-token"
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
  [ -s "${token_file}" ] || die "Web token 文件不存在：${token_file}"
  printf 'CakeBox Web Bearer token:\n%s\n' "$(cat "${token_file}")"
}

show_paths() {
  cat <<EOF

安装目录: ${INSTALL_DIR}
状态目录: ${STATE_DIR}
日志目录: ${LOG_DIR}
二进制:   ${BIN_PATH}
混淆组件: ${NOISE_PATH}
Sidecar:  ${SIDECAR_PATH}
服务名:   ${SERVICE_NAME}
Web UI:   ${WEB_BIND}
矿机入口: 由 Activation Token 决定；如需覆盖，用 CAKEBOX_MINER_LISTEN
发布仓库: https://github.com/${RELEASE_REPO}
EOF
  [ -s "${STATE_DIR}/web-token" ] && printf 'Web token 文件: %s\n' "${STATE_DIR}/web-token"
  return 0
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

1. 安装 / 更新
2. 安装 / 替换 Activation Token
3. 启动
4. 停止
5. 重启
6. 查看运行状态
7. 查看最近日志
8. 实时跟随日志
9. 清空日志
10. 设置开机启动
11. 关闭开机启动
12. 查看路径和访问地址
13. 显示 Web token
14. 解除系统连接数限制
15. 卸载
0. 退出
EOF
  read -r -p "请选择 [0-15]: " choice
  case "${choice}" in
    1) install_or_update ;;
    2) shift || true; install_token ;;
    3) start_service ;;
    4) stop_service ;;
    5) restart_service ;;
    6) status_service ;;
    7) show_logs ;;
    8) follow_logs ;;
    9) clear_logs ;;
    10) enable_service ;;
    11) disable_service ;;
    12) show_paths ;;
    13) show_web_token ;;
    14) change_limit ;;
    15) uninstall ;;
    0) exit 0 ;;
    *) die "无效选择" ;;
  esac
}

cmd="${1:-menu}"
case "${cmd}" in
  install|update) install_or_update ;;
  install-token) shift; install_token "$@" ;;
  start) start_service ;;
  stop) stop_service ;;
  restart) restart_service ;;
  status) status_service ;;
  logs) show_logs ;;
  follow-logs) follow_logs ;;
  clear-logs) clear_logs ;;
  enable) enable_service ;;
  disable) disable_service ;;
  paths) show_paths ;;
  web-token) show_web_token ;;
  limit) change_limit ;;
  write-service) ensure_dirs; write_service ;;
  uninstall) uninstall ;;
  menu|"") menu ;;
  *) die "未知命令：${cmd}" ;;
esac
