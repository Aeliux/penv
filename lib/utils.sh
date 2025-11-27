#!/usr/bin/env bash
# utils.sh - Utility functions

# -------- helpers --------
msg(){ echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
info(){ echo -e "${C_CYAN}[i]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err(){ echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
header(){ echo -e "${C_BOLD}${C_CYAN}$*${C_RESET}"; }

ensure_dirs(){
  mkdir -p "$CACHE_DIR" "$ENVS_DIR" "$BIN_DIR" "$PENV_DIR"
}

require_proot(){
  # Skip proot check if running as root (will use chroot instead)
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi
  
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

  info "Setting up environment..."

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

  # Run any version-specific proot setup here if needed
  if requires_version "$rootfs" "2" && [[ "$PENV_ENV_MODE" = "prepare" ]]; then
    info "Preparing penv v2+ environment..."
    exec_in_proot "$rootfs"
  fi

  msg "Environment setup complete"
  
  return 0
}

requires_version() {
    local penv_version=$(get_penv_version "$1")
    local required_version="$2"

    local cmp_result=0
    compare_versions "$penv_version" "$required_version" || cmp_result=$?
    if [[ $cmp_result -eq 1 || $cmp_result -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

get_penv_version() {
    local rootfs="$1"
    local version_file="$rootfs/penv/metadata/version"

    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        echo "0"
    fi
}

compare_versions() {
    local ver1=(${1//./ })
    local ver2=(${2//./ })
    local len=$(( ${#ver1[@]} > ${#ver2[@]} ? ${#ver1[@]} : ${#ver2[@]} ))

    for ((i=0; i<len; i++)); do
        local v1="${ver1[i]:-0}"
        local v2="${ver2[i]:-0}"

        # Remove any spaces (defensive)
        v1="${v1//[[:space:]]/}"
        v2="${v2//[[:space:]]/}"

        # If not a number, default to 0
        [[ "$v1" =~ ^[0-9]+$ ]] || v1=0
        [[ "$v2" =~ ^[0-9]+$ ]] || v2=0

        if ((10#$v1 > 10#$v2)); then
            return 1
        elif ((10#$v1 < 10#$v2)); then
            return 2
        fi
    done

    return 0
}

# Find available shell in rootfs
find_shell(){
  local rootfs="$1"
  
  # Try shells in order of preference
  for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    # Check if file or symlink exists
    if [[ -e "$rootfs$shell" ]] || [[ -L "$rootfs$shell" ]]; then
      echo "$shell"
      return 0
    fi
  done
  
  return 1
}

# Launch interactive shell in rootfs
launch_shell(){
  local rootfs="$1"
  
  info "Launching shell..."
  info "Type 'exit' when done to return and continue..."
  echo
  
  exec_in_proot "$rootfs"
}

# Execute command in proot environment (or chroot if running as root)
exec_in_proot(){
  local rootfs="$1"
  shift
  local cmd=("$@")
  
  if [[ ! -d "$rootfs" ]]; then
    err "Root filesystem not found: $rootfs"
    return 1
  fi

  local compare_result=0
  compare_versions "$CLIENT_VERSION" "$(get_penv_version "$rootfs")" || compare_result=$?
  if [[ $compare_result -eq 2 ]]; then
      warn "Warning: penv client version ($CLIENT_VERSION) is older than environment version ($(get_penv_version "$rootfs"))"
      warn "Some features may not work as expected. Consider updating penv."
      echo
  fi
  
  if [[ -f "$rootfs/penv/startup.sh" ]]; then
      startup=(/bin/sh -- /penv/startup.sh)
  fi

  # If no command provided, detect best default
  if [[ ${#cmd[@]} -eq 0 ]]; then
    # Priority 1: Use startup script if available
    if [[ -n "${startup[*]}" ]]; then
      cmd=("${startup[@]}")
    else
      # Priority 2: Find available shell
      local shell_path
      shell_path=$(find_shell "$rootfs")
      if [[ -n "$shell_path" ]]; then
        cmd=("$shell_path" -l)
      else
        err "No shell found in rootfs"
        return 1
      fi
    fi
  elif [[ -n "${startup[*]}" ]]; then
      if requires_version "$rootfs" "2"; then
          # Prepend startup script for penv v2+
          cmd=("${startup[@]}" "${cmd[@]}")
      fi
  fi
  
  # Check if running as root (UID 0)
  if [[ $EUID -eq 0 ]]; then
    # Mount necessary pseudo-filesystems
    mount --bind /dev "$rootfs/dev" || true
    mount --bind /dev/pts "$rootfs/dev/pts" || true
    mount --bind /dev/shm "$rootfs/dev/shm" || true
    mount -t proc proc "$rootfs/proc" || true
    mount -t sysfs sys "$rootfs/sys" || true
    
    if [[ "$PENV_CONFIG_MNT_HOME" -eq 1 ]]; then
      mount --bind "$HOME" "$rootfs/mnt" || true
    fi
    
    export PENV_ENV_PARENT="chroot"
    # Execute in chroot
    chroot "$rootfs" "${cmd[@]}"
    local exit_code=$?
    
    # Cleanup mounts
    umount -l "$rootfs/dev/pts" || true
    umount -l "$rootfs/dev/shm" || true
    umount -l "$rootfs/dev" || true
    umount -l "$rootfs/proc" || true
    umount -l "$rootfs/sys" || true
    umount -l "$rootfs/mnt" 2>/dev/null || true
    
    return $exit_code
  else
    # Use proot for non-root users
    require_proot
    
    local proot_args=(
      -0                        # Fake root user
      -r .                      # Rootfs path
      -b /dev -b /proc -b /sys  # Bind mount pseudo-filesystems
      -w /                      # Set working directory to /
    )
    if [[ "$PENV_CONFIG_MNT_HOME" -eq 1 ]]; then
      proot_args+=(-b "$HOME":"/mnt")
    fi

    # Change to rootfs directory to fix proot working directory issues
    # When proot is launched from outside the rootfs with -r <path>,
    # the current directory (.) gets confused. Using -r . from inside
    # the rootfs directory fixes this.
    pushd "$rootfs" >/dev/null || return 1
    
    proot "${proot_args[@]}" "${cmd[@]}"
    
    popd >/dev/null || return 1
  fi
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
