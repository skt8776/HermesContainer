# Hermes container — interactive bash config
# Loaded for every interactive shell as the hermes user.

# Source system bashrc if available
[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc

# Friendly prompt
export PS1='\[\e[1;36m\]hermes\[\e[0m\]@\h:\[\e[1;33m\]\w\[\e[0m\]\$ '

# Persistent bash history across container runs (mounted volume)
if [ -d /commandhistory ]; then
    HISTFILE=/commandhistory/.bash_history
fi
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# Make Ctrl+V do nothing in bash (so the terminal's paste action wins).
# Same intent as ~/.inputrc, repeated here in case readline init order
# differs across shells.
bind -r '"\C-v"' 2>/dev/null || true
bind 'set enable-bracketed-paste on' 2>/dev/null || true

# Convenience aliases
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'

# Clipboard bridge helpers (see ~/.local/bin/cb)
alias cbset='cat > /workspace/.clipboard'
# Usage:
#   cb                       — print host clipboard (after running
#                              `Get-Clipboard | Out-File -Encoding utf8 .clipboard`
#                              on the host beforehand)
#   echo "text" | cbset      — stage text from inside the container
#   cb | claude -p           — pipe Windows clipboard into Claude Code

# Add Hermes user-local bin
export PATH="$HOME/.local/bin:$PATH"
