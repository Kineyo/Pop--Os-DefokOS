#!/usr/bin/env bash
# ==============================================================================
#  DEFOKOS // THEME & BRANDING APPLICATION SCRIPT (apply-theme.sh)
#  Aplica configuraciones visuales globales, dotfiles de skel y esquemas dconf/cosmic.
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_LAVENDER="\033[38;2;180;159;204m"
C_CYAN="\033[38;2;136;192;208m"
C_GREEN="\033[38;2;142;192;156m"

log_info()    { echo -e "${C_BOLD}${C_LAVENDER}[THEME:INFO]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_success() { echo -e "${C_BOLD}${C_GREEN}[THEME:OK]${C_RESET} $*"; }

log_step "1. Compilando esquemas GSettings / GLib"
if [ -d /usr/share/glib-2.0/schemas ]; then
    log_info "Compilando schemas en /usr/share/glib-2.0/schemas..."
    glib-compile-schemas /usr/share/glib-2.0/schemas/
    log_success "Esquemas compilados correctamente con soporte de fondo y tema oscuro."
fi

log_step "2. Configurando terminal por defecto del sistema"
if command -v update-alternatives >/dev/null 2>&1 && command -v kitty >/dev/null 2>&1; then
    log_info "Configurando Kitty como alternativa por defecto para x-terminal-emulator..."
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 60 || true
    update-alternatives --set x-terminal-emulator /usr/bin/kitty || true
fi

log_step "3. Configurando wallpapers y enlaces simbólicos"
WALLPAPER_DIR="/usr/share/backgrounds/defokos"
if [ -f "${WALLPAPER_DIR}/defoko-default.svg" ]; then
    log_info "Wallpaper temático encontrado en ${WALLPAPER_DIR}/defoko-default.svg"
    # Crear enlace para aplicaciones GNOME/COSMIC que busquen fondos predeterminados
    mkdir -p /usr/share/backgrounds/pop
    ln -sf "${WALLPAPER_DIR}/defoko-default.svg" /usr/share/backgrounds/pop/defokos-default.svg || true
fi

log_step "4. Asegurando permisos en /etc/skel y dotfiles globales"
log_info "Ajustando permisos recursivos en /etc/skel para nuevos usuarios..."
chmod -R u=rwX,go=rX /etc/skel/

# Asegurar que los scripts y binarios en skel mantengan permisos de ejecución
find /etc/skel -type d -exec chmod 755 {} +
find /etc/skel -type f -name "*.sh" -exec chmod 755 {} +

log_step "5. Verificando integridad de sonidos del sistema"
if [ -d /usr/share/sounds/defokos ]; then
    log_info "Tema de sonidos DefokOS registrado en /usr/share/sounds/defokos"
    chmod -R 755 /usr/share/sounds/defokos
fi

log_step "6. Actualizando caché de iconos y temas GTK"
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    for dir in /usr/share/icons/*; do
        if [ -d "$dir" ] && [ -f "$dir/index.theme" ]; then
            gtk-update-icon-cache -f -q "$dir" 2>/dev/null || true
        fi
    done
fi

log_success "Personalización visual y branding de DefokOS aplicados exitosamente."
