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
    err "Distro not downloaded: $distro_id"
    info "Download it first: ${C_BOLD}penv download $distro_id${C_RESET}"
    return 1
  fi
  
  # Validate distro file
  if [[ ! -s "$distro_file" ]]; then
    err "Distro file is empty or corrupted: $distro_file"
    info "Re-download it: ${C_BOLD}penv clean $distro_id && penv download $distro_id${C_RESET}"
    return 1
  fi
  
  # Create environment
  header "Creating environment: $env_name"
  mkdir -p "$env_root"
  
  extract_tarball "$distro_file" "$env_root" || {
    rm -rf "$env_root"
    return 1
  }
  
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
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi
  
  # Validate environment name
  if ! index::validate_name "$env_name"; then
    return 1
  fi
  
  local env_root="$ENVS_DIR/$env_name"
  
  if [[ ! -d "$env_root" ]]; then
    err "Environment not found: $env_name"
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi
  
  # Sanity check: verify environment has basic structure
  if [[ ! -d "$env_root/bin" ]] && [[ ! -d "$env_root/usr" ]]; then
    err "Environment appears corrupted (missing /bin and /usr directories)"
    info "Recreate it: ${C_BOLD}penv delete $env_name && penv create $env_name <distro>${C_RESET}"
    return 1
  fi
  
  require_proot
  header "Entering environment: $env_name"
  echo -e "  ${C_DIM}rootfs: $env_root${C_RESET}"
  if [[ $EUID -eq 0 ]]; then
    echo -e "  ${C_DIM}mode: chroot (running as root)${C_RESET}"
  else
    echo -e "  ${C_DIM}mode: proot${C_RESET}"
  fi
  echo

  # Detect best default command
  local -a default_cmd
  if [[ -f "$env_root/penv/startup.sh" ]]; then
    default_cmd=(/bin/sh /penv/startup.sh)
  elif [[ -f "$env_root/bin/bash" ]]; then
    default_cmd=(/bin/bash --login)
  elif [[ -f "$env_root/bin/sh" ]]; then
    default_cmd=(/bin/sh --login)
  else
    default_cmd=""
  fi

  export PENV_ENV_MODE="environment"
  export PENV_ENV_NAME="$env_name"
  
  # Build final command
  local -a cmd
  if (( $# == 0 )); then
    if [[ -z "${default_cmd}" ]]; then
      err "No default shell found in environment: $env_name"
      info "Specify a command to run, e.g.: ${C_BOLD}penv shell $env_name /bin/sh${C_RESET}"
      return 1
    fi
    cmd=("${default_cmd[@]}")
  else
    cmd=( "$@" )
  fi
  
  exec_in_proot "$env_root" "${cmd[@]}"
}

# Delete environment
env::delete(){
  local env_name="$1"
  
  if [[ -z "$env_name" ]]; then
    err "Usage: penv delete <name>"
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi
  
  # Validate environment name
  if ! index::validate_name "$env_name"; then
    return 1
  fi
  
  local env_root="$ENVS_DIR/$env_name"
  
  if [[ ! -d "$env_root" ]]; then
    err "Environment not found: $env_name"
    info "Use ${C_BOLD}penv list${C_RESET} to see available environments"
    return 2
  fi
  
  local size
  size=$(du -sh "$env_root" 2>/dev/null | cut -f1)
  
  warn "About to delete environment: ${C_BOLD}$env_name${C_RESET} (${size})"
  echo -e "  ${C_DIM}Location: $env_root${C_RESET}"
  read -p "$(echo -e "${C_YELLOW}Are you sure? (y/N):${C_RESET} ")" yn
  
  case "$yn" in
    [Yy])
      rm -rf "$env_root"
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
      rm -rf "${ENVS_DIR:?}/"*
      msg "Deleted all environments"
      ;;
    *)
      info "Aborted"
      ;;
  esac
}
