#!/usr/bin/env bash
# commands.sh - Main command implementations

# Namespace: cmd::

cmd::version(){
  echo "$CLIENT_VERSION"
}

cmd::init(){
  ensure_dirs
  index::init_local
  echo -e "${C_CYAN}Cache:${C_RESET}      $CACHE_DIR"
  echo -e "${C_CYAN}Envs:${C_RESET}       $ENVS_DIR"
  echo -e "${C_CYAN}Index URL:${C_RESET}  $INDEX_URL"
  echo
  if [[ -z "$DL_TOOL" ]]; then
    err "No download tool found. Install one of:"
    echo -e "    ${C_DIM}• aria2c${C_RESET}"
    echo -e "    ${C_DIM}• curl${C_RESET}"
    echo -e "    ${C_DIM}• wget${C_RESET}"
    return 1
  else
    msg "Downloader: $(which $DL_TOOL)"
  fi
  if ! command -v proot >/dev/null 2>&1; then
    info "proot not found. Compiling proot from source..."
    INSTALL_DIR="$BIN_DIR" "${SCRIPT_DIR}/build-proot.sh"
  else
    msg "proot: $(command -v proot)"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    err "jq not found"
    return 1
  else
    msg "jq: $(command -v jq)"
  fi
  echo
  info "penv $CLIENT_VERSION is ready to use!"
}

cmd::import(){
  if [[ $# -lt 2 ]]; then
    err "Usage: penv import <distro-id> <tarball-path>"
    echo -e "       penv import <distro-id> <tarball-path> [-f <family>]"
    info "Import a custom rootfs tarball as a distro"
    echo -e "  ${C_DIM}<distro-id>${C_RESET}     Unique identifier for the imported distro"
    echo -e "  ${C_DIM}<tarball-path>${C_RESET} Path to the rootfs tarball (.tar.gz)"
    echo -e "  ${C_DIM}-f <family>${C_RESET}    Optional: distro family (debian, alpine, arch, etc.)"
    return 2
  fi
  
  local distro_id="$1"
  local tarball_path="$2"
  shift 2
  
  local family=""
  
  # Parse optional arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--family)
        if [[ -z "$2" ]]; then
          err "Option -f requires a value"
          return 2
        fi
        family="$2"
        shift 2
        ;;
      *)
        err "Unknown option: $1"
        return 2
        ;;
    esac
  done
  
  distro::import "$distro_id" "$tarball_path" "$family"
}

cmd::mod(){
  local distro_id=""
  local new_name=""
  local addons=()
  local open_shell=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--name)
        if [[ -z "$2" ]]; then
          err "Option -n requires a value"
          return 2
        fi
        new_name="$2"
        shift 2
        ;;
      -a|--addon)
        if [[ -z "$2" ]]; then
          err "Option -a requires an addon ID"
          return 2
        fi
        addons+=("$2")
        shift 2
        ;;
      -s|--shell)
        open_shell=true
        shift
        ;;
      -*)
        err "Unknown option: $1"
        return 2
        ;;
      *)
        if [[ -z "$distro_id" ]]; then
          distro_id="$1"
        else
          err "Unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done
  
  if [[ -z "$distro_id" ]]; then
    err "Usage: penv mod <distro-id> [-a <addon> ...] -n <new-id> [-s]"
    info "Modify a distro (local or downloaded) by applying addons and/or manual changes"
    echo -e "  ${C_DIM}<distro-id>${C_RESET}  Base distro ID from local cache"
    echo -e "  ${C_DIM}-a <addon>${C_RESET}   Addon ID (can use multiple times, optional with -s)"
    echo -e "  ${C_DIM}-n <new-id>${C_RESET}  New distro ID for modified version ${C_DIM}(required)${C_RESET}"
    echo -e "  ${C_DIM}-s, --shell${C_RESET}  Open interactive shell for manual modifications"
    return 2
  fi
  
  if [[ ${#addons[@]} -eq 0 ]] && [[ "$open_shell" == "false" ]]; then
    err "At least one addon or -s option is required"
    info "Usage: penv mod $distro_id -a <addon> -n <new-id>"
    info "   Or: penv mod $distro_id -s -n <new-id>"
    return 2
  fi
  
  if [[ -z "$new_name" ]]; then
    err "New distro ID is required (-n option)"
    if [[ ${#addons[@]} -gt 0 ]]; then
      info "Usage: penv mod $distro_id -a ${addons[0]} -n <new-id>"
    else
      info "Usage: penv mod $distro_id -s -n <new-id>"
    fi
    return 2
  fi
  
  if [[ ${#addons[@]} -gt 0 ]]; then
    distro::modify "$distro_id" "$new_name" "$open_shell" "${addons[@]}"
  else
    distro::modify "$distro_id" "$new_name" "$open_shell"
  fi
}

cmd::get(){
  local list_mode=false
  local custom_name=""
  local distro_id=""
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--list)
        list_mode=true
        shift
        ;;
      -n|--name)
        if [[ -z "$2" ]]; then
          err "Option -n requires a value"
          return 2
        fi
        custom_name="$2"
        shift 2
        ;;
      -*)
        err "Unknown option: $1"
        return 2
        ;;
      *)
        if [[ -z "$distro_id" ]]; then
          distro_id="$1"
        else
          err "Unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done
  
  if $list_mode; then
    index::list_distros
    return 0
  fi
  
  if [[ -z "$distro_id" ]]; then
    err "Usage: penv get <distro-id> [-n <custom-name>]"
    echo -e "       penv get -l  ${C_DIM}(list available distros)${C_RESET}"
    return 2
  fi
  
  distro::download "$distro_id" "$custom_name"
}

cmd::create(){
  if [[ $# -eq 1 ]] && [[ "$1" == "-l" || "$1" == "--list" ]]; then
    distro::list_distro
    return 0
  fi
  
  if [[ $# -lt 2 ]]; then
    err "Usage: penv create <name> <distro-id>"
    echo -e "       penv create -l  ${C_DIM}(list downloaded distros)${C_RESET}"
    return 2
  fi
  
  env::create "$1" "$2"
}

cmd::shell(){
  env::shell "$@"
}

cmd::rm(){
  local remove_distros=false
  local remove_all=false
  local targets=()
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--distro)
        remove_distros=true
        shift
        ;;
      -a|--all)
        remove_all=true
        shift
        ;;
      -*)
        err "Unknown option: $1"
        info "Usage: penv rm <name>          Remove environment"
        info "       penv rm -d <id>        Remove distro"
        info "       penv rm -a             Remove all environments"
        info "       penv rm -d -a          Remove all distros"
        return 2
        ;;
      *)
        targets+=("$1")
        shift
        ;;
    esac
  done
  
  if $remove_distros; then
    # Remove distros
    if $remove_all; then
      distro::clean_all
    else
      if [[ ${#targets[@]} -eq 0 ]]; then
        err "Usage: penv rm -d <distro-id>"
        info "       penv rm -d -a  ${C_DIM}(remove all distros)${C_RESET}"
        return 2
      fi
      for target in "${targets[@]}"; do
        distro::clean "$target"
      done
    fi
  else
    # Remove environments
    if $remove_all; then
      env::delete_all
    else
      if [[ ${#targets[@]} -eq 0 ]]; then
        err "Usage: penv rm <name>"
        info "       penv rm -a  ${C_DIM}(remove all environments)${C_RESET}"
        return 2
      fi
      for target in "${targets[@]}"; do
        env::delete "$target"
      done
    fi
  fi
}

cmd::list(){
  local show_online=false
  local show_envs=false
  local show_downloaded=false
  local show_addons=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--online)
        show_online=true
        shift
        ;;
      -e|--envs)
        show_envs=true
        shift
        ;;
      -d|--downloaded)
        show_downloaded=true
        shift
        ;;
      -a|--addons)
        show_addons=true
        shift
        ;;
      *)
        err "Unknown option: $1"
        info "Usage: penv list [-o] [-e] [-d] [-a]"
        return 2
        ;;
    esac
  done
  
  # If no flags, default to envs
  if ! $show_online && ! $show_envs && ! $show_downloaded && ! $show_addons; then
    show_envs=true
  fi
  
  if $show_online; then
    index::list_distros
    if $show_addons; then
      echo
      index::list_addons
    fi
  fi
  
  if $show_downloaded; then
    distro::list_distro
  fi
  
  if $show_envs; then
    env::list
  fi
}



cmd::usage(){
  echo -e "${C_BOLD}${C_MAGENTA}penv${C_RESET} - proot environment manager"
  echo
  echo -e "${C_BOLD}USAGE:${C_RESET}"
  echo -e "  ${C_GREEN}penv version${C_RESET}                           Show penv version"
  echo -e "  ${C_GREEN}penv init${C_RESET}                           Initialize penv"
  echo -e "  ${C_GREEN}penv get${C_RESET} ${C_YELLOW}<id>${C_RESET}                      Download a distro"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-l, --list${C_RESET}                  List available distros"
  echo -e "      ${C_DIM}-n, --name <name>${C_RESET}           Save with custom name"
  echo -e "  ${C_GREEN}penv import${C_RESET} ${C_YELLOW}<id>${C_RESET} ${C_YELLOW}<tarball>${C_RESET}        Import custom rootfs tarball"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-f, --family <name>${C_RESET}         Set distro family (debian, alpine, etc.)"
  echo -e "  ${C_GREEN}penv mod${C_RESET} ${C_YELLOW}<distro-id>${C_RESET}              Modify distro with addons/shell"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-a, --addon <id>${C_RESET}            Apply addon (can use multiple times)"
  echo -e "      ${C_DIM}-s, --shell${C_RESET}                 Open shell for manual modifications"
  echo -e "      ${C_DIM}-n, --name <name>${C_RESET}           Save as new distro ID ${C_DIM}(required)${C_RESET}"
  echo -e "  ${C_GREEN}penv new${C_RESET} ${C_YELLOW}<name>${C_RESET} ${C_YELLOW}<distro-id>${C_RESET}      Create new environment"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-l, --list${C_RESET}                  List installed distros"
  echo -e "  ${C_GREEN}penv shell${C_RESET} ${C_YELLOW}<name>${C_RESET} ${C_YELLOW}[cmd]${C_RESET}           Enter environment shell or run command"
  echo -e "  ${C_GREEN}penv rm${C_RESET} ${C_YELLOW}<name>${C_RESET}                     Remove environment"
  echo -e "  ${C_GREEN}penv rm -d${C_RESET} ${C_YELLOW}<id>${C_RESET}                   Remove distro"
  echo -e "  ${C_GREEN}penv rm -a${C_RESET}                        Remove all environments"
  echo -e "  ${C_GREEN}penv rm -d -a${C_RESET}                     Remove all distros"
  echo -e "  ${C_GREEN}penv list${C_RESET}                           List resources"
  echo -e "    ${C_DIM}Options (combine multiple):${C_RESET}"
  echo -e "      ${C_DIM}-o, --online${C_RESET}                List online distros"
  echo -e "      ${C_DIM}-e, --envs${C_RESET}                  List environments ${C_DIM}(default)${C_RESET}"
  echo -e "      ${C_DIM}-d, --downloaded${C_RESET}            List installed distros"
  echo -e "      ${C_DIM}-a, --addons${C_RESET}                List available addons ${C_DIM}(with -o)${C_RESET}"
  echo
  echo -e "${C_BOLD}EXAMPLES:${C_RESET}"
  echo "  # Get a distro"
  echo "  penv get ubuntu"
  echo "  penv get ubuntu-24.04 -n my-ubuntu"
  echo
  echo "  # Import a custom rootfs"
  echo "  penv import my-custom /path/to/rootfs.tar.gz"
  echo "  penv import my-alpine rootfs.tar.gz -f alpine"
  echo
  echo "  # Modify distro with addons"
  echo "  penv mod ubuntu-24.04 -a nodejs -a python -n ubuntu-dev"
  echo "  penv mod my-custom -a build-tools -n my-custom-dev"
  echo
  echo "  # Modify with shell (manual changes)"
  echo "  penv mod ubuntu-24.04 -s -n ubuntu-custom"
  echo "  penv mod ubuntu-dev -a python -s -n ubuntu-dev-plus  # addons + shell"
  echo
  echo "  # Create and use environment"
  echo "  penv new myenv ubuntu-24.04"
  echo "  penv shell myenv"
  echo "  penv shell myenv python3 --version"
  echo
  echo "  # Remove resources"
  echo "  penv rm myenv            # remove environment"
  echo "  penv rm -d ubuntu-dev    # remove distro"
  echo "  penv rm -a               # remove all environments"
  echo "  penv rm -d -a            # remove all distros"
  echo
  echo "  # List everything"
  echo "  penv list -o -e -d       # online, envs, and distros"
  echo "  penv list -o -a          # online distros and addons"
  echo
  echo -e "${C_BOLD}ENVIRONMENT:${C_RESET}"
  echo -e "  ${C_DIM}PENV_INDEX_URL${C_RESET}  Custom index URL (default: GitHub)"
}
