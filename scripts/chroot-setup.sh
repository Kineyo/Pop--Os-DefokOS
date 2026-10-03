#!/usr/bin/env bash
# ==============================================================================
#  DEFOKOS // CHROOT PROVISIONING SCRIPT (chroot-setup.sh)
#  Ejecutado estrictamente dentro del entorno chroot durante la construcción.
# ==============================================================================

set -euo pipefail

# Definición de colores para salida en terminal
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_LAVENDER="\033[38;2;180;159;204m"
C_CYAN="\033[38;2;136;192;208m"
C_GREEN="\033[38;2;142;192;156m"
C_YELLOW="\033[38;2;222;193;138m"
C_RED="\033[38;2;216;124;149m"

log_info()    { echo -e "${C_BOLD}${C_LAVENDER}[DEFOKOS:INFO]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_success() { echo -e "${C_BOLD}${C_GREEN}[DEFOKOS:OK]${C_RESET} $*"; }
log_warn()    { echo -e "${C_BOLD}${C_YELLOW}[DEFOKOS:WARN]${C_RESET} $*"; }
log_err()     { echo -e "${C_BOLD}${C_RED}[DEFOKOS:ERROR]${C_RESET} $*" >&2; }

# Prevenir prompts interactivos
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

log_step "1. Verificando entorno chroot y conectividad de red"

# Asegurar directorios esenciales
mkdir -p /etc/apt/keyrings /etc/apt/sources.list.d /usr/share/keyrings

# Validación activa de DNS dentro del chroot
log_info "Comprobando resolución DNS dentro del chroot..."
if ! getent ahosts apt.pop-os.org >/dev/null 2>&1; then
    log_warn "Fallo en resolución DNS inicial dentro de chroot. Inyectando resolvedores públicos de respaldo..."
    cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# Soporte para binarios de 32-bit (Requerido para Steam y compatibilidad Wine)
log_info "Habilitando arquitectura i386 para compatibilidad de 32 bits..."
dpkg --add-architecture i386 || true

log_step "2. Configurando repositorios de software"

# Actualizar listas base
apt-get update -y

# Herramientas requeridas para gestión de llaves y repositorios
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Asegurar repositorios estándar habilitados
add-apt-repository -y universe || true
add-apt-repository -y multiverse || true
add-apt-repository -y restricted || true

# --- Repositorio VSCodium ---
log_info "Configurando repositorio oficial de VSCodium..."
if [ ! -f /etc/apt/keyrings/vscodium-archive-keyring.gpg ]; then
    VSC_KEY_URL1="https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"
    VSC_KEY_URL2="https://raw.githubusercontent.com/paulcarroty/vscodium-deb-rpm-repo/master/pub.gpg"
    
    if curl -fsSL --connect-timeout 10 "${VSC_KEY_URL1}" | gpg --dearmor -o /etc/apt/keyrings/vscodium-archive-keyring.gpg 2>/dev/null; then
        log_info "Llave de VSCodium obtenida exitosamente desde GitLab."
    elif curl -fsSL --connect-timeout 10 "${VSC_KEY_URL2}" | gpg --dearmor -o /etc/apt/keyrings/vscodium-archive-keyring.gpg 2>/dev/null; then
        log_info "Llave de VSCodium obtenida exitosamente desde mirror de GitHub."
    else
        log_warn "No se pudo obtener la llave GPG de VSCodium automáticamente."
    fi
fi
echo 'deb [ signed-by=/etc/apt/keyrings/vscodium-archive-keyring.gpg ] https://download.vscodium.com/debs vscodium main' \
    > /etc/apt/sources.list.d/vscodium.list

# --- Repositorio Fastfetch (en caso de base 22.04 donde no esté en repos principales) ---
if ! apt-cache show fastfetch >/dev/null 2>&1; then
    log_info "Añadiendo PPA para fastfetch..."
    add-apt-repository -y ppa:zhangsongcui3371/fastfetch || true
fi

# Actualizar índices de paquetes tras añadir nuevos repositorios
log_info "Actualizando índices APT tras añadir repositorios..."
apt-get update -y

log_step "3. Instalando paquetes principales del sistema"

# Lista de paquetes nativos esenciales
APT_PACKAGES=(
    # Emulador de terminal y utilidades CLI modernas
    kitty
    fastfetch
    htop
    btop
    neovim
    tmux
    git
    curl
    wget
    rsync
    ripgrep
    jq
    tree
    build-essential

    # Editor y desarrollo
    codium

    # Soporte AppImage sin conflictos (FUSE 2 + FUSE 3)
    # Ubuntu 24.04 utiliza libfuse2t64; Ubuntu 22.04 utiliza libfuse2
    fuse3

    # Audio profesional y síntesis de voz
    pavucontrol
    audacity
    sox
    ffmpeg
    ladspa-sdk

    # Gaming & runtime 32-bit
    steam-installer
)

# Detectar versión correcta de libfuse2 según la distribución base
if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2t64)
elif apt-cache show libfuse2 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2)
fi

# Añadir cosmic-store si está empaquetado en los repos de Pop!_OS
if apt-cache show cosmic-store >/dev/null 2>&1; then
    APT_PACKAGES+=(cosmic-store)
fi

log_info "Instalando paquetes: ${APT_PACKAGES[*]}"
apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"

log_step "4. Configurando soporte Flatpak y Flathub"

apt-get install -y --no-install-recommends flatpak

# Habilitar Flathub a nivel de sistema
log_info "Añadiendo repositorio Flathub a nivel de sistema..."
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Pre-instalación de aplicaciones Flatpak seleccionadas
# Discord es distribuido principalmente via Flatpak en distribuciones modernas
log_info "Instalando Discord via Flatpak (system-wide)..."
flatpak install --system -y --noninteractive flathub com.discordapp.Discord || {
    log_warn "No se pudo pre-descargar Discord Flatpak dentro del chroot (red o namespace restringido)."
    log_warn "El repositorio Flathub queda habilitado para instalación en primer arranque."
}

log_step "5. Optimizaciones para AppImages y binarios portables"

# Asegurar permisos correctos para montajes FUSE en usuarios no-root
if [ -f /etc/fuse.conf ]; then
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf || true
fi

log_step "6. Limpieza profunda para reducir el tamaño de la imagen final"

# Eliminar paquetes obsoletos o innecesarios
log_info "Ejecutando autoremove y clean..."
apt-get autoremove -y --purge
apt-get autoclean -y
apt-get clean -y

# Eliminar archivos temporales y cachés
log_info "Borrando cachés de paquetes y listas APT..."
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*-old
find /var/log -type f -exec truncate -s 0 {} +

# Truncar machine-id para que systemd regenere un ID único en el primer arranque
log_info "Restableciendo machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

log_success "Aprovisionamiento dentro del chroot completado con éxito."
