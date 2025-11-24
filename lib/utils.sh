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
  
  # Check proot version and warn if too old
  local version_output
  version_output=$(proot --version 2>&1)
  
  # Extract version number (format: v5.4.0 or 5.1.0)
  local version
  version=$(echo "$version_output" | grep -oP 'v?\d+\.\d+\.\d+' | head -1 | sed 's/^v//')
  
  if [[ -n "$version" ]]; then
    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"
    
    # Check if version < 5.4.0
    if [[ "$major" -lt 5 ]] || [[ "$major" -eq 5 && "$minor" -lt 4 ]]; then
      warn "proot ${version} detected - this version has a critical bug!"
      warn "Relative paths fail after 'cd' in glibc distributions (Debian/Ubuntu)"
      warn "Upgrade to proot v5.4.0+ for full functionality"
      echo ""
    fi
  fi
}

require_jq(){
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for index operations. Install it: sudo apt update && sudo apt install -y jq"
    exit 1
  fi
}

# Verify file checksum
verify_checksum(){
  local file="$1"
  local expected_sha256="$2"
  
  if [[ -z "$expected_sha256" || "$expected_sha256" == "null" ]]; then
    # No checksum provided, skip verification
    return 0
  fi
  
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "sha256sum not found, skipping checksum verification"
    return 0
  fi
  
  info "Verifying checksum..."
  local actual_sha256
  actual_sha256=$(sha256sum "$file" | cut -d' ' -f1)
  
  if [[ "$actual_sha256" == "$expected_sha256" ]]; then
    msg "Checksum verified"
    return 0
  else
    err "Checksum mismatch!"
    err "  Expected: $expected_sha256"
    err "  Got:      $actual_sha256"
    return 1
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
  
  # Check for download tool early (skip for file:// URLs)
  if [[ ! "$url" =~ ^file:// ]] && [[ -z "$DL_TOOL" ]]; then
    err "No download tool found. Install aria2c, curl or wget."
    return 2
  fi
  
  info "Downloading: $(basename "$out")"
  echo -e "${C_DIM}Source: $url${C_RESET}"
  
  if [[ "$url" =~ ^file:// ]]; then
    local file_path="${url#file://}"
    if [[ ! -f "$file_path" ]]; then
      err "Source file not found: $file_path"
      return 1
    fi
    if ! cp "$file_path" "$out"; then
      err "Failed to copy file: $file_path"
      return 1
    fi
    msg "File copied successfully"
    return 0
  fi
  
  local download_status=0
  case "$DL_TOOL" in
    aria2c)
      aria2c -x16 -s16 -c --console-log-level=warn --summary-interval=0 -o "$out" "$url" || download_status=$?
      ;;
    curl)
      curl -L --fail --retry 5 --retry-delay 2 --continue-at - --progress-bar -o "$out" "$url" || download_status=$?
      ;;
    wget)
      wget -c --progress=bar:force -O "$out" "$url" || download_status=$?
      ;;
  esac
  
  if [[ $download_status -ne 0 ]]; then
    err "Download failed with exit code: $download_status"
    # Clean up partial download
    [[ -f "$out" ]] && rm -f "$out"
    return 1
  fi
  
  # Verify file was actually downloaded
  if [[ ! -f "$out" ]]; then
    err "Download completed but file not found: $(basename "$out")"
    return 1
  fi
  
  # Verify file has content
  if [[ ! -s "$out" ]]; then
    err "Downloaded file is empty: $(basename "$out")"
    rm -f "$out"
    return 1
  fi
  
  echo
  msg "Download complete: $(basename "$out")"
  return 0
}

# Download a file without cache check (for temporary files)
download_file_nocache(){
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  
  # Check for download tool early (skip for file:// URLs)
  if [[ ! "$url" =~ ^file:// ]] && [[ -z "$DL_TOOL" ]]; then
    err "No download tool found. Install aria2c, curl or wget."
    return 2
  fi
  
  if [[ "$url" =~ ^file:// ]]; then
    local file_path="${url#file://}"
    if [[ ! -f "$file_path" ]]; then
      err "Source file not found: $file_path"
      return 1
    fi
    if ! cp "$file_path" "$out"; then
      err "Failed to copy file: $file_path"
      return 1
    fi
    return 0
  fi
  
  local download_status=0
  case "$DL_TOOL" in
    aria2c)
      aria2c -x16 -s16 --console-log-level=error --summary-interval=0 -o "$out" "$url" 2>&1 | grep -v "^$" || download_status=$?
      ;;
    curl)
      curl -fsSL -o "$out" "$url" || download_status=$?
      ;;
    wget)
      wget -q -O "$out" "$url" || download_status=$?
      ;;
  esac
  
  if [[ $download_status -ne 0 ]]; then
    err "Download failed"
    [[ -f "$out" ]] && rm -f "$out"
    return 1
  fi
  
  # Verify file was downloaded and has content
  if [[ ! -f "$out" ]] || [[ ! -s "$out" ]]; then
    err "Download failed or file is empty"
    rm -f "$out"
    return 1
  fi
  
  return 0
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
    return 1
  fi
  
  # Verify tarball is valid
  if [[ ! -s "$tarball" ]]; then
    err "Tarball is empty: $tarball"
    return 1
  fi
  
  info "Extracting $(basename "$tarball")..."
  
  # Use pipefail to catch extraction errors
  local extract_status=0
  { tar -xpf "$tarball" -C "$target" 2>&1 || extract_status=$?; } | grep -v "Ignoring unknown extended header" || true
  
  if [[ $extract_status -ne 0 ]]; then
    err "Extraction failed with exit code: $extract_status"
    return 1
  fi
  
  # Verify extraction created files
  if [[ ! "$(ls -A "$target" 2>/dev/null)" ]]; then
    err "Extraction completed but target directory is empty"
    return 1
  fi
  
  msg "Extraction complete"
}

# Setup environment for proot (resolv.conf, etc)
setup_proot_env(){
  local rootfs="$1"
  
  # Ensure essential directories exist (device files removed at build time)
  mkdir -p "$rootfs/dev" "$rootfs/proc" "$rootfs/sys" 2>/dev/null || true
  
  # Copy resolv.conf for DNS
  if [[ -f /etc/resolv.conf ]]; then
    mkdir -p "$rootfs/etc"
    cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true
  fi
  
  # Copy host users and groups to prevent ID resolving issues
  # This ensures UIDs/GIDs match between host and environment
  if [[ -f /etc/passwd ]]; then
    cp -L /etc/passwd "$rootfs/etc/passwd" 2>/dev/null || true
  fi
  if [[ -f /etc/group ]]; then
    cp -L /etc/group "$rootfs/etc/group" 2>/dev/null || true
  fi
  
  # Fix directory permissions for proot -0 compatibility
  # When tarballs created by root are extracted by non-root users,
  # proot with fake root (-0) fails to access directories
  # This ensures all directories are world-readable and executable
  info "Fixing permissions..."
  find "$rootfs" -type d -exec chmod a+rx {} \; 2>/dev/null || true
  
  return 0
}

# Execute command in proot environment
exec_in_proot(){
  local rootfs="$1"
  shift
  local cmd=("$@")
  
  require_proot
  
  if [[ ! -d "$rootfs" ]]; then
    err "Root filesystem not found: $rootfs"
    return 1
  fi
  
  # Change to rootfs directory to fix proot working directory issues
  # When proot is launched from outside the rootfs with -r <path>,
  # the current directory (.) gets confused. Using -r . from inside
  # the rootfs directory fixes this.
  cd "$rootfs" || return 1
  
  proot -0 -r . \
    -b /dev -b /proc -b /sys \
    -w / \
    "${cmd[@]}"
}

# Compress directory to tarball
compress_tarball(){
  local source="$1" output="$2"
  
  if [[ ! -d "$source" ]]; then
    err "Source directory not found: $source"
    return 1
  fi
  
  # Verify source directory is not empty
  if [[ ! "$(ls -A "$source" 2>/dev/null)" ]]; then
    err "Source directory is empty: $source"
    return 1
  fi
  
  info "Compressing $(basename "$source")..."
  
  local compress_status=0
  tar -cpzf "$output" -C "$source" . || compress_status=$?
  
  if [[ $compress_status -ne 0 ]]; then
    err "Compression failed with exit code: $compress_status"
    # Clean up partial output
    [[ -f "$output" ]] && rm -f "$output"
    return 1
  fi
  
  # Verify output file was created and has content
  if [[ ! -f "$output" ]]; then
    err "Compression completed but output file not found"
    return 1
  fi
  
  if [[ ! -s "$output" ]]; then
    err "Compressed file is empty"
    rm -f "$output"
    return 1
  fi
  
  msg "Compression complete: $(basename "$output")"
}
