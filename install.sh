#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="ach1992"
REPO_NAME="simple-gre"
BRANCH="main"

BIN_NAME="simple-gre"
INSTALL_PATH="/usr/local/bin/${BIN_NAME}"

SCRIPT_FILE_IN_REPO="gre_manager.sh"

RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[0;33m"; BLU="\033[0;34m"; NC="\033[0m"
log(){ echo -e "${BLU}[INFO]${NC} $*"; }
ok(){ echo -e "${GRN}[OK]${NC} $*"; }
warn(){ echo -e "${YEL}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERROR]${NC} $*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Please run as root (use sudo)."
    exit 1
  fi
}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

install_deps() {
  if ! have_cmd curl; then
    log "Installing curl..."
    apt-get update -y
    apt-get install -y curl
  fi
  if ! have_cmd ip; then
    log "Installing iproute2..."
    apt-get update -y
    apt-get install -y iproute2
  fi
  if ! have_cmd systemctl; then
    err "systemd is required (systemctl not found)."
    exit 1
  fi
}

download_script() {
  local url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${SCRIPT_FILE_IN_REPO}"
  log "Downloading ${SCRIPT_FILE_IN_REPO} from:"
  log "  ${url}"

  curl -fsSL "$url" -o "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
}

post_install() {
  ok "Installed: ${INSTALL_PATH}"
  echo
  echo "Run it with:"
  echo "  sudo ${BIN_NAME}"
}

main() {
  require_root

  if ! have_cmd apt-get; then
    err "This installer supports Debian/Ubuntu (apt-get required)."
    exit 1
  fi

  install_deps
  download_script
  post_install
}

main "$@"
