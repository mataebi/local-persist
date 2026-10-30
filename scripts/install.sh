#!/usr/bin/env bash
set -e

VERSION="v1.3.0"

# Default repo — used when the script is run via a pipe (curl | bash),
# where $BASH_SOURCE is empty and we can't detect a git checkout.
REPO="mataebi/local-persist"

# When run from a git checkout of the fork, derive the repo from the remote.
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ -n "$SCRIPT_PATH" && "$SCRIPT_PATH" != "bash" ]]; then
  gitDir=$(realpath "$(dirname "$SCRIPT_PATH")/.." 2>/dev/null || true)
  if [[ -n "$gitDir" ]] && command -v git >/dev/null 2>&1; then
    thisGit=$(git -C "$gitDir" config --get remote.origin.url 2>/dev/null || true)
    if [[ -n "$thisGit" ]]; then
      thisGit=${thisGit%.git}
      REPO=${thisGit#https://github.com/}
    fi
  fi
fi

GITHUB_BINARY_BASE="https://github.com/${REPO}/releases/download"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${REPO}/master"

echo "Installing local-persist from ${REPO} (${VERSION})"

# --- sanity: must run as root ---
if [[ "$(id -u)" != "0" ]]; then
  echo "NOTE: sudo needed to set up and run the service"
  exit 1
fi

function setenv {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  SUPPORTED=false
  if [[ "$OS" == "linux" ]]; then
    case "$ARCH" in
      x86_64)  ARCH="amd64"; SUPPORTED=true ;;
      aarch64) ARCH="arm64"; SUPPORTED=true ;;
      i686)    SUPPORTED=false ;; # untested
      arm*)    SUPPORTED=false ;; # untested
    esac
  elif [[ "$OS" == "freebsd" ]]; then
    ARCH=$(uname -m)
    SUPPORTED=false
  fi
  if [[ "$SUPPORTED" == false ]]; then
    echo "$OS $ARCH is not supported"
    exit 2
  fi
}

function install-binary {
  echo "Stopping docker-volume-local-persist service if running"
  echo ''
  if [[ "$*" == *--upstart* ]]; then
    (sudo service docker-volume-local-persist stop || true)
  else
    (sudo systemctl stop docker-volume-local-persist || true)
  fi

  BINARY_URL="${GITHUB_BINARY_BASE}/${VERSION}/local-persist-${OS}-${ARCH}"
  BINARY_DEST="/usr/bin/docker-volume-local-persist"
  echo "Downloading binary:"
  echo "  From: $BINARY_URL"
  echo "  To:   $BINARY_DEST"
  curl -fLsS "$BINARY_URL" > "$BINARY_DEST"
  chmod +x "$BINARY_DEST"
  echo "Binary downloaded"
  echo ''
}

function setup-systemd {
  SYSTEMD_CONFIG_URL="${GITHUB_RAW_BASE}/init/systemd.service"
  SYSTEMD_CONFIG_DEST="/etc/systemd/system/docker-volume-local-persist.service"
  echo "Downloading Systemd service conf:"
  echo "  From: $SYSTEMD_CONFIG_URL"
  echo "  To:   $SYSTEMD_CONFIG_DEST"
  sudo curl -fLsS "$SYSTEMD_CONFIG_URL" > "$SYSTEMD_CONFIG_DEST"
  echo "Systemd conf downloaded"
  echo ''
}

function start-systemd {
  echo "Starting docker-volume-local-persist service..."
  sudo systemctl daemon-reload
  sudo systemctl enable docker-volume-local-persist
  sudo systemctl start docker-volume-local-persist
  sudo systemctl status --full --no-pager docker-volume-local-persist
  echo ''
  echo "Done! If you see this message, that should mean everything is installed and is running."
}

function setup-upstart {
  UPSTART_CONFIG_URL="${GITHUB_RAW_BASE}/init/upstart.conf"
  UPSTART_CONFIG_DEST="/etc/init/docker-volume-local-persist.conf"
  echo "Downloading Upstart conf:"
  echo "  From: $UPSTART_CONFIG_URL"
  echo "  To:   $UPSTART_CONFIG_DEST"
  sudo curl -fLsS "$UPSTART_CONFIG_URL" > "$UPSTART_CONFIG_DEST"
  echo "Upstart conf downloaded"
  echo ''
}

function start-upstart {
  echo "Reloading Upstart config and starting docker-volume-local-persist service..."
  sudo initctl reload-configuration
  sudo service docker-volume-local-persist start
  sudo service docker-volume-local-persist status
  echo ''
  echo "Done! If you see this message, that should mean everything is installed and is running."
}

setenv

if [[ "$*" == *--upstart* ]]; then
  install-binary --upstart
  setup-upstart
  start-upstart
else
  install-binary
  setup-systemd
  start-systemd
fi
