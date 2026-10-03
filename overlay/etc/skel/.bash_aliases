# ==============================================================================
#  DEFOKOS // USER SHELL ALIASES (.bash_aliases)
# ==============================================================================

# Navegación y listado con colores
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Mantenimiento del Sistema (APT + Flatpak)
alias update='sudo apt update && sudo apt upgrade -y && flatpak update -y'
alias clean='sudo apt autoremove -y && sudo apt autoclean && flatpak uninstall --unused -y'

# Comandos Temáticos y Audio / Síntesis
alias defoko='fastfetch'
alias audio-devices='pactl list short sinks && pactl list short sources'
alias pipewire-status='systemctl --user status pipewire pipewire-pulse wireplumber'

# Atajos de desarrollo
alias g='git'
alias gs='git status'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias code='codium'

# Soporte AppImage (recordatorio permisos)
appimage-make-executable() {
    chmod +x "$@"
    echo "Permiso de ejecución otorgado a: $@"
}
