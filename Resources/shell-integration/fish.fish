# Symaira Terminal - Fish Shell Integration
# Emits OSC 133 (command zones) and OSC 7 (CWD) for agent awareness
# Add to ~/.config/fish/config.fish: source /path/to/symaira-terminal/Resources/shell-integration/fish.fish

# Avoid double-initialization
set -q _SYMIRA_INTEGRATION_LOADED; and return
set -g _SYMIRA_INTEGRATION_LOADED 1

function symaira_report_cwd --on-variable PWD
    printf '\033]7;file://%s%s\033\\' (hostname) $PWD
end

function symaira_cmd_start --on-event fish_preexec
    printf '\033]133;A\033\\'
    printf '\033]133;B\033\\'
end

function symaira_cmd_finish --on-event fish_postexec
    printf '\033]133;D;%d\033\\' $status
    printf '\033]133;C\033\\'
end

# Report initial CWD
symaira_report_cwd
