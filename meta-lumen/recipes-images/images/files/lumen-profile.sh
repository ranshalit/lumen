# /etc/profile.d/lumen.sh
# System-wide shell defaults for the Lumen appliance.
# Sourced by /etc/profile for login shells (both sh and bash).

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Make busybox admin applets (reboot, poweroff, halt, ip, ifconfig, ...)
# callable by bare name. /etc/profile only adds /sbin and /usr/sbin to PATH for
# root (uid 0); non-root users like nexus otherwise have to type the full path.
# Idempotent so re-sourcing (login shell + .bashrc) does not duplicate entries.
case ":$PATH:" in
    *:/sbin:*) ;;
    *) PATH="$PATH:/sbin:/usr/sbin" ;;
esac
export PATH

export HISTCONTROL=ignoreboth
export HISTSIZE=1000
export HISTFILESIZE=2000
