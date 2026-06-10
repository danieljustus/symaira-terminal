# Symaira Terminal - Bash Shell Integration
# Emits OSC 133 sequences for command blocks, exit codes, and prompt navigation.
# Source this in your .bashrc: source /path/to/symaira-bash-integration.bash

# OSC 133 sequences
__symaira_prompt_start() { printf '\033]133;A\007'; }
__symaira_command_start() { printf '\033]133;B\007'; }
__symaira_command_end() { 
    local exit_code=$?
    printf '\033]133;C\007'
    printf '\033]133;D;%d\007' "$exit_code"
    return $exit_code
}

# Hook into PROMPT_COMMAND
__symaira_original_prompt_command="$PROMPT_COMMAND"
__symaira_prompt_command() {
    __symaira_command_end
    __symaira_prompt_start
    eval "$__symaira_original_prompt_command"
}
PROMPT_COMMAND="__symaira_prompt_command"

# Trap DEBUG for command start
trap '__symaira_command_start' DEBUG

# Initial prompt start
__symaira_prompt_start
