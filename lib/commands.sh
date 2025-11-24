#!/usr/bin/env bash
# commands.sh - Main command implementations

# Namespace: cmd::

cmd::init(){
  ensure_dirs
  header "penv initialized successfully!"
  echo -e "  ${C_CYAN}Cache:${C_RESET}      $CACHE_DIR"
  echo -e "  ${C_CYAN}Envs:${C_RESET}       $ENVS_DIR"
  echo -e "  ${C_CYAN}Index URL:${C_RESET}  $INDEX_URL"
  echo
  if [[ -z "$DL_TOOL" ]]; then
    warn "No download tool found. Install one of:"
    echo -e "    ${C_DIM}• aria2c (recommended)${C_RESET}"
    echo -e "    ${C_DIM}• curl${C_RESET}"
    echo -e "    ${C_DIM}• wget${C_RESET}"
  else
    msg "Downloader: $DL_TOOL"
  fi
  if ! command -v proot >/dev/null 2>&1; then
    warn "proot not found. Install it:"
    echo -e "    ${C_DIM}sudo apt update && sudo apt install -y proot${C_RESET}"
  else
    msg "proot: $(command -v proot)"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found (required for index). Install it:"
    echo -e "    ${C_DIM}sudo apt update && sudo apt install -y jq${C_RESET}"
  else
    msg "jq: $(command -v jq)"
  fi
  echo
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

cmd::download(){
  local list_mode=false
  local custom_name=""
  local distro_id=""
  local addons=()
  
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
      -a|--addon)
        if [[ -z "$2" ]]; then
          err "Option -a requires an addon ID"
          return 2
        fi
        addons+=("$2")
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
    err "Usage: penv download <distro-id> [-n <custom-name>] [-a <addon>]..."
    echo -e "       penv download -l  ${C_DIM}(list available distros)${C_RESET}"
    return 2
  fi
  
  if [[ ${#addons[@]} -gt 0 ]]; then
    distro::download "$distro_id" "$custom_name" "${addons[@]}"
  else
    distro::download "$distro_id" "$custom_name"
  fi
}

cmd::create(){
  if [[ $# -eq 1 ]] && [[ "$1" == "-l" || "$1" == "--list" ]]; then
    distro::list_downloaded
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

cmd::delete(){
  env::delete "$@"
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
    distro::list_downloaded
  fi
  
  if $show_envs; then
    env::list
  fi
}

cmd::cache(){
  distro::list_downloaded
}

cmd::clean(){
  if [[ $# -lt 1 ]]; then
    err "Usage: penv clean <distro-id>"
    echo -e "       penv clean --all  ${C_DIM}(remove all cached downloads)${C_RESET}"
    return 2
  fi
  
  if [[ "$1" == "--all" ]]; then
    distro::clean_all
  else
    distro::clean "$1"
  fi
}

cmd::usage(){
  echo -e "${C_BOLD}${C_MAGENTA}penv${C_RESET} - proot environment manager"
  echo
  echo -e "${C_BOLD}USAGE:${C_RESET}"
  echo -e "  ${C_GREEN}penv init${C_RESET}                           Initialize penv"
  echo -e "  ${C_GREEN}penv download${C_RESET} ${C_YELLOW}<id>${C_RESET}                   Download a distro"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-l, --list${C_RESET}                  List available distros"
  echo -e "      ${C_DIM}-n, --name <name>${C_RESET}           Save with custom name ${C_DIM}(required with -a)${C_RESET}"
  echo -e "      ${C_DIM}-a, --addon <id>${C_RESET}            Apply addon (can use multiple times)"
  echo -e "  ${C_GREEN}penv import${C_RESET} ${C_YELLOW}<id>${C_RESET} ${C_YELLOW}<tarball>${C_RESET}        Import custom rootfs tarball"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-f, --family <name>${C_RESET}         Set distro family (debian, alpine, etc.)"
  echo -e "  ${C_GREEN}penv create${C_RESET} ${C_YELLOW}<name>${C_RESET} ${C_YELLOW}<distro-id>${C_RESET}     Create new environment"
  echo -e "    ${C_DIM}Options:${C_RESET}"
  echo -e "      ${C_DIM}-l, --list${C_RESET}                  List downloaded distros"
  echo -e "  ${C_GREEN}penv shell${C_RESET} ${C_YELLOW}<name>${C_RESET} ${C_YELLOW}[cmd]${C_RESET}           Enter environment shell or run command"
  echo -e "  ${C_GREEN}penv list${C_RESET}                           List resources"
  echo -e "    ${C_DIM}Options (combine multiple):${C_RESET}"
  echo -e "      ${C_DIM}-o, --online${C_RESET}                List online distros"
  echo -e "      ${C_DIM}-e, --envs${C_RESET}                  List environments ${C_DIM}(default)${C_RESET}"
  echo -e "      ${C_DIM}-d, --downloaded${C_RESET}            List downloaded distros"
  echo -e "      ${C_DIM}-a, --addons${C_RESET}                List available addons ${C_DIM}(with -o)${C_RESET}"
  echo -e "  ${C_GREEN}penv delete${C_RESET} ${C_YELLOW}<name>${C_RESET}                 Delete an environment"
  echo -e "  ${C_GREEN}penv cache${C_RESET}                          Show downloaded distros (alias for list -d)"
  echo -e "  ${C_GREEN}penv clean${C_RESET} ${C_YELLOW}<id>${C_RESET}                    Remove cached distro"
  echo -e "  ${C_GREEN}penv clean --all${C_RESET}                   Remove all cached downloads"
  echo
  echo -e "${C_BOLD}EXAMPLES:${C_RESET}"
  echo "  # Download a vanilla distro"
  echo "  penv download ubuntu-24.04-vanilla"
  echo
  echo "  # Import a custom rootfs"
  echo "  penv import my-custom-distro /path/to/rootfs.tar.gz"
  echo "  penv import my-alpine alpine-rootfs.tar.gz -f alpine"
  echo
  echo "  # Download with custom name (required for addons)"
  echo "  penv download ubuntu-24.04-vanilla -n my-dev-env"
  echo
  echo "  # Download with addons (custom name required)"
  echo "  penv download ubuntu-24.04-vanilla -n ubuntu-dev -a nodejs -a python"
  echo
  echo "  # List everything"
  echo "  penv list -o -e -d       # online, envs, and downloaded"
  echo "  penv list -o -a          # online distros and addons"
  echo
  echo "  # Create and use environment"
  echo "  penv create myenv ubuntu-24.04-vanilla"
  echo "  penv shell myenv"
  echo "  penv shell myenv python3 --version  # run command"
  echo
  echo -e "${C_BOLD}ENVIRONMENT:${C_RESET}"
  echo -e "  ${C_DIM}PENV_INDEX_URL${C_RESET}  Custom index URL (default: GitHub)"
  echo
  echo -e "${C_BOLD}NOTES:${C_RESET}"
  echo -e "  ${C_DIM}• Custom name (-n) is required when using addons (-a)${C_RESET}"
  echo -e "  ${C_DIM}• Addons are distro-specific or universal${C_RESET}"
  echo -e "  ${C_DIM}• Addons are architecture-aware${C_RESET}"
  echo
  echo -e "${C_BOLD}ALIASES:${C_RESET}"
  echo -e "  ${C_DIM}enter -> shell, dl -> download, ls -> list, rm -> delete${C_RESET}"
}
