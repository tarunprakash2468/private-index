_pi_completions() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="index watch search stats reset help --help -h"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        index|watch)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--install-launchagent" -- "$cur") )
            else
                COMPREPLY=( $(compgen -d -- "$cur") )
            fi
            return 0
            ;;
        search)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--limit" -- "$cur") )
            fi
            return 0
            ;;
    esac
}

complete -F _pi_completions pi
complete -F _pi_completions private-index
complete -F _pi_completions private-index-cli
