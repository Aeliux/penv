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
  require_jq
  
  # Get distro info from remote index
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
  
  # Determine final distro ID
  local final_id="$distro_id"
  local is_custom=false
  
  if [[ -n "$custom_name" ]]; then
    # Validate custom name
    if ! index::validate_name "$custom_name"; then
      return 1
    fi
    
    final_id="$custom_name"
    is_custom=true
    
    # Check if name already exists
    index::init_local
    local exists
    exists=$(jq -r ".distros[\"$final_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
    if [[ -n "$exists" ]]; then
      err "Name already exists: $final_id"
      info "Use a different name or clean existing: ${C_BOLD}penv clean $final_id${C_RESET}"
      return 1
    fi
  fi
  
  # If addons requested, custom name is required
  if [[ ${#addons[@]} -gt 0 ]] && [[ "$is_custom" == "false" ]]; then
    err "Custom name (-n) is required when using addons"
    info "Usage: penv download $distro_id -n <custom-name> -a <addon>"
    return 1
  fi
  
  # Check if base distro already downloaded (for reuse)
  local base_distro_file=""
  if [[ "$is_custom" == "true" ]]; then
    base_distro_file=$(index::get_local_path "$actual_distro_id")
    
    if [[ -n "$base_distro_file" ]] && [[ -f "$base_distro_file" ]]; then
      msg "Reusing existing base distro: $actual_distro_id"
    else
      base_distro_file=""
      if [[ ${#addons[@]} -gt 0 ]]; then
        info "Base distro not found locally, downloading: $actual_distro_id"
      fi
    fi
  fi
  
  # Download base distro if needed
  local cache_file
  if [[ -n "$base_distro_file" ]]; then
    # Reuse existing download
    cache_file="$base_distro_file"
  else
    # Get URL for current architecture
    local url
    url=$(index::get_url_for_arch "$distro_data" "$ARCH")
    
    if [[ -z "$url" ]]; then
      return 1
    fi
    
    # Download to cache (use actual_distro_id for base downloads, final_id for simple downloads)
    if [[ "$is_custom" == "true" ]] && [[ ${#addons[@]} -gt 0 ]]; then
      cache_file="$CACHE_DIR/${actual_distro_id}.tar.gz"
    else
      cache_file="$CACHE_DIR/${final_id}.tar.gz"
    fi
    
    download_file "$url" "$cache_file" || return 1
    
    # Store base distro in index if it was the actual distro ID
    if [[ "$is_custom" == "true" ]] && [[ ${#addons[@]} -gt 0 ]]; then
      index::store_downloaded "$actual_distro_id" "$cache_file"
    fi
  fi
  
  # If addons requested, apply them to create custom distro
  if [[ ${#addons[@]} -gt 0 ]]; then
    info "Applying ${#addons[@]} addon(s)..."
    
    # Build JSON array for addons
    local addons_json
    addons_json=$(printf '%s\n' "${addons[@]}" | jq -R . | jq -s .)
    
    local custom_cache_file
    custom_cache_file=$(distro::apply_addons "$cache_file" "$final_id" "$actual_distro_id" "${addons[@]}") || return 1
    
    # Store custom distro with metadata
    index::store_downloaded "$final_id" "$custom_cache_file" "$actual_distro_id" "$addons_json" "custom"
    
    msg "Custom distro created: ${C_BOLD}$final_id${C_RESET}"
    info "Base: $actual_distro_id + addons: ${addons[*]}"
    info "File: $custom_cache_file"
  else
    # Simple download (no addons)
    if [[ "$is_custom" != "true" ]]; then
      # Store base distro
      index::store_downloaded "$final_id" "$cache_file"
    else
      # Custom name but no addons - just an alias
      index::store_downloaded "$final_id" "$cache_file" "$actual_distro_id" "[]" "alias"
    fi
    
    msg "Distro downloaded: ${C_BOLD}$final_id${C_RESET}"
    info "File: $cache_file"
  fi
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
  
  jq -r '.distros | to_entries[] | "\(.key)|\(.value.file)|\(.value.type // "base")|\(.value.base_distro // "")|\(.value.addons // [])"' "$LOCAL_INDEX" 2>/dev/null | \
  while IFS='|' read -r id file distro_type base_distro addons_json; do
    if [[ -f "$file" ]]; then
      local size
      size=$(du -sh "$file" 2>/dev/null | cut -f1)
      
      # Format display based on type
      case "$distro_type" in
        custom)
          local addons_list
          addons_list=$(echo "$addons_json" | jq -r 'join(", ")' 2>/dev/null)
          printf "  ${C_CYAN}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (base: %s + %s)${C_RESET}\n" "$id" "$size" "$base_distro" "$addons_list"
          ;;
        alias)
          printf "  ${C_MAGENTA}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (alias of %s)${C_RESET}\n" "$id" "$size" "$base_distro"
          ;;
        *)
          printf "  ${C_GREEN}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$id" "$size"
          ;;
      esac
    else
      printf "  ${C_RED}!${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}(file missing: %s)${C_RESET}\n" "$id" "$file"
    fi
  done
  
  echo
}

# Clean downloaded distro
distro::clean(){
  local distro_id="$1"
  require_jq
  
  # Validate name
  if ! index::validate_name "$distro_id"; then
    return 1
  fi
  
  index::init_local
  
  local file_path distro_type
  file_path=$(index::get_local_path "$distro_id")
  distro_type=$(jq -r ".distros[\"$distro_id\"].type // \"base\"" "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ -z "$file_path" ]]; then
    err "Distro not found in local index: $distro_id"
    info "Use ${C_BOLD}penv list -d${C_RESET} to see downloaded distros"
    return 1
  fi
  
  # Check if this is a base distro used by custom distros
  if [[ "$distro_type" == "base" ]]; then
    local dependents
    dependents=$(jq -r ".distros | to_entries[] | select(.value.base_distro == \"$distro_id\") | .key" "$LOCAL_INDEX" 2>/dev/null)
    
    if [[ -n "$dependents" ]]; then
      warn "This base distro is used by custom distros:"
      echo "$dependents" | while read -r dep; do
        echo -e "    ${C_CYAN}$dep${C_RESET}"
      done
      echo
      read -p "$(echo -e "${C_YELLOW}Remove anyway? Custom distros will still work. (y/N):${C_RESET} ")" yn
      
      case "$yn" in
        [Yy]) ;;
        *) 
          info "Aborted"
          return 0
          ;;
      esac
    fi
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
      echo '{"distros":{}}' > "$LOCAL_INDEX"
      msg "Cache cleared"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}
