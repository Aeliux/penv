#!/usr/bin/env bash
# config.sh - Configuration and constants

# -------- Configuration --------
PENV_DIR="${HOME}/.penv"
CACHE_DIR="${PENV_DIR}/cache"
ENVS_DIR="${PENV_DIR}/envs"
BIN_DIR="${PENV_DIR}/bin"
LOCAL_INDEX="${PENV_DIR}/local_index.json"

# Remote index URL - change this to use a different index
INDEX_URL="${PENV_INDEX_URL:-https://raw.githubusercontent.com/Aeliux/penv/master/index.json}"

# Detect system architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;           # Popular: amd64
  aarch64|arm64) ARCH="arm64" ;;          # Popular: arm64
  armv8*|armv8l) ARCH="arm64" ;;          # Popular: arm64
  armv7l|armhf) ARCH="armhf" ;;           # Popular: armhf
  armv6l|armel) ARCH="armel" ;;           # Popular: armel
  i686|i386) ARCH="i386" ;;               # Popular: i386
  x86|i486|i586) ARCH="i386" ;;           # Popular: i386
  ppc64le) ARCH="ppc64le" ;;              # Popular: ppc64le
  ppc64) ARCH="ppc64" ;;                  # Popular: ppc64
  s390x) ARCH="s390x" ;;                  # Popular: s390x
  riscv64) ARCH="riscv64" ;;              # Popular: riscv64
  mips64el) ARCH="mips64el" ;;            # Popular: mips64el
  mipsel) ARCH="mipsel" ;;                # Popular: mipsel
  mips64) ARCH="mips64" ;;                # Popular: mips64
  mips) ARCH="mips" ;;                    # Popular: mips
  *) ;;                                   # Leave as-is if unknown
esac

# -------- Color codes --------
C_RESET='\e[0m'
C_BOLD='\e[1m'
C_DIM='\e[2m'
C_RED='\e[1;31m'
C_GREEN='\e[1;32m'
C_YELLOW='\e[1;33m'
C_BLUE='\e[1;34m'
C_MAGENTA='\e[1;35m'
C_CYAN='\e[1;36m'
C_WHITE='\e[1;37m'

# -------- download tool detection (prefer aria2c, curl, wget) --------
DL_TOOL=""
if command -v aria2c >/dev/null 2>&1; then
  DL_TOOL="aria2c"
elif command -v curl >/dev/null 2>&1; then
  DL_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL_TOOL="wget"
fi
