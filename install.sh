#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Simple Gre Installer
# Repo: https://github.com/ach1992/simple-gre
# =========================

REPO_RAW_BASE="https://raw.githubusercontent.com/ach1992/simple-gre/main"
SCRIPT_NAME_IN_REPO="gre_manager.sh"     # <-- make sure your main script in repo has this name
INSTALL_PATH="/usr/local/bin/simple-gre" # command name
TMP_DIR="/tmp/simple-gre-install.$$"

RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
log()  { echo -e "${BLU}[INFO]${NC} $*"; }
ok()   { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "${YEL}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Run as root. Example:"
    echo "  curl -fsSL ${REPO_RAW_BASE}/install.sh | sudo bash"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  log "Installing dependencies (Debian/Ubuntu)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl iproute2 iputils-ping tcpdump
  ok "Dependencies installed."
}

download_script() {
  mkdir -p "$TMP_DIR"
  log "Downloading ${SCRIPT_NAME_IN_REPO}..."
  curl -fsSL "${REPO_RAW_BASE}/${SCRIPT_NAME_IN_REPO}" -o "${TMP_DIR}/${SCRIPT_NAME_IN_REPO}"
  ok "Downloaded."
}

install_script() {
  log "Installing to ${INSTALL_PATH}..."
  install -m 0755 "${TMP_DIR}/${SCRIPT_NAME_IN_REPO}" "${INSTALL_PATH}"
  ok "Installed."
}

verify() {
  log "Verifying install..."
  if [[ ! -x "${INSTALL_PATH}" ]]; then
    err "Install failed: ${INSTALL_PATH} is not executable."
    exit 1
  fi
  ok "Command available: simple-gre"
  echo
  echo "Run:"
  echo "  sudo simple-gre"
}

cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}

main() {
  need_root

  if ! have_cmd apt-get; then
    err "This installer currently supports Debian/Ubuntu (apt-get not found)."
    exit 1
  fi

  # Install deps if missing
  if ! have_cmd curl || ! have_cmd ip || ! have_cmd ping; then
    install_deps
  else
    # still ensure tcpdump exists (nice for troubleshooting)
    if ! have_cmd tcpdump; then
      install_deps
    fi
  fi

  download_script
  install_script
  verify
  cleanup
}

main "$@"
