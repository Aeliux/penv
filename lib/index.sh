#!/usr/bin/env bash
# index.sh - Index management functions

# Namespace: index::

# Fetch the remote index directly (no caching)
index::fetch_remote(){
  local temp_index
  temp_index=$(mktemp)
  
  # Download silently without cache check
  info "Fetching remote index..." >&2
  if ! download_file_nocache "$INDEX_URL" "$temp_index" >&2; then
    rm -f "$temp_index"
    err "Failed to fetch remote index" >&2
    return 1
  fi
  
  echo "$temp_index"
}

# Initialize local index if it doesn't exist
index::init_local(){
  if [[ ! -f "$LOCAL_INDEX" ]]; then
    echo '{"distros":{}}' > "$LOCAL_INDEX"
  else
    # Migrate from legacy format (pre-v2.0) if needed
    if jq -e '.custom' "$LOCAL_INDEX" >/dev/null 2>&1; then
      index::migrate_local_index
    fi
  fi
  
  return 0
}

# Migrate legacy local index format (pre-v2.0) to current format
index::migrate_local_index(){
  require_jq
  
  info "Migrating legacy local index to current format..." >&2
  
  local tmp_file
  tmp_file=$(mktemp)
  
  # Convert old format to new format
  if jq '
    # Start with existing distros, convert them to new format
    (.distros | to_entries | map({
      key: .key,
      value: {
        file: .value.file,
        downloaded: .value.downloaded,
        type: "base"
      }
    }) | from_entries) as $base_distros |
    
    # Process custom distros
    (.custom | to_entries | map({
      key: .key,
      value: {
        file: ($base_distros[.key].file // ($base_distros[.value.source].file // "")),
        downloaded: ($base_distros[.key].downloaded // (now | strftime("%Y-%m-%dT%H:%M:%S%z"))),
        base_distro: .value.source,
        addons: [],
        type: "alias"
      }
    }) | from_entries) as $custom_distros |
    
    # Merge base and custom distros
    {distros: ($base_distros + $custom_distros)}
  ' "$LOCAL_INDEX" > "$tmp_file"; then
    mv "$tmp_file" "$LOCAL_INDEX"
    msg "Local index migrated successfully" >&2
  else
    rm -f "$tmp_file"
    err "Failed to migrate local index" >&2
    return 1
  fi
}

# Get distro info from remote index
index::get_distro(){
  local distro_id="$1"
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  # Get from remote index only
  local data
  data=$(jq -r ".distros[\"$distro_id\"] // empty" "$remote_index" 2>/dev/null)
  
  # Clean up temp file
  rm -f "$remote_index"
  
  if [[ -z "$data" || "$data" == "null" ]]; then
    return 1
  fi
  
  echo "$data"
}

# Get addon info from remote index
index::get_addon(){
  local addon_id="$1"
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  local data
  data=$(jq -r ".addons[\"$addon_id\"] // empty" "$remote_index" 2>/dev/null)
  
  # Clean up temp file
  rm -f "$remote_index"
  
  if [[ -z "$data" || "$data" == "null" ]]; then
    return 1
  fi
  
  echo "$data"
}

# Check if addon is compatible with distro
index::addon_compatible(){
  local addon_data="$1"
  local distro_id="$2"
  
  # Get distroIds array from addon
  local distro_ids
  distro_ids=$(echo "$addon_data" | jq -r '.distroIds[]' 2>/dev/null)
  
  # Empty array means compatible with all
  if [[ -z "$distro_ids" ]]; then
    return 0
  fi
  
  # Check if distro_id is in the list
  while IFS= read -r id; do
    if [[ "$id" == "$distro_id" ]]; then
      return 0
    fi
  done <<< "$distro_ids"
  
  return 1
}

# List all available distros from remote index
index::list_distros(){
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  header "Available Distributions"
  
  jq -r '.distros | to_entries[] | "\(.key)|\(.value.name)|\(.value.description)"' "$remote_index" 2>/dev/null | sort | while IFS='|' read -r id name desc; do
    printf "  ${C_GREEN}%-30s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$id" "$desc"
  done
  
  # Clean up temp file
  rm -f "$remote_index"
  
  echo
}

# List all available addons
index::list_addons(){
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  header "Available Addons"
  
  local addon_count
  addon_count=$(jq -r '.addons | length' "$remote_index" 2>/dev/null)
  
  if [[ "$addon_count" -eq 0 ]]; then
    echo -e "  ${C_DIM}No addons available yet${C_RESET}"
    echo
    rm -f "$remote_index"
    return
  fi
  
  jq -r '.addons | to_entries[] | "\(.key)|\(.value.name)|\(.value.description)|\(.value.distroIds | length)"' "$remote_index" 2>/dev/null | sort | while IFS='|' read -r id name desc distro_count; do
    if [[ "$distro_count" -eq 0 ]]; then
      printf "  ${C_MAGENTA}%-30s${C_RESET} ${C_DIM}%s (universal)${C_RESET}\n" "$id" "$desc"
    else
      printf "  ${C_MAGENTA}%-30s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$id" "$desc"
    fi
  done
  
  # Clean up temp file
  rm -f "$remote_index"
  
  echo
}

# Validate distro name (alphanumeric, dashes, underscores, dots only)
index::validate_name(){
  local name="$1"
  
  if [[ -z "$name" ]]; then
    err "Name cannot be empty"
    return 1
  fi
  
  if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    err "Invalid name: '$name' (only alphanumeric, dashes, underscores, and dots allowed)"
    return 1
  fi
  
  if [[ ${#name} -gt 64 ]]; then
    err "Name too long: '$name' (max 64 characters)"
    return 1
  fi
  
  return 0
}

# Get URL for specific architecture
index::get_url_for_arch(){
  local distro_data="$1"
  local target_arch="${2:-$ARCH}"
  
  # Check if distro has URL for this arch
  local url
  url=$(echo "$distro_data" | jq -r ".urls[] | select(.arch == \"$target_arch\" or .arch == \"all\") | .url" | head -1)
  
  if [[ -z "$url" || "$url" == "null" ]]; then
    err "No URL available for architecture: $target_arch"
    return 1
  fi
  
  echo "$url"
}

# Store distro metadata in local index
# Args: distro_id, file_path, [base_distro], [addons_json_array], [type]
index::store_downloaded(){
  local distro_id="$1" 
  local file_path="$2"
  local base_distro="${3:-}"
  local addons_json="${4:-[]}"
  local distro_type="${5:-base}"
  
  require_jq
  index::init_local
  
  # Validate file exists and has content
  if [[ ! -f "$file_path" ]]; then
    err "Cannot store: file does not exist: $file_path"
    return 1
  fi
  
  if [[ ! -s "$file_path" ]]; then
    err "Cannot store: file is empty: $file_path"
    return 1
  fi
  
  local tmp_file
  tmp_file=$(mktemp)
  
  local jq_success=false
  if [[ -n "$base_distro" ]]; then
    # Store custom distro with base_distro and addons
    if jq --arg id "$distro_id" \
       --arg path "$file_path" \
       --arg date "$(date -Iseconds)" \
       --arg base "$base_distro" \
       --argjson addons "$addons_json" \
       --arg type "$distro_type" \
       '.distros[$id] = {file: $path, downloaded: $date, base_distro: $base, addons: $addons, type: $type}' \
       "$LOCAL_INDEX" > "$tmp_file"; then
      jq_success=true
    fi
  else
    # Store base distro
    if jq --arg id "$distro_id" \
       --arg path "$file_path" \
       --arg date "$(date -Iseconds)" \
       --arg type "$distro_type" \
       '.distros[$id] = {file: $path, downloaded: $date, type: $type}' \
       "$LOCAL_INDEX" > "$tmp_file"; then
      jq_success=true
    fi
  fi
  
  if [[ "$jq_success" == "true" ]]; then
    mv "$tmp_file" "$LOCAL_INDEX"
    return 0
  else
    rm -f "$tmp_file"
    err "Failed to update local index"
    return 1
  fi
}

# Get local path for downloaded distro (resolves aliases to base distro file)
index::get_local_path(){
  local distro_id="$1"
  require_jq
  
  index::init_local
  
  # Get the distro entry
  local distro_entry
  distro_entry=$(jq -r ".distros[\"$distro_id\"] // empty" "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ -z "$distro_entry" || "$distro_entry" == "null" ]]; then
    return 1
  fi
  
  # Check if it's an alias
  local distro_type base_distro file_path
  distro_type=$(echo "$distro_entry" | jq -r '.type // "base"')
  
  if [[ "$distro_type" == "alias" ]]; then
    # Resolve alias to base distro file
    base_distro=$(echo "$distro_entry" | jq -r '.base_distro // empty')
    if [[ -n "$base_distro" && "$base_distro" != "null" ]]; then
      file_path=$(jq -r ".distros[\"$base_distro\"].file // empty" "$LOCAL_INDEX" 2>/dev/null)
    fi
  else
    # Get file directly
    file_path=$(echo "$distro_entry" | jq -r '.file // empty')
  fi
  
  if [[ -z "$file_path" || "$file_path" == "null" ]]; then
    return 1
  fi
  
  echo "$file_path"
}
