#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Simple Gre Installer (Minimal / No-unneeded-updates)
# Repo: https://github.com/ach1992/simple-gre
# =========================

REPO_RAW_BASE="https://raw.githubusercontent.com/ach1992/simple-gre/main"
SCRIPT_NAME_IN_REPO="gre_manager.sh"
INSTALL_PATH="/usr/local/bin/simple-gre"
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

# Only install missing deps. Avoid apt-get update unless needed.
install_missing_deps_if_possible() {
  local missing=()
  # For installer: curl required to download
  have_cmd curl || missing+=("curl")
  # For runtime: ip + ping required
  have_cmd ip   || missing+=("iproute2")
  have_cmd ping || missing+=("iputils-ping")

  if ((${#missing[@]} == 0)); then
    ok "All required commands are already installed. Skipping apt operations."
    return 0
  fi

  if ! have_cmd apt-get; then
    err "apt-get not found. This installer supports Debian/Ubuntu."
    err "Missing dependencies: ${missing[*]}"
    err "Please install them manually and rerun installer."
    return 1
  fi

  warn "Missing dependencies detected: ${missing[*]}"
  warn "Attempting to install only missing packages (minimal changes)."

  export DEBIAN_FRONTEND=noninteractive

  # Try install without apt-get update first (often avoids repo/DNS issues).
  if apt-get install -y "${missing[@]}"; then
    ok "Installed missing dependencies without apt-get update."
    return 0
  fi

  warn "Install failed without apt-get update."
  warn "Trying: apt-get update (best effort) then install missing packages..."

  # Best effort update + install
  if apt-get update -y && apt-get install -y "${missing[@]}"; then
    ok "Installed missing dependencies after apt-get update."
    return 0
  fi

  err "Could not install required dependencies automatically."
  err "Please fix apt/network, then install manually:"
  err "  apt-get update && apt-get install -y ${missing[*]}"
  return 1
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

cleanup() { rm -rf "$TMP_DIR" >/dev/null 2>&1 || true; }

main() {
  need_root

  install_missing_deps_if_possible

  download_script
  install_script
  cleanup

  ok "Installed successfully."
  echo
  echo "Run:"
  echo "  sudo simple-gre"
}

main "$@"
