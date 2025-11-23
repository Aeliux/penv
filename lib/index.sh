#!/usr/bin/env bash
# index.sh - Index management functions

# Namespace: index::

# Download and cache the remote index
index::fetch_remote(){
  local index_cache="$PENV_DIR/remote_index.json"
  local age=0
  
  if [[ -f "$index_cache" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$index_cache" 2>/dev/null || stat -f %m "$index_cache" 2>/dev/null || echo 0) ))
  fi
  
  # Refresh if older than 1 hour (3600 seconds)
  if [[ ! -f "$index_cache" ]] || (( age > 3600 )); then
    info "Fetching remote index..." >&2
    download_file "$INDEX_URL" "$index_cache" >&2 || {
      err "Failed to fetch remote index" >&2
      return 1
    }
  fi
  
  echo "$index_cache"
}

# Initialize local index if it doesn't exist
index::init_local(){
  if [[ ! -f "$LOCAL_INDEX" ]]; then
    echo '{"distros":{},"custom":{}}' > "$LOCAL_INDEX"
  fi
}

# Get distro info from index (remote or local custom)
index::get_distro(){
  local distro_id="$1"
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  index::init_local
  
  # Try remote index first
  local data
  data=$(jq -r ".distros[\"$distro_id\"] // empty" "$remote_index" 2>/dev/null)
  
  # Fall back to local custom distros
  if [[ -z "$data" || "$data" == "null" ]]; then
    # Check if it's a custom distro pointing to a real one
    local source_id
    source_id=$(jq -r ".custom[\"$distro_id\"].source // empty" "$LOCAL_INDEX" 2>/dev/null)
    if [[ -n "$source_id" && "$source_id" != "null" ]]; then
      # Get the real distro data from source
      data=$(jq -r ".distros[\"$source_id\"] // empty" "$remote_index" 2>/dev/null)
    fi
  fi
  
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

# List all available distros
index::list_distros(){
  require_jq
  
  local remote_index
  remote_index=$(index::fetch_remote) || return 1
  
  index::init_local
  
  header "Available Distributions"
  
  echo -e "${C_BOLD}${C_CYAN}Remote Distributions:${C_RESET}"
  jq -r '.distros | to_entries[] | "\(.key)|\(.value.name)|\(.value.description)"' "$remote_index" 2>/dev/null | sort | while IFS='|' read -r id name desc; do
    printf "  ${C_GREEN}%-30s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$id" "$desc"
  done
  
  echo
  echo -e "${C_BOLD}${C_CYAN}Custom Distributions:${C_RESET}"
  local custom_count
  custom_count=$(jq -r '.custom | length' "$LOCAL_INDEX" 2>/dev/null)
  
  if [[ "$custom_count" -gt 0 ]]; then
    jq -r '.custom | to_entries[] | "\(.key)|\(.value.source)"' "$LOCAL_INDEX" 2>/dev/null | sort | while IFS='|' read -r id source; do
      printf "  ${C_CYAN}%-30s${C_RESET} ${C_DIM}(alias of %s)${C_RESET}\n" "$id" "$source"
    done
  else
    echo -e "  ${C_DIM}No custom distributions yet${C_RESET}"
  fi
  
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
    return
  fi
  
  jq -r '.addons | to_entries[] | "\(.key)|\(.value.name)|\(.value.description)|\(.value.distroIds | length)"' "$remote_index" 2>/dev/null | sort | while IFS='|' read -r id name desc distro_count; do
    if [[ "$distro_count" -eq 0 ]]; then
      printf "  ${C_MAGENTA}%-30s${C_RESET} ${C_DIM}%s (universal)${C_RESET}\n" "$id" "$desc"
    else
      printf "  ${C_MAGENTA}%-30s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$id" "$desc"
    fi
  done
  
  echo
}

# Add a custom distro alias to local index
index::add_custom(){
  local custom_id="$1" source_id="$2" custom_name="$3"
  require_jq
  
  index::init_local
  
  # Verify source exists
  if ! index::get_distro "$source_id" >/dev/null 2>&1; then
    err "Source distro not found: $source_id"
    return 1
  fi
  
  # Add to local index
  local tmp_file
  tmp_file=$(mktemp)
  jq --arg id "$custom_id" \
     --arg source "$source_id" \
     --arg name "$custom_name" \
     '.custom[$id] = {name: $name, source: $source, arch: "all"}' \
     "$LOCAL_INDEX" > "$tmp_file" && mv "$tmp_file" "$LOCAL_INDEX"
  
  msg "Added custom distro: $custom_id -> $source_id"
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
index::store_downloaded(){
  local distro_id="$1" file_path="$2"
  require_jq
  
  index::init_local
  
  local tmp_file
  tmp_file=$(mktemp)
  jq --arg id "$distro_id" \
     --arg path "$file_path" \
     --arg date "$(date -Iseconds)" \
     '.distros[$id] = {file: $path, downloaded: $date}' \
     "$LOCAL_INDEX" > "$tmp_file" && mv "$tmp_file" "$LOCAL_INDEX"
}

# Get local path for downloaded distro
index::get_local_path(){
  local distro_id="$1"
  require_jq
  
  index::init_local
  
  jq -r ".distros[\"$distro_id\"].file // empty" "$LOCAL_INDEX" 2>/dev/null
}
