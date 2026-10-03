# ~/.bashrc: executed by bash(1) for non-login shells.
# DefokOS Custom Edition

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=10000

# Check window size after each command
shopt -s checkwinsize

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Enable color support of ls and add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# Load aliases if present
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Prompt temático Defoko:
# Estilo: [usuario@defokos:directorio]$ con colores lavanda (#b49fcc) y cian suave (#88c0d0)
COLOR_LAVENDER="\[\033[38;2;180;159;204m\]"
COLOR_CHARCOAL="\[\033[38;2;111;115;126m\]"
COLOR_CYAN="\[\033[38;2;136;192;208m\]"
COLOR_RESET="\[\033[00m\]"

PS1="${COLOR_LAVENDER}┌──(${COLOR_CYAN}\u@defokos${COLOR_LAVENDER})-[${COLOR_CHARCOAL}\w${COLOR_LAVENDER}]\n${COLOR_LAVENDER}└─▪${COLOR_RESET} "

# Habilitar autocompletado programable
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Banner temático al abrir terminal interactiva
if [ -t 1 ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi
