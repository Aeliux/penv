#!/usr/bin/env bash
# distro.sh - Distro download and management

# Namespace: distro::

# Import a custom rootfs tarball as a distro
distro::import(){
  local distro_id="$1"
  local tarball_path="$2"
  local family="${3:-}"
  
  ensure_dirs
  require_jq
  
  # Validate distro ID
  if ! index::validate_name "$distro_id"; then
    return 1
  fi
  
  # Normalize tarball path
  if [[ "$tarball_path" != /* ]]; then
    tarball_path="$PWD/$tarball_path"
  fi
  
  # Check if tarball exists
  if [[ ! -f "$tarball_path" ]]; then
    err "Tarball not found: $tarball_path"
    return 1
  fi
  
  # Check if tarball is readable
  if [[ ! -r "$tarball_path" ]]; then
    err "Cannot read tarball: $tarball_path"
    return 1
  fi
  
  # Check if tarball has content
  if [[ ! -s "$tarball_path" ]]; then
    err "Tarball is empty: $tarball_path"
    return 1
  fi
  
  # Validate tarball is actually a tar/gzip file
  local file_type
  file_type=$(file -b "$tarball_path" 2>/dev/null || echo "")
  
  if [[ ! "$file_type" =~ (gzip|tar|compressed) ]]; then
    err "File does not appear to be a valid tarball: $tarball_path"
    info "Detected type: $file_type"
    warn "Continuing anyway - extraction will fail if format is invalid"
  fi
  
  # Check if distro ID already exists
  index::init_local
  local exists
  exists=$(jq -r ".distros[\"$distro_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ -n "$exists" ]]; then
    err "Distro ID already exists: $distro_id"
    info "Use a different ID or clean existing: ${C_BOLD}penv clean $distro_id${C_RESET}"
    return 1
  fi
  
  header "Importing custom distro: $distro_id"
  info "Source: $tarball_path"
  echo
  
  # Validate tarball structure by attempting a test extraction
  info "Validating tarball structure..."
  local test_dir
  test_dir=$(mktemp -d)
  
  if ! tar -tzf "$tarball_path" >/dev/null 2>&1; then
    rm -rf "$test_dir"
    err "Invalid tarball format or corrupted file"
    return 1
  fi
  
  # Extract to test directory to verify it's a valid rootfs
  if ! extract_tarball "$tarball_path" "$test_dir"; then
    rm -rf "$test_dir"
    err "Failed to extract tarball"
    return 1
  fi
  
  # Verify it looks like a rootfs (has at least one of these directories)
  local has_rootfs_structure=false
  for dir in bin usr etc lib sbin; do
    if [[ -d "$test_dir/$dir" ]]; then
      has_rootfs_structure=true
      break
    fi
  done
  
  if [[ "$has_rootfs_structure" == "false" ]]; then
    rm -rf "$test_dir"
    err "Tarball does not appear to contain a valid rootfs structure"
    info "Expected at least one of: bin, usr, etc, lib, sbin"
    return 1
  fi
  
  msg "Tarball structure validated"
  
  # Auto-detect family if not provided
  if [[ -z "$family" ]]; then
    if [[ -f "$test_dir/penv/metadata/family" ]]; then
      family=$(cat "$test_dir/penv/metadata/family" 2>/dev/null | tr -d '\n\r')
      if [[ -n "$family" ]]; then
        info "Auto-detected family from metadata: $family"
      fi
    fi
    
    if [[ -z "$family" ]]; then
      rm -rf "$test_dir"
      err "Could not detect distro family"
      info "Family not found in /penv/metadata/family"
      info "Please specify family: ${C_BOLD}penv import $distro_id $tarball_path -f <family>${C_RESET}"
      info "Common families: debian, alpine, arch"
      return 1
    fi
  else
    info "Family: $family"
  fi
  
  # Clean up test extraction
  rm -rf "$test_dir"
  
  # Copy tarball to cache with distro ID name
  local cache_file="$CACHE_DIR/${distro_id}.tar.gz"
  info "Copying to cache..."
  
  if ! cp "$tarball_path" "$cache_file"; then
    err "Failed to copy tarball to cache"
    return 1
  fi
  
  # Verify copied file
  if [[ ! -f "$cache_file" ]] || [[ ! -s "$cache_file" ]]; then
    err "Cache file verification failed"
    rm -f "$cache_file"
    return 1
  fi
  
  # Store in local index as imported distro
  if ! index::store_downloaded "$distro_id" "$cache_file" "" "[]" "imported" "$family"; then
    err "Failed to update local index"
    rm -f "$cache_file"
    return 1
  fi
  
  local size
  size=$(du -sh "$cache_file" 2>/dev/null | cut -f1)
  
  echo
  msg "Successfully imported: ${C_BOLD}$distro_id${C_RESET}"
  info "Create environment: ${C_BOLD}penv new <name> $distro_id${C_RESET}"
  echo
  
  return 0
}

# Download a distro
distro::download(){
  local distro_id="$1"
  local custom_name="$2"
  
  ensure_dirs
  require_jq
  
  # Get distro info from remote index
  local distro_data
  distro_data=$(index::get_distro "$distro_id" || true)
  
  if [[ -z "$distro_data" ]]; then
    err "Distro not found: $distro_id"
    return 1
  fi
  
  # Get the actual distro ID and family (in case user provided an alias)
  local actual_distro_id distro_family
  actual_distro_id=$(echo "$distro_data" | jq -r '.id')
  distro_family=$(echo "$distro_data" | jq -r '.family // "unknown"')
  
  # Determine if this is a custom name or alias
  local is_custom=false
  local final_id="$distro_id"
  
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
      return 1
    fi
  fi
  
  # Check if base distro exists, download if not
  local base_distro_file
  base_distro_file=$(index::get_local_path "$actual_distro_id" || true)
  
  if [[ -z "$base_distro_file" ]] || [[ ! -f "$base_distro_file" ]]; then
    # Base distro doesn't exist, download it
    header "Downloading distro: $actual_distro_id"
    
    # Get URL and checksum for current architecture
    local url checksum
    url=$(index::get_url_for_arch "$distro_data" "$ARCH")
    checksum=$(echo "$distro_data" | jq -r ".urls[] | select(.arch == \"$ARCH\" or .arch == \"all\") | .sha256 // empty" | head -1)
    
    if [[ -z "$url" ]]; then
      return 1
    fi
    
    local base_cache_file="$CACHE_DIR/${actual_distro_id}.tar.gz"
    
    # Download base distro
    download_file "$url" "$base_cache_file" || return 1
    
    # Verify checksum
    if ! verify_checksum "$base_cache_file" "$checksum"; then
      err "Downloaded file failed checksum verification"
      rm -f "$base_cache_file"
      return 1
    fi
    
    # Store base distro in index with family
    index::store_downloaded "$actual_distro_id" "$base_cache_file" "" "[]" "base" "$distro_family"
    base_distro_file="$base_cache_file"
    
    msg "Distro downloaded: ${C_BOLD}$actual_distro_id${C_RESET}"
  else
    msg "Distro already cached: $actual_distro_id"
  fi
  
  # Handle alias creation
  if [[ "$final_id" != "$actual_distro_id" ]]; then
    # Alias: just store reference to base distro, no file duplication
    index::store_downloaded "$final_id" "$base_distro_file" "$actual_distro_id" "[]" "alias" "$distro_family"
    msg "Alias created: ${C_BOLD}$final_id${C_RESET}"
  fi
  
  info "Create environment: ${C_BOLD}penv new <name> $final_id${C_RESET}"
  return 0
}

# Modify a distro with addons (works on local distros)
distro::modify(){
  local distro_id="$1"
  local new_id="$2"
  local open_shell="$3"
  shift 3
  local addons=("$@")
  
  ensure_dirs
  require_jq
  
  # Validate new distro ID
  if ! index::validate_name "$new_id"; then
    return 1
  fi
  
  # Check if new ID already exists
  index::init_local
  local exists
  exists=$(jq -r ".distros[\"$new_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
  if [[ -n "$exists" ]]; then
    err "Distro ID already exists: $new_id"
    info "Use a different ID or remove existing: ${C_BOLD}penv rm -d $new_id${C_RESET}"
    return 1
  fi
  
  # Get source distro from local index
  local source_file source_family source_type
  source_file=$(index::get_local_path "$distro_id" || true)
  
  if [[ -z "$source_file" ]] || [[ ! -f "$source_file" ]]; then
    err "Source distro not found in local index: $distro_id"
    return 1
  fi
  
  # Get family and type from local index
  # First try the distro_id directly
  local distro_entry
  distro_entry=$(jq -r ".distros[\"$distro_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
  
  # If not found or if it's an alias, get the base distro's metadata
  if [[ -z "$distro_entry" ]] || [[ "$(echo "$distro_entry" | jq -r '.type // "base"')" == "alias" ]]; then
    # Find the base distro that owns this file
    local base_distro_id
    base_distro_id=$(jq -r --arg file "$source_file" '.distros | to_entries[] | select(.value.file == $file and (.value.type // "base") != "alias") | .key' "$LOCAL_INDEX" 2>/dev/null | head -1)
    
    if [[ -n "$base_distro_id" ]]; then
      distro_entry=$(jq -r ".distros[\"$base_distro_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
    fi
  fi
  
  source_family=$(echo "$distro_entry" | jq -r '.family // "unknown"')
  source_type=$(echo "$distro_entry" | jq -r '.type // "base"')
  
  header "Modifying distro: $distro_id"
  info "Source: $distro_id ($source_type)"
  info "Target: $new_id"
  if [[ ${#addons[@]} -gt 0 ]]; then
    info "Addons: ${addons[*]}"
  fi
  if [[ -n "$source_family" && "$source_family" != "unknown" ]]; then
    info "Family: $source_family"
  fi
  echo
  
  local addons_json
  addons_json=$(printf '%s\n' "${addons[@]}" | jq -R . | jq -s .)
  
  local output_file="$CACHE_DIR/${new_id}.tar.gz"
  
  # Apply addons to source distro (if any)
  if [[ ${#addons[@]} -gt 0 ]]; then
    if ! distro::apply_addons_and_shell "$source_file" "$output_file" "$distro_id" "$source_family" "$open_shell" "${addons[@]}"; then
      return 1
    fi
  else
    # No addons, just open shell if requested
    if ! distro::shell_and_pack "$source_file" "$output_file" "$open_shell"; then
      return 1
    fi
  fi
  
  # Store modified distro with metadata
  index::store_downloaded "$new_id" "$output_file" "$distro_id" "$addons_json" "custom" "$source_family"
  
  echo
  msg "Modified distro created: ${C_BOLD}$new_id${C_RESET}"
  info "Create environment: ${C_BOLD}penv new <name> $new_id${C_RESET}"
  echo
  
  return 0
}

# Apply addons and optionally open shell for manual modifications
distro::apply_addons_and_shell(){
  local source_tarball="$1"
  local output_file="$2"
  local distro_id="$3"
  local distro_family="$4"
  local open_shell="$5"
  shift 5
  local addons=("$@")
  
  require_proot
  require_jq
  
  local temp_root
  temp_root=$(mktemp -d)
  
  # Extract original
  info "Extracting base distro..."
  extract_tarball "$source_tarball" "$temp_root" || {
    rm -rf "$temp_root"
    err "Failed to extract base distro"
    return 1
  }
  
  export PENV_ENV_MODE="addon"

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
    if ! index::addon_compatible "$addon_data" "$distro_id" "$distro_family"; then
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
  
  # Open interactive shell if requested
  if [[ "$open_shell" == "true" ]]; then
    echo
    header "Manual Modification Shell"
    info "You are now in the distro rootfs"
    info "Make any manual changes you need"
    warn "Changes will be saved when you exit the shell"
    echo
    
    if ! launch_shell "$temp_root"; then
      rm -rf "$temp_root"
      err "Failed to launch shell"
      return 1
    fi
    
    echo
    info "Continuing with packaging..."
  fi
  
  # Compress modified rootfs
  compress_tarball "$temp_root" "$output_file" || {
    rm -rf "$temp_root"
    err "Failed to compress modified distro"
    return 1
  }
  
  # Cleanup
  rm -rf "$temp_root"
  
  return 0
}

# Open shell and pack distro (no addons)
distro::shell_and_pack(){
  local source_tarball="$1"
  local output_file="$2"
  local open_shell="$3"
  
  local temp_root
  temp_root=$(mktemp -d)
  
  # Extract original
  info "Extracting base distro..."
  extract_tarball "$source_tarball" "$temp_root" || {
    rm -rf "$temp_root"
    err "Failed to extract base distro"
    return 1
  }
  
  export PENV_ENV_MODE="mod"

  # Setup proot environment
  setup_proot_env "$temp_root"
  
  # Open interactive shell
  if [[ "$open_shell" == "true" ]]; then
    echo
    header "Manual Modification Shell"
    info "You are now in the distro rootfs"
    info "Make any manual changes you need"
    warn "Changes will be saved when you exit the shell"
    echo
    
    if ! launch_shell "$temp_root"; then
      rm -rf "$temp_root"
      err "Failed to launch shell"
      return 1
    fi
    
    echo
    info "Continuing with packaging..."
  fi
  
  # Compress modified rootfs
  compress_tarball "$temp_root" "$output_file" || {
    rm -rf "$temp_root"
    err "Failed to compress modified distro"
    return 1
  }
  
  # Cleanup
  rm -rf "$temp_root"
  
  return 0
}

# List distros
distro::list_distro(){
  require_jq
  index::init_local
  
  header "Installed Distribution Images"
  
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
          if [[ -n "$addons_list" ]]; then
            printf "  ${C_CYAN}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (base: %s + %s)${C_RESET}\n" "$id" "$size" "$base_distro" "$addons_list"
          else
            printf "  ${C_CYAN}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (base: %s, modified)${C_RESET}\n" "$id" "$size" "$base_distro"
          fi
          ;;
        alias)
          printf "  ${C_MAGENTA}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (alias of %s)${C_RESET}\n" "$id" "$size" "$base_distro"
          ;;
        imported)
          printf "  ${C_YELLOW}*${C_RESET} ${C_BOLD}%-30s${C_RESET} ${C_DIM}%s (imported)${C_RESET}\n" "$id" "$size"
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
  file_path=$(jq -r ".distros[\"$distro_id\"].file // empty" "$LOCAL_INDEX" 2>/dev/null)
  distro_type=$(jq -r ".distros[\"$distro_id\"].type // \"base\"" "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ -z "$file_path" ]]; then
    err "Distro not found in local index: $distro_id"
    info "Use ${C_BOLD}penv list -d${C_RESET} to see downloaded distros"
    return 1
  fi
  
  # Check if this is a base distro used by custom distros or aliases
  if [[ "$distro_type" == "base" ]]; then
    local dependents
    dependents=$(jq -r ".distros | to_entries[] | select(.value.base_distro == \"$distro_id\") | .key" "$LOCAL_INDEX" 2>/dev/null)
    
    if [[ -n "$dependents" ]]; then
      local custom_count alias_count
      custom_count=$(jq -r "[.distros | to_entries[] | select(.value.base_distro == \"$distro_id\" and .value.type == \"custom\")] | length" "$LOCAL_INDEX" 2>/dev/null)
      alias_count=$(jq -r "[.distros | to_entries[] | select(.value.base_distro == \"$distro_id\" and .value.type == \"alias\")] | length" "$LOCAL_INDEX" 2>/dev/null)
      
      warn "This base distro is used by:"
      if [[ "$custom_count" -gt 0 ]]; then
        echo "  Custom distros ($custom_count):"
        jq -r ".distros | to_entries[] | select(.value.base_distro == \"$distro_id\" and .value.type == \"custom\") | .key" "$LOCAL_INDEX" 2>/dev/null | while read -r dep; do
          echo -e "    ${C_CYAN}$dep${C_RESET}"
        done
      fi
      if [[ "$alias_count" -gt 0 ]]; then
        echo "  Aliases ($alias_count):"
        jq -r ".distros | to_entries[] | select(.value.base_distro == \"$distro_id\" and .value.type == \"alias\") | .key" "$LOCAL_INDEX" 2>/dev/null | while read -r dep; do
          echo -e "    ${C_MAGENTA}$dep${C_RESET}"
        done
      fi
      echo
      read -p "$(echo -e "${C_YELLOW}Remove anyway? Custom distros will still work, aliases will break. (y/N):${C_RESET} ")" yn
      
      case "$yn" in
        [Yy]) ;;
        *) 
          info "Aborted"
          return 0
          ;;
      esac
    fi
  fi
  
  # For aliases, just remove from index (file is shared)
  if [[ "$distro_type" == "alias" ]]; then
    local tmp_file
    tmp_file=$(mktemp)
    if jq --arg id "$distro_id" 'del(.distros[$id])' "$LOCAL_INDEX" > "$tmp_file"; then
      mv "$tmp_file" "$LOCAL_INDEX"
      msg "Removed alias: $distro_id"
    else
      rm -f "$tmp_file"
      err "Failed to update local index"
      return 1
    fi
    return 0
  fi
  
  # For base and custom distros, remove file and index entry
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
  if jq --arg id "$distro_id" 'del(.distros[$id])' "$LOCAL_INDEX" > "$tmp_file"; then
    mv "$tmp_file" "$LOCAL_INDEX"
  else
    rm -f "$tmp_file"
    err "Failed to update local index"
    return 1
  fi
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
