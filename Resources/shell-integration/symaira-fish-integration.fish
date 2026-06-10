# Symaira Terminal - Fish Shell Integration
# Emits OSC 133 sequences for command blocks, exit codes, and prompt navigation.
# Add to config.fish: source /path/to/symaira-fish-integration.fish

function __symaira_prompt_start
    printf '\033]133;A\007'
end

function __symaira_command_start
    printf '\033]133;B\007'
end

function __symaira_command_end
    set -l exit_code $status
    printf '\033]133;C\007'
    printf '\033]133;D;%d\007' $exit_code
    return $exit_code
end

function __symaira_preexec
    __symaira_command_start
end

function __symaira_postexec
    __symaira_command_end
end

function __symaira_fish_prompt
    __symaira_prompt_start
end

# Install hooks
functions -c fish_prompt __symaira_original_fish_prompt
functions -c fish_right_prompt __symaira_original_fish_right_prompt

function fish_prompt
    __symaira_fish_prompt
    __symaira_original_fish_prompt
end

function fish_right_prompt
    __symaira_original_fish_right_prompt
end

# Event handlers
functions -e __symaira_event_handler
function __symaira_event_handler --on-event fish_preexec
    __symaira_preexec
end

functions -e __symaira_postexec_handler
function __symaira_postexec_handler --on-event fish_postexec
    __symaira_postexec
end

# Initial prompt start
__symaira_prompt_start
