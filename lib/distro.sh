#!/usr/bin/env bash
# distro.sh - Distro download and management

# Namespace: distro::

# Download a distro
distro::download(){
  local distro_id="$1"
  local custom_name="$2"
  shift 2
  local addons=("$@")
  
  ensure_dirs
  
  # Get distro info
  local distro_data
  distro_data=$(index::get_distro "$distro_id")
  
  if [[ -z "$distro_data" ]]; then
    err "Distro not found: $distro_id"
    info "Use ${C_BOLD}penv list -o${C_RESET} to see available distros"
    return 1
  fi
  
  # Get the actual distro ID (in case user provided an alias)
  local actual_distro_id
  actual_distro_id=$(echo "$distro_data" | jq -r '.id')
  
  # If addons requested, custom name is required
  if [[ ${#addons[@]} -gt 0 ]] && [[ -z "$custom_name" ]]; then
    err "Custom name (-n) is required when using addons"
    info "Usage: penv download $distro_id -n <custom-name> -a <addon>"
    return 1
  fi
  
  # Get URL for current architecture
  local url
  url=$(index::get_url_for_arch "$distro_data" "$ARCH")
  
  if [[ -z "$url" ]]; then
    return 1
  fi
  
  # Determine final distro ID
  local final_id="$distro_id"
  if [[ -n "$custom_name" ]]; then
    final_id="$custom_name"
    index::init_local
    # Check if custom name already exists in distros or custom
    local exists_in_distros exists_in_custom
    exists_in_distros=$(jq -r ".distros[\"$final_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
    exists_in_custom=$(jq -r ".custom[\"$final_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
    if [[ -n "$exists_in_distros" ]] || [[ -n "$exists_in_custom" ]]; then
      err "Custom name already exists: $final_id"
      return 1
    fi
  fi
  
  # Download to cache
  local cache_file="$CACHE_DIR/${final_id}.tar.gz"
  
  download_file "$url" "$cache_file" || return 1
  
  # If addons requested, apply them
  if [[ ${#addons[@]} -gt 0 ]]; then
    info "Applying ${#addons[@]} addon(s)..."
    cache_file=$(distro::apply_addons "$cache_file" "$final_id" "$actual_distro_id" "${addons[@]}") || return 1
  fi
  
  # Store in local index
  index::store_downloaded "$final_id" "$cache_file"
  
  # If custom name, also create link
  if [[ -n "$custom_name" ]]; then
    local distro_name
    distro_name=$(echo "$distro_data" | jq -r '.name')
    local addon_list=""
    if [[ ${#addons[@]} -gt 0 ]]; then
      addon_list=" with addons: ${addons[*]}"
    fi
    index::add_custom "$custom_name" "$actual_distro_id" "$distro_name$addon_list"
  fi
  
  msg "Distro downloaded: ${C_BOLD}$final_id${C_RESET}"
  info "File: $cache_file"
}

# Apply addons to a distro
distro::apply_addons(){
  local tarball="$1"
  local final_id="$2"
  local distro_id="$3"
  shift 3
  local addons=("$@")
  
  require_proot
  require_jq
  
  local temp_root
  temp_root=$(mktemp -d)
  
  # Extract original
  info "Extracting base distro..."
  extract_tarball "$tarball" "$temp_root" || {
    rm -rf "$temp_root"
    err "Failed to extract base distro"
    return 1
  }
  
  # Setup proot environment
  setup_proot_env "$temp_root"
  
  # Apply each addon
  for addon_id in "${addons[@]}"; do
    info "Processing addon: $addon_id"
    
    # Get addon info
    local addon_data
    addon_data=$(index::get_addon "$addon_id")
    
    if [[ -z "$addon_data" ]]; then
      warn "Addon not found: $addon_id (skipping)"
      continue
    fi
    
    # Check distro compatibility
    if ! index::addon_compatible "$addon_data" "$distro_id"; then
      local addon_name
      addon_name=$(echo "$addon_data" | jq -r '.name')
      warn "Addon '$addon_name' is not compatible with distro '$distro_id' (skipping)"
      continue
    fi
    
    # Get addon script URL for current architecture
    local addon_url
    addon_url=$(index::get_url_for_arch "$addon_data" "$ARCH")
    
    if [[ -z "$addon_url" ]]; then
      warn "No URL for addon $addon_id on architecture $ARCH (skipping)"
      continue
    fi
    
    # Download addon script
    local addon_script="$temp_root/tmp/addon_${addon_id}.sh"
    mkdir -p "$temp_root/tmp"
    download_file "$addon_url" "$addon_script" || {
      warn "Failed to download addon: $addon_id (skipping)"
      continue
    }
    
    chmod +x "$addon_script"
    
    # Run addon in proot
    info "Running addon script: $addon_id"
    if ! exec_in_proot "$temp_root" /tmp/"addon_${addon_id}.sh"; then
      warn "Addon script failed: $addon_id (continuing anyway)"
    else
      msg "Addon applied: $addon_id"
    fi
    
    # Cleanup addon script
    rm -f "$addon_script"
  done
  
  # Compress modified rootfs
  local output_file="$CACHE_DIR/${final_id}.tar.gz"
  
  # Remove old tarball first
  rm -f "$tarball"
  
  compress_tarball "$temp_root" "$output_file" || {
    rm -rf "$temp_root"
    err "Failed to compress modified distro"
    return 1
  }
  
  # Cleanup
  rm -rf "$temp_root"
  
  echo "$output_file"
}

# List downloaded distros
distro::list_downloaded(){
  require_jq
  index::init_local
  
  header "Downloaded Distributions"
  
  local count
  count=$(jq -r '.distros | length' "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ "$count" -eq 0 ]]; then
    echo -e "  ${C_DIM}No distributions downloaded yet${C_RESET}"
    echo -e "  ${C_DIM}Use: penv download <distro-id>${C_RESET}"
    echo
    return
  fi
  
  jq -r '.distros | to_entries[] | "\(.key)|\(.value.file)|\(.value.downloaded)"' "$LOCAL_INDEX" 2>/dev/null | \
  while IFS='|' read -r id file date; do
    if [[ -f "$file" ]]; then
      local size
      size=$(du -sh "$file" 2>/dev/null | cut -f1)
      printf "  ${C_GREEN}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (%s)${C_RESET}\n" "$id" "$size" "$(basename "$file")"
    else
      printf "  ${C_RED}!${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}(file missing)${C_RESET}\n" "$id"
    fi
  done
  
  echo
}

# Clean downloaded distro
distro::clean(){
  local distro_id="$1"
  require_jq
  
  index::init_local
  
  local file_path
  file_path=$(index::get_local_path "$distro_id")
  
  if [[ -z "$file_path" ]]; then
    err "Distro not found in local index: $distro_id"
    return 1
  fi
  
  if [[ -f "$file_path" ]]; then
    local size
    size=$(du -sh "$file_path" 2>/dev/null | cut -f1)
    rm -f "$file_path"
    msg "Removed: $distro_id ($size)"
  else
    warn "File already missing: $file_path"
  fi
  
  # Remove from local index
  local tmp_file
  tmp_file=$(mktemp)
  jq --arg id "$distro_id" 'del(.distros[$id])' "$LOCAL_INDEX" > "$tmp_file" && \
    mv "$tmp_file" "$LOCAL_INDEX"
}

# Clean all downloads
distro::clean_all(){
  require_jq
  index::init_local
  
  local count
  count=$(jq -r '.distros | length' "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ "$count" -eq 0 ]]; then
    info "No downloads to clean"
    return 0
  fi
  
  local total_size
  total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
  
  warn "About to delete all cached downloads (${total_size})"
  read -p "$(echo -e "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
  
  case "$yn" in
    [Yy])
      rm -rf "${CACHE_DIR:?}/"*
      echo '{"distros":{},"custom":{}}' > "$LOCAL_INDEX"
      msg "Cache cleared"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}
