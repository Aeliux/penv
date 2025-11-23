#!/usr/bin/env bash
# penv - simple proot-based env manager

set -euo pipefail
IFS=$'\n\t'

# -------- Configuration --------
PENV_DIR="${HOME}/.penv"
CACHE_DIR="${PENV_DIR}/cache"
ENVS_DIR="${PENV_DIR}/envs"
BIN_DIR="${HOME}/bin"

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

# -------- Icons --------
ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_ARROW="→"
ICON_INFO="ℹ"
ICON_DOWNLOAD="⬇"
ICON_PACKAGE="📦"
ICON_SHELL="🐚"
ICON_TRASH="🗑"

# Default distro mapping (key -> tarball URL)
declare -A DISTROS=(
  [ubuntu-24.04]="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz"
  [alpine-3.22]="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz"
)

# -------- download tool detection (prefer aria2c, curl, wget) --------
DL_TOOL=""
if command -v aria2c >/dev/null 2>&1; then
  DL_TOOL="aria2c"
elif command -v curl >/dev/null 2>&1; then
  DL_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL_TOOL="wget"
fi

# -------- helpers --------
msg(){ printf "${C_GREEN}${ICON_CHECK}${C_RESET} %s\n" "$*"; }
info(){ printf "${C_CYAN}${ICON_INFO}${C_RESET} %s\n" "$*"; }
warn(){ printf "${C_YELLOW}⚠${C_RESET}  %s\n" "$*"; }
err(){ printf "${C_RED}${ICON_CROSS} ERROR:${C_RESET} %s\n" "$*" >&2; }
header(){ printf "\n${C_BOLD}${C_CYAN}%s${C_RESET}\n" "$*"; }
ensure_dirs(){
  mkdir -p "$CACHE_DIR" "$ENVS_DIR" "$BIN_DIR"
}

# Progress bar for downloads
show_progress(){
  local current="$1" total="$2"
  local percent=$((current * 100 / total))
  local filled=$((percent / 2))
  local empty=$((50 - filled))
  printf "\r${C_CYAN}${ICON_DOWNLOAD}${C_RESET} ["
  printf "%${filled}s" | tr ' ' '█'
  printf "%${empty}s" | tr ' ' '░'
  printf "] ${C_BOLD}%3d%%${C_RESET}" "$percent"
}
require_proot(){
  if ! command -v proot >/dev/null 2>&1; then
    err "proot is required. Install it: sudo apt update && sudo apt install -y proot"
    exit 1
  fi
}
usage(){
  cat <<USAGE
${C_BOLD}${C_MAGENTA}penv${C_RESET} - proot environment manager

${C_BOLD}USAGE:${C_RESET}
  ${C_GREEN}penv init${C_RESET}                    Initialize penv
  ${C_GREEN}penv download${C_RESET} ${C_YELLOW}<id>${C_RESET}          Download a distro (use -l to list available)
  ${C_GREEN}penv download -l${C_RESET}             List all available distros
  ${C_GREEN}penv create${C_RESET} ${C_YELLOW}<name>${C_RESET} ${C_YELLOW}<id>${C_RESET}      Create new environment (use -l to list distros)
  ${C_GREEN}penv create -l${C_RESET}               List available distros for creation
  ${C_GREEN}penv shell${C_RESET} ${C_YELLOW}<name>${C_RESET}            Enter environment shell
  ${C_GREEN}penv list${C_RESET}                    List all environments
  ${C_GREEN}penv delete${C_RESET} ${C_YELLOW}<name>${C_RESET}          Delete an environment
  ${C_GREEN}penv cache${C_RESET}                   Show cached downloads
  ${C_GREEN}penv clean${C_RESET} ${C_YELLOW}<id>${C_RESET}             Remove cached distro
  ${C_GREEN}penv clean --all${C_RESET}            Remove all cached downloads

${C_BOLD}EXAMPLES:${C_RESET}
  penv download ubuntu-24.04
  penv create myenv ubuntu-24.04
  penv shell myenv
  penv delete myenv

${C_BOLD}ALIASES:${C_RESET}
  ${C_DIM}enter → shell, available → download -l, list-envs → list${C_RESET}
USAGE
}

distro_resolve(){
  local key="$1"
  if [[ -z "$key" ]]; then
    echo ""
    return
  fi
  if [[ "$key" =~ ^https?:// ]]; then
    echo "$key"; return
  fi
  if [[ -n "${DISTROS[$key]:-}" ]]; then
    echo "${DISTROS[$key]}"; return
  fi
  # treat as local path
  if [[ -f "$key" ]]; then
    echo "file://$(realpath "$key")"; return
  fi
  echo ""
}

cached_tarball_for(){
  local url="$1"
  if [[ -z "$url" ]]; then echo ""; return; fi
  if [[ "$url" =~ ^file:// ]]; then
    local p="${url#file://}"
    echo "$CACHE_DIR/$(basename "$p")"
    return
  fi
  # use basename of URL (strip query)
  local fname
  fname="$(basename "${url%%\?*}")"
  echo "$CACHE_DIR/$fname"
}

download_url(){
  local url="$1"; local out="$2"
  mkdir -p "$(dirname "$out")"
  if [[ -f "$out" ]]; then
    msg "Using cached: $(basename "$out")"
    return 0
  fi
  info "Downloading: $(basename "$out")"
  printf "${C_DIM}Source: %s${C_RESET}\n" "$url"
  if [[ "$url" =~ ^file:// ]]; then
    cp -n "${url#file://}" "$out"
    msg "File copied successfully"
    return 0
  fi
  case "$DL_TOOL" in
    aria2c)
      aria2c -x16 -s16 -c --console-log-level=warn --summary-interval=0 -o "$out" "$url"
      ;;
    curl)
      curl -L --fail --retry 5 --retry-delay 2 --continue-at - --progress-bar -o "$out" "$url"
      ;;
    wget)
      wget -c --progress=bar:force -O "$out" "$url"
      ;;
    *)
      err "No download tool found. Install aria2c, curl or wget."
      return 2
      ;;
  esac
  echo
  msg "Download complete: $(basename "$out")"
}

extract_tarball_to(){
  local tarball="$1" target="$2"
  mkdir -p "$target"
  if [[ "$tarball" =~ ^file:// ]]; then
    tarball="${tarball#file://}"
  fi
  if [[ ! -f "$tarball" ]]; then
    err "Tarball not found: $tarball"; return 2
  fi
  info "Extracting $(basename "$tarball")..."
  # preserve numeric owners (if tarball contains them)
  tar -xpf "$tarball" -C "$target"
  msg "Extraction complete"
}

list_envs(){
  header "${ICON_PACKAGE} Available Environments"
  if [[ -d "$ENVS_DIR" ]] && [[ -n "$(ls -A "$ENVS_DIR" 2>/dev/null)" ]]; then
    for env in "$ENVS_DIR"/*; do
      local name size
      name=$(basename "$env")
      size=$(du -sh "$env" 2>/dev/null | cut -f1)
      printf "  ${C_GREEN}●${C_RESET} ${C_BOLD}%-20s${C_RESET} ${C_DIM}(%s)${C_RESET}\n" "$name" "$size"
    done
  else
    printf "  ${C_DIM}No environments created yet.${C_RESET}\n"
    printf "  ${C_DIM}Use: penv create <name> <distro-id>${C_RESET}\n"
  fi
  echo
}

list_cached(){
  header "${ICON_DOWNLOAD} Cached Downloads"
  if [[ -d "$CACHE_DIR" ]] && [[ -n "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]]; then
    for cache in "$CACHE_DIR"/*; do
      local name size
      name=$(basename "$cache")
      size=$(du -sh "$cache" 2>/dev/null | cut -f1)
      printf "  ${C_CYAN}▸${C_RESET} ${C_BOLD}%-40s${C_RESET} ${C_DIM}(%s)${C_RESET}\n" "$name" "$size"
    done
  else
    printf "  ${C_DIM}No cached downloads.${C_RESET}\n"
  fi
  echo
}

# -------- commands --------
cmd_init(){
  ensure_dirs
  header "${ICON_PACKAGE} penv initialized successfully!"
  printf "  ${C_CYAN}Cache:${C_RESET}      %s\n" "$CACHE_DIR"
  printf "  ${C_CYAN}Envs:${C_RESET}       %s\n" "$ENVS_DIR"
  echo
  if [[ -z "$DL_TOOL" ]]; then
    warn "No download tool found. Install one of:"
    printf "    ${C_DIM}• aria2c (recommended)${C_RESET}\n"
    printf "    ${C_DIM}• curl${C_RESET}\n"
    printf "    ${C_DIM}• wget${C_RESET}\n"
  else
    msg "Downloader: $DL_TOOL"
  fi
  if ! command -v proot >/dev/null 2>&1; then
    warn "proot not found. Install it:"
    printf "    ${C_DIM}sudo apt update && sudo apt install -y proot${C_RESET}\n"
  else
    msg "proot: $(command -v proot)"
  fi
  echo
}

cmd_available(){
  header "${ICON_DOWNLOAD} Available Distributions"
  printf "  ${C_BOLD}${C_CYAN}%-20s${C_RESET}  ${C_BOLD}${C_DIM}%s${C_RESET}\n" "ID" "SOURCE URL"
  printf "  ${C_DIM}%s${C_RESET}\n" "$(printf '%.0s─' {1..80})"
  for k in "${!DISTROS[@]}"; do
    printf "  ${C_GREEN}%-20s${C_RESET}  ${C_DIM}%s${C_RESET}\n" "$k" "${DISTROS[$k]}"
  done | sort
  echo
  info "Use: ${C_BOLD}penv download <id>${C_RESET} to download a distro"
  echo
}

cmd_download(){
  ensure_dirs
  # Handle -l flag to list available distros
  if [[ $# -eq 1 ]] && [[ "$1" == "-l" || "$1" == "--list" ]]; then
    cmd_available
    return 0
  fi
  if [[ $# -lt 1 ]]; then
    err "Usage: penv download <distro-id>"
    printf "       penv download -l  ${C_DIM}(list available distros)${C_RESET}\n"
    exit 2
  fi
  local key="$1"
  local url
  url="$(distro_resolve "$key")"
  if [[ -z "$url" ]]; then
    err "Unknown distro: $key"
    info "Use ${C_BOLD}penv download -l${C_RESET} to see available distros"
    exit 2
  fi
  local tar
  tar="$(cached_tarball_for "$url")"
  download_url "$url" "$tar"
}

cmd_create(){
  ensure_dirs
  # Handle -l flag to list available distros
  if [[ $# -eq 1 ]] && [[ "$1" == "-l" || "$1" == "--list" ]]; then
    cmd_available
    return 0
  fi
  # Support both old syntax (name -d distro) and new syntax (name distro)
  local name="" distro_key=""
  if [[ $# -lt 2 ]]; then
    err "Usage: penv create <name> <distro-id>"
    printf "       penv create -l  ${C_DIM}(list available distros)${C_RESET}\n"
    exit 2
  fi
  
  name="$1"; shift
  
  # Check if old syntax with -d flag
  if [[ "$1" == "-d" || "$1" == "--distro" ]]; then
    if [[ $# -lt 2 ]]; then
      err "Option -d requires a distro ID"
      exit 2
    fi
    distro_key="$2"
  else
    # New simple syntax: name distro
    distro_key="$1"
  fi
  
  local url
  url="$(distro_resolve "$distro_key")"
  if [[ -z "$url" ]]; then
    err "Unknown distro: $distro_key"
    info "Use ${C_BOLD}penv create -l${C_RESET} to see available distros"
    exit 2
  fi
  
  local tar
  tar="$(cached_tarball_for "$url")"
  if [[ ! -f "$tar" ]]; then
    info "Distro not cached, downloading first..."
    download_url "$url" "$tar"
  fi
  
  local root="$ENVS_DIR/$name"
  if [[ -d "$root" ]]; then
    err "Environment already exists: $name"
    exit 2
  fi
  
  header "${ICON_PACKAGE} Creating environment: $name"
  mkdir -p "$root"
  extract_tarball_to "$tar" "$root"
  
  # copy host resolv.conf for working DNS (follow symlink)
  if [[ -f /etc/resolv.conf ]]; then
    mkdir -p "$root/etc"
    cp -L /etc/resolv.conf "$root/etc/resolv.conf" || true
  fi
  
  echo
  msg "Environment created: ${C_BOLD}$name${C_RESET}"
  info "Enter with: ${C_BOLD}penv shell $name${C_RESET}"
  echo
}

cmd_shell(){
  if (( $# < 1 )); then
    err "Usage: penv shell <name>"
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi

  local name="$1"; shift
  local root="$ENVS_DIR/$name"

  if [[ ! -d "$root" ]]; then
    err "Environment not found: $name"
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi

  require_proot
  header "${ICON_SHELL} Entering environment: $name"
  printf "  ${C_DIM}Rootfs: %s${C_RESET}\n" "$root"
  echo

  # Build command as an array so arguments are preserved correctly
  local -a cmd
  if (( $# == 0 )); then
    cmd=(/bin/bash --login)
  else
    cmd=( "$@" )
  fi

  proot -0 -r "$root" \
    -b /dev -b /proc -b /sys \
    -w / \
    "${cmd[@]}"
}

cmd_delete(){
  if (( $# < 1 )); then
    err "Usage: penv delete <name>"
    exit 2
  fi
  local name="$1"
  local root="$ENVS_DIR/$name"
  if [[ ! -d "$root" ]]; then
    err "Environment not found: $name"
    exit 2
  fi
  local size
  size=$(du -sh "$root" 2>/dev/null | cut -f1)
  warn "About to delete environment: ${C_BOLD}$name${C_RESET} (${size})"
  printf "  ${C_DIM}Location: %s${C_RESET}\n" "$root"
  read -p "$(printf "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
  case "$yn" in
    [Yy])
      rm -rf "$root"
      msg "Deleted: $name"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}

cmd_list(){ list_envs; }
cmd_cache(){ list_cached; }

cmd_clean(){
  if [[ $# -lt 1 ]]; then
    err "Usage: penv clean <distro-id>"
    printf "       penv clean --all  ${C_DIM}(remove all cached downloads)${C_RESET}\n"
    exit 2
  fi
  
  # Handle --all flag
  if [[ "$1" == "--all" ]]; then
    if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]]; then
      info "Cache is already empty"
      return 0
    fi
    local total_size
    total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    warn "About to delete all cached downloads (${total_size})"
    read -p "$(printf "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
    case "$yn" in
      [Yy])
        rm -rf "${CACHE_DIR:?}/"*
        msg "Cache cleared"
        ;;
      *)
        info "Aborted"
        ;;
    esac
    return 0
  fi
  
  # Remove specific distro
  local key="$1"
  local url
  url="$(distro_resolve "$key")"
  if [[ -z "$url" ]]; then
    err "Unknown distro: $key"
    exit 2
  fi
  local tar
  tar="$(cached_tarball_for "$url")"
  if [[ -f "$tar" ]]; then
    local size
    size=$(du -sh "$tar" 2>/dev/null | cut -f1)
    rm -f "$tar"
    msg "Removed cached download: $(basename "$tar") (${size})"
  else
    err "No cached download found for: $key"
  fi
}

# -------- dispatch --------
if (( $# < 1 )); then usage; exit 0; fi
cmd="$1"; shift

case "$cmd" in
  init) cmd_init ;;
  # List available distros
  available|avail) cmd_available ;;
  # Download distro
  download|dl) cmd_download "$@" ;;
  # Create environment
  create|new) cmd_create "$@" ;;
  # Enter environment (shell)
  shell|enter|sh) cmd_shell "$@" ;;
  # Delete environment
  delete|remove|rm) cmd_delete "$@" ;;
  # List environments
  list|ls|list-envs) cmd_list ;;
  # Show cached downloads
  cache|list-downloads) cmd_cache ;;
  # Clean cached downloads
  clean|remove-distro) cmd_clean "$@" ;;
  # Help
  help|--help|-h) usage ;;
  *) err "Unknown command: $cmd"; usage; exit 2 ;;
esac
