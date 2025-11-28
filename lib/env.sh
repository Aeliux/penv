#!/usr/bin/env bash
# env.sh - Environment management functions

# Namespace: env::

# List environments
env::list(){
  header "Available Environments"
  
  if [[ -d "$ENVS_DIR" ]] && [[ -n "$(ls -A "$ENVS_DIR" 2>/dev/null)" ]]; then
    for env in "$ENVS_DIR"/*; do
      local name size
      name=$(basename "$env")
      size=$(du -sh "$env" 2>/dev/null | cut -f1)
      printf "  ${C_GREEN}*${C_RESET} ${C_BOLD}%-20s${C_RESET} ${C_DIM}(%s)${C_RESET}\n" "$name" "$size"
    done
  else
    echo -e "  ${C_DIM}No environments created yet.${C_RESET}"
    echo -e "  ${C_DIM}Use: penv create <name> <distro-id>${C_RESET}"
  fi
  
  echo
}

# Create environment
env::create(){
  local env_name="$1"
  local distro_id="$2"
  
  ensure_dirs
  
  if [[ -z "$env_name" ]] || [[ -z "$distro_id" ]]; then
    err "Usage: penv create <name> <distro-id>"
    return 1
  fi
  
  # Validate environment name
  if ! index::validate_name "$env_name"; then
    return 1
  fi
  
  # Check if env already exists
  local env_root="$ENVS_DIR/$env_name"
  if [[ -d "$env_root" ]]; then
    err "Environment already exists: $env_name"
    info "Delete it first: ${C_BOLD}penv delete $env_name${C_RESET}"
    return 1
  fi
  
  # Get distro file path
  local distro_file
  distro_file=$(index::get_local_path "$distro_id")
  
  if [[ -z "$distro_file" ]] || [[ ! -f "$distro_file" ]]; then
    err "Distro not found in local index: $distro_id"
    return 1
  fi
  
  # Validate distro file
  if [[ ! -s "$distro_file" ]]; then
    err "Distro file is empty or corrupted: $distro_file"
    return 1
  fi
  
  # Create environment
  header "Creating environment: $env_name"
  mkdir -p "$env_root"
  
  extract_tarball "$distro_file" "$env_root" || {
    safe_rm "$env_root"
    return 1
  }
  
  export PENV_ENV_MODE="prepare"

  # Setup proot environment
  setup_proot_env "$env_root"
  
  echo
  msg "Environment created: ${C_BOLD}$env_name${C_RESET}"
  info "Enter with: ${C_BOLD}penv shell $env_name${C_RESET}"
  echo
}

# Enter environment shell
env::shell(){
  local env_name="$1"
  shift
  
  if [[ -z "$env_name" ]]; then
    err "Usage: penv shell <name> [command...]"
    return 2
  fi
  
  # Validate environment name
  if ! index::validate_name "$env_name"; then
    return 1
  fi
  
  local env_root="$ENVS_DIR/$env_name"
  
  if [[ ! -d "$env_root" ]]; then
    err "Environment not found: $env_name"
    return 2
  fi
  
  require_proot

  export PENV_ENV_MODE="environment"
  export PENV_ENV_NAME="$env_name"
  
  exec_in_proot "$env_root" "$@"
}

# Delete environment
env::delete(){
  local env_name="$1"
  
  if [[ -z "$env_name" ]]; then
    err "Usage: penv delete <name>"
    return 2
  fi
  
  # Validate environment name
  if ! index::validate_name "$env_name"; then
    return 1
  fi
  
  local env_root="$ENVS_DIR/$env_name"
  
  if [[ ! -d "$env_root" ]]; then
    err "Environment not found: $env_name"
    return 2
  fi
  
  local size
  size=$(du -sh "$env_root" 2>/dev/null | cut -f1)
  
  warn "About to delete environment: ${C_BOLD}$env_name${C_RESET} (${size})"
  echo -e "  ${C_DIM}Location: $env_root${C_RESET}"
  read -p "$(echo -e "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
  
  case "$yn" in
    [Yy])
      safe_rm "$env_root"
      msg "Deleted: $env_name"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}

# Delete all environments
env::delete_all(){
  ensure_dirs
  
  if [[ ! -d "$ENVS_DIR" ]] || [[ ! "$(ls -A "$ENVS_DIR" 2>/dev/null)" ]]; then
    info "No environments to delete"
    return 0
  fi
  
  local count
  count=$(find "$ENVS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
  local total_size
  total_size=$(du -sh "$ENVS_DIR" 2>/dev/null | cut -f1)
  
  warn "About to delete all $count environment(s) (${total_size})"
  echo -e "  ${C_DIM}Location: $ENVS_DIR${C_RESET}"
  read -p "$(echo -e "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
  
  case "$yn" in
    [Yy])
      safe_rm "$ENVS_DIR"/*
      msg "Deleted all environments"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}
