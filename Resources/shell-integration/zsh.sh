# Symaira Terminal - Zsh Shell Integration
# Emits OSC 133 (command zones) and OSC 7 (CWD) for agent awareness
# Add to ~/.zshrc: source /path/to/symaira-terminal/Resources/shell-integration/zsh.sh

# Avoid double-initialization
[[ -n "$_SYMIRA_INTEGRATION_LOADED" ]] && return
_SYMIRA_INTEGRATION_LOADED=1

# OSC 7: Report current working directory
symaira_report_cwd() {
    printf '\033]7;file://%s%s\033\\' "$(hostname)" "$PWD"
}

# OSC 133 A: Command start (prompt marker)
symaira_cmd_start() {
    printf '\033]133;A\033\\'
}

# OSC 133 B: Command input starts
symaira_cmd_input() {
    printf '\033]133;B\033\\'
}

# OSC 133 C: Command execution finishes
symaira_cmd_finish() {
    printf '\033]133;C\033\\'
}

# OSC 133 D;exitcode: Command finished with exit code
symaira_cmd_executed() {
    local exit_code=$?
    printf '\033]133;D;%d\033\\' "$exit_code"
}

# Hook into precmd/preexec for automatic reporting
symaira_preexec() {
    symaira_cmd_start
    symaira_cmd_input
}

symaira_precmd() {
    symaira_cmd_executed
    symaira_cmd_finish
    symaira_report_cwd
}

# Install hooks
autoload -Uz add-zsh-hook
add-zsh-hook preexec symaira_preexec
add-zsh-hook precmd symaira_precmd

# Report initial CWD
symaira_report_cwd
