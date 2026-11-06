# shellcheck shell=bash
# Interactive-only part of `ws`, sourced from bash_additions.sh. The real
# command is bin/ws; this adds the one thing an executable can't do (cd)
# and tab completion.

# Call the dotfiles copy by its real path rather than ~/bin/ws, so this
# works before install_bin_scripts has linked it.
_ws_bin="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../bin/ws"

ws() {
    local dir
    if [[ $# -eq 1 ]] && dir="$("$_ws_bin" path "$1" 2>/dev/null)"; then
        cd "$dir" || return
    else
        "$_ws_bin" "$@"
    fi
}

_ws_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}" first="${COMP_WORDS[1]:-}"
    local ids="default ws1 ws2 ws3 ws4 ws5"
    local subs="all status acquire release adopt prep init whoami help"
    if [[ $COMP_CWORD -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$subs $ids" -- "$cur")
        return
    fi
    local flags=""
    case "$first" in
        status) flags="--json" ;;
        acquire) flags="--label --for --at --prep" ;;
        release) flags="--no-park --force --all --stale" ;;
        adopt) flags="--label --for --force" ;;
        prep | path) flags="" ;;
        all)
            mapfile -t COMPREPLY < <(compgen -c -- "$cur")
            return
            ;;
        default | ws[1-5] | [1-5])
            # `ws <id> <cmd...>`: complete the command, then fall back to files.
            if [[ $COMP_CWORD -eq 2 ]]; then
                mapfile -t COMPREPLY < <(compgen -c -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -f -- "$cur")
            fi
            return
            ;;
        *) return ;;
    esac
    # acquire never moves default, so --at doesn't apply there.
    if [[ "$first" == acquire && " ${COMP_WORDS[*]:2} " == *" default "* ]]; then
        flags="${flags/--at /}"
    fi
    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$flags" -- "$cur")
    else
        case "$first" in
            acquire | release | adopt | prep | path)
                mapfile -t COMPREPLY < <(compgen -W "$ids" -- "$cur") ;;
        esac
    fi
}
complete -F _ws_complete ws
