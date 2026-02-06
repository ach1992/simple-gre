#!/usr/bin/env bash
set -Eeuo pipefail

# ==================================================
# Simple GRE Installer
#
# Offline usage (local files):
#   sudo bash install.sh
#
# Online usage (download latest):
#   curl -fsSL https://raw.githubusercontent.com/ach1992/simple-gre/main/install.sh | sudo bash
#
# If local gre_manager.sh exists, user will be asked:
#   - Use local file (offline)
#   - Download latest version (online)
# ==================================================

REPO_RAW_BASE="https://raw.githubusercontent.com/ach1992/simple-gre/main"
SCRIPT_NAME="gre_manager.sh"
INSTALL_PATH="/usr/local/bin/simple-gre"
ROOT_UPLOAD_DIR="/root/simple-gre"
TMP_DIR="/tmp/simple-gre-install.$$"

RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
log()  { echo -e "${BLU}[INFO]${NC} $*"; }
ok()   { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "${YEL}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "This installer must be run as root."
    echo "Example:"
    echo "  sudo bash install.sh"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

install_missing_deps_if_possible() {
  local missing=()
  have_cmd ip   || missing+=("iproute2")
  have_cmd ping || missing+=("iputils-ping")

  if ((${#missing[@]} == 0)); then
    ok "All required dependencies are already installed."
    return 0
  fi

  if ! have_cmd apt-get; then
    err "apt-get not found. Missing dependencies: ${missing[*]}"
    err "Please install them manually and re-run the installer."
    return 1
  fi

  warn "Installing missing dependencies: ${missing[*]}"
  export DEBIAN_FRONTEND=noninteractive

  if apt-get install -y "${missing[@]}"; then
    ok "Dependencies installed successfully."
    return 0
  fi

  warn "Retrying after apt-get update..."
  apt-get update -y
  apt-get install -y "${missing[@]}"
}

ask_install_mode() {
  local choice

  echo
  echo "Local ${SCRIPT_NAME} detected."
  echo "Choose installation mode:"
  echo "  [1] Use local file (offline)"
  echo "  [2] Download latest version (online)"
  echo

  # Read from terminal even if stdin is piped
  read -r -p "Select [1/2] (default: 1): " choice </dev/tty || true

  case "${choice:-1}" in
    2)
      echo "online"
      ;;
    *)
      echo "offline"
      ;;
  esac
}

prepare_script() {
  mkdir -p "$TMP_DIR"

  local base local_path
  base="$(script_dir)"
  local_path="${base}/${SCRIPT_NAME}"

  # Case 1: local gre_manager.sh exists
  if [[ -f "$local_path" ]]; then
    local mode
    mode="$(ask_install_mode)"

    if [[ "$mode" == "offline" ]]; then
      log "Using local ${SCRIPT_NAME} (offline mode)."
      cp -f "$local_path" "${TMP_DIR}/${SCRIPT_NAME}"
      return 0
    fi

    log "Downloading latest ${SCRIPT_NAME} (online mode)."
  else
    # Case 2: no local file
    if [[ -f "${BASH_SOURCE[0]}" ]]; then
      err "Local ${SCRIPT_NAME} not found."
      err "Offline installation is not possible."
      exit 1
    fi

    log "Installer running from stdin. Using online mode."
  fi

  # Online download
  if ! have_cmd curl; then
    err "curl is required for online installation."
    exit 1
  fi

  curl -fsSL "${REPO_RAW_BASE}/${SCRIPT_NAME}" -o "${TMP_DIR}/${SCRIPT_NAME}"
  ok "Downloaded latest ${SCRIPT_NAME}."
}

copy_to_root() {
  mkdir -p "$ROOT_UPLOAD_DIR"
  chmod 700 "$ROOT_UPLOAD_DIR" || true

  if [[ -f "${TMP_DIR}/${SCRIPT_NAME}" ]]; then
    cp -f "${TMP_DIR}/${SCRIPT_NAME}" "${ROOT_UPLOAD_DIR}/${SCRIPT_NAME}"
    chmod 755 "${ROOT_UPLOAD_DIR}/${SCRIPT_NAME}"
  fi

  if [[ -f "${BASH_SOURCE[0]}" ]]; then
    local base
    base="$(script_dir)"
    if [[ -f "${base}/install.sh" ]]; then
      cp -f "${base}/install.sh" "${ROOT_UPLOAD_DIR}/install.sh"
      chmod 755 "${ROOT_UPLOAD_DIR}/install.sh"
    fi
  fi

  ok "Installer files saved to ${ROOT_UPLOAD_DIR}"
}

install_script() {
  install -m 0755 "${TMP_DIR}/${SCRIPT_NAME}" "${INSTALL_PATH}"
  ok "Command installed: simple-gre"
}

cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

main() {
  need_root
  install_missing_deps_if_possible
  prepare_script
  copy_to_root
  install_script
  cleanup

  echo
  ok "Installation completed successfully."
  echo "Run:"
  echo "  sudo simple-gre"
}

main "$@"
