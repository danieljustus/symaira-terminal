# Symaira Terminal - ZSH Shell Integration
# Emits OSC 133 sequences for command blocks, exit codes, and prompt navigation.
# Source this in your .zshrc: source /path/to/symaira-zsh-integration.zsh

# OSC 133 sequences
__symaira_prompt_start() { printf '\033]133;A\007'; }
__symaira_command_start() { printf '\033]133;B\007'; }
__symaira_command_end() { 
    local exit_code=$?
    printf '\033]133;C\007'
    printf '\033]133;D;%d\007' "$exit_code"
    return $exit_code
}

# Hook into prompt
__symaira_preexec() {
    __symaira_command_start
}

__symaira_precmd() {
    __symaira_command_end
    __symaira_prompt_start
}

# Install hooks
autoload -Uz add-zsh-hook
add-zsh-hook preexec __symaira_preexec
add-zsh-hook precmd __symaira_precmd

# Initial prompt start
__symaira_prompt_start
