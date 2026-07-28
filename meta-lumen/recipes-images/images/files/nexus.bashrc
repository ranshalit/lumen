# ~/.bashrc for user nexus on the Lumen appliance.
# Bash-only niceties for interactive shells (login and non-login).

# If not running interactively, do nothing.
case $- in
    *i*) ;;
    *) return;;
esac

shopt -s histappend checkwinsize

# Colored ls (only if dircolors is available; not shipped by default)
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
fi

# Colored prompt: green user@host, blue path
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Set xterm title to user@host: dir
case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;\u@\h: \w\a\]$PS1"
        ;;
esac

# For non-login interactive shells (subshells, bash inside tmux), /etc/profile
# is NOT sourced but this file IS -- pull in the system-wide aliases/env here.
if [ -f /etc/profile.d/lumen.sh ]; then
    . /etc/profile.d/lumen.sh
fi
