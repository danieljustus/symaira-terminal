# Symaira Terminal - Bash Shell Integration
# Emits OSC 133 (command zones) and OSC 7 (CWD) for agent awareness
# Add to ~/.bashrc: source /path/to/symaira-terminal/Resources/shell-integration/bash.sh

# Avoid double-initialization
[[ -n "$_SYMIRA_INTEGRATION_LOADED" ]] && return
_SYMIRA_INTEGRATION_LOADED=1

symaira_report_cwd() {
    printf '\033]7;file://%s%s\033\\' "$(hostname)" "$PWD"
}

symaira_cmd_start() {
    printf '\033]133;A\033\\'
}

symaira_cmd_input() {
    printf '\033]133;B\033\\'
}

symaira_cmd_finish() {
    printf '\033]133;C\033\\'
}

symaira_cmd_executed() {
    local exit_code=$?
    printf '\033]133;D;%d\033\\' "$exit_code"
}

# Bash doesn't have precmd/preexec hooks like zsh
# Use DEBUG trap and PROMPT_COMMAND instead
symaira_debug_trap() {
    # Only fire on actual command execution, not subshells
    [[ "$BASH_COMMAND" == "$PROMPT_COMMAND" ]] && return
    symaira_cmd_start
    symaira_cmd_input
}

symaira_prompt_command() {
    symaira_cmd_executed
    symaira_cmd_finish
    symaira_report_cwd
}

# Install hooks
trap symaira_debug_trap DEBUG
PROMPT_COMMAND="symaira_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

# Report initial CWD
symaira_report_cwd
