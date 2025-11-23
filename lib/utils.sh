#!/usr/bin/env bash
# utils.sh - Utility functions

# -------- helpers --------
msg(){ echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
info(){ echo -e "${C_CYAN}[i]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
header(){ echo -e "\n${C_BOLD}${C_CYAN}=== $* ===${C_RESET}"; }

ensure_dirs(){
  mkdir -p "$CACHE_DIR" "$ENVS_DIR" "$BIN_DIR" "$PENV_DIR"
}

require_proot(){
  if ! command -v proot >/dev/null 2>&1; then
    err "proot is required. Install it: sudo apt update && sudo apt install -y proot"
    exit 1
  fi
}

require_jq(){
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for index operations. Install it: sudo apt update && sudo apt install -y jq"
    exit 1
  fi
}

# Download a file with progress
download_file(){
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  
  if [[ -f "$out" ]]; then
    msg "Using cached: $(basename "$out")"
    return 0
  fi
  
  info "Downloading: $(basename "$out")"
  echo -e "${C_DIM}Source: $url${C_RESET}"
  
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

# Extract tarball preserving permissions
extract_tarball(){
  local tarball="$1" target="$2"
  mkdir -p "$target"
  
  if [[ "$tarball" =~ ^file:// ]]; then
    tarball="${tarball#file://}"
  fi
  
  if [[ ! -f "$tarball" ]]; then
    err "Tarball not found: $tarball"
    return 2
  fi
  
  info "Extracting $(basename "$tarball")..."
  tar -xpf "$tarball" -C "$target" 2>&1 | grep -v "Ignoring unknown extended header" || true
  msg "Extraction complete"
}

# Setup environment for proot (resolv.conf, etc)
setup_proot_env(){
  local rootfs="$1"
  
  # Copy resolv.conf for DNS
  if [[ -f /etc/resolv.conf ]]; then
    mkdir -p "$rootfs/etc"
    cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true
  fi
}

# Execute command in proot environment
exec_in_proot(){
  local rootfs="$1"
  shift
  local cmd=("$@")
  
  require_proot
  
  proot -0 -r "$rootfs" \
    -b /dev -b /proc -b /sys \
    -w / \
    "${cmd[@]}"
}

# Compress directory to tarball
compress_tarball(){
  local source="$1" output="$2"
  
  if [[ ! -d "$source" ]]; then
    err "Source directory not found: $source"
    return 2
  fi
  
  info "Compressing $(basename "$source")..."
  tar -cpzf "$output" -C "$source" .
  msg "Compression complete: $(basename "$output")"
}
