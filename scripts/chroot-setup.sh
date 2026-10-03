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

# --- Repositorio System76 / Pop!_OS ---
log_info "Verificando repositorios oficiales de System76 y Pop!_OS..."
if [ ! -f /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg ]; then
    mkdir -p /etc/apt/trusted.gpg.d
    curl -fsSL "https://apt.pop-os.org/proprietary/archive.key" | gpg --dearmor -o /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg 2>/dev/null || true
fi
if [ ! -f /etc/apt/sources.list.d/system76.sources ]; then
    cat << 'EOF' > /etc/apt/sources.list.d/system76.sources
X-Repolib-Name: Pop_OS Applications
Enabled: yes
Types: deb
URIs: http://apt.pop-os.org/proprietary
Suites: noble
Components: main
Signed-By: /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg

X-Repolib-Name: Pop_OS Release Sources
Enabled: yes
Types: deb
URIs: http://apt.pop-os.org/release
Suites: noble
Components: main
Signed-By: /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg

X-Repolib-Name: Pop_OS System Sources
Enabled: yes
Types: deb
URIs: http://apt.pop-os.org/ubuntu
Suites: noble noble-security noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg
EOF
fi

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

log_step "3. Desinstalando aplicaciones preinstaladas no deseadas"
log_info "Purgando Thunderbird, Popsicle, xterm y gnome-terminal..."
apt-get purge -y \
    thunderbird \
    'thunderbird-locale-*' \
    popsicle \
    popsicle-gtk \
    xterm \
    gnome-terminal \
    gnome-terminal-data || true

# Limpiar archivos de escritorio y accesos residuales
rm -f /usr/share/applications/thunderbird.desktop \
      /usr/share/applications/popsicle*.desktop \
      /usr/share/applications/*xterm*.desktop \
      /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true

log_step "4. Instalando paquetes principales del sistema"

# Lista de paquetes nativos esenciales
APT_PACKAGES=(
    # Núcleo del sistema y soporte Live ISO
    linux-generic
    casper
    systemd
    systemd-sysv
    udev
    sudo
    locales
    network-manager
    net-tools

    # Entorno COSMIC Desktop nativo (System76)
    pop-de-cosmic
    cosmic-session
    cosmic-store
    cosmic-term
    cosmic-edit
    cosmic-files
    cosmic-greeter
    cosmic-app-library

    # Pila Gráfica: Mesa, Vulkan y OpenGL
    mesa-vulkan-drivers
    mesa-utils
    vulkan-tools
    libvulkan1
    libgl1-mesa-dri
    libgl1
    libglu1-mesa
    libegl-mesa0
    libglx-mesa0

    # Pila de Audio: Pipewire y compatibilidad PulseAudio
    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-audio-client-libraries
    wireplumber
    pulseaudio-utils
    pavucontrol
    audacity
    sox
    ffmpeg
    ladspa-sdk

    # Instalador de sistema universal independiente
    calamares
    calamares-settings-ubuntu-common

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
)

# Detectar versión correcta de libfuse2 según la distribución base
if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2t64)
elif apt-cache show libfuse2 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2)
fi

# Filtrar paquetes disponibles en los repositorios
INSTALLABLE_PACKAGES=()
for pkg in "${APT_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        INSTALLABLE_PACKAGES+=("$pkg")
    else
        log_warn "Paquete no encontrado en repositorios APT: $pkg (omitiendo...)"
    fi
done

log_info "Instalando paquetes principales (${#INSTALLABLE_PACKAGES[@]} paquetes detectados)..."
apt-get install -y --no-install-recommends "${INSTALLABLE_PACKAGES[@]}" || {
    log_warn "Error en instalación masiva. Ejecutando instalación individual con resolución de dependencias..."
    for pkg in "${INSTALLABLE_PACKAGES[@]}"; do
        apt-get install -y --no-install-recommends "$pkg" || log_warn "No se pudo instalar $pkg"
    done
    apt-get install -f -y --no-install-recommends || true
}

# Instalar librerías gráficas de 32 bits para gaming y Steam si i386 está habilitado
log_info "Instalando soporte Vulkan/Mesa de 32 bits para Steam..."
apt-get install -y --no-install-recommends libvulkan1:i386 mesa-vulkan-drivers:i386 || true

# Configuración de usuario Live defokos
if ! id defokos >/dev/null 2>&1; then
    log_info "Configurando usuario live 'defokos' con privilegios sudo..."
    useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev defokos || true
    echo "defokos:defokos" | chpasswd || true
    echo "defokos ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/defokos
    chmod 0440 /etc/sudoers.d/defokos
fi

log_step "5. Instalando paquetes .deb nativos (YouTube Music, Discord, Steam)"

DEBS_DIR="/opt/defokos-packages"
mkdir -p "${DEBS_DIR}"

# 1. YouTube Music Desktop App
if ! ls "${DEBS_DIR}"/youtube-music*.deb >/dev/null 2>&1; then
    log_info "Descargando YouTube Music Desktop .deb oficial..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/youtube-music.deb" \
        "https://github.com/ytmdesktop/ytmdesktop/releases/download/v2.0.12/youtube-music-desktop-app_2.0.12_amd64.deb" || true
fi

# 2. Discord .deb
if ! ls "${DEBS_DIR}"/discord*.deb >/dev/null 2>&1; then
    log_info "Descargando Discord .deb oficial..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/discord.deb" \
        "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=linux&arch=x64&format=deb" || true
fi

# 3. Steam .deb
if ! ls "${DEBS_DIR}"/steam*.deb >/dev/null 2>&1; then
    log_info "Descargando Steam .deb oficial..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/steam.deb" \
        "https://cdn.fastly.steamstatic.com/client/installer/steam.deb" || true
fi

# Instalación de paquetes .deb presentes en DEBS_DIR
for deb_file in "${DEBS_DIR}"/*.deb; do
    if [[ -f "${deb_file}" ]]; then
        log_info "Instalando paquete: $(basename "${deb_file}")..."
        apt-get install -y --no-install-recommends "${deb_file}" || {
            log_warn "Resolviendo dependencias para $(basename "${deb_file}")..."
            apt-get install -f -y --no-install-recommends
        }
    fi
done

# Limpieza de paquetes deb temporales
rm -rf "${DEBS_DIR}"

log_step "6. Configurando soporte Flatpak y Flathub"

apt-get install -y --no-install-recommends flatpak

# Habilitar Flathub a nivel de sistema
log_info "Añadiendo repositorio Flathub a nivel de sistema..."
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Si Discord fue instalado anteriormente via Flatpak, removerlo para usar la versión deb nativa
if command -v flatpak >/dev/null 2>&1; then
    flatpak uninstall --system -y com.discordapp.Discord 2>/dev/null || true
fi

log_step "7. Configurando extensión PreMiD para Mozilla Firefox"

# Asegurar permisos correctos en extensiones y políticas de Firefox
for ext_path in \
    "/usr/lib/firefox/browser/extensions/support@premid.app.xpi" \
    "/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi" \
    "/etc/firefox/policies/policies.json" \
    "/usr/lib/firefox/distribution/policies.json"; do
    if [[ -f "${ext_path}" ]]; then
        chmod 644 "${ext_path}" 2>/dev/null || true
        log_info "Registrado archivo de Firefox: ${ext_path}"
    fi
done

log_step "8. Optimizaciones para AppImages y binarios portables"

# Asegurar permisos correctos para montajes FUSE en usuarios no-root
if [ -f /etc/fuse.conf ]; then
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf || true
fi

log_step "9. Limpieza profunda para reducir el tamaño de la imagen final"

# Eliminar paquetes obsoletos o innecesarios
log_info "Ejecutando autoremove y clean..."
apt-get autoremove -y --purge
apt-get autoclean -y
apt-get clean -y

# Purgar runtimes residuales de Flatpak no utilizados (garantiza que SquashFS quepa en los 4GB de la partición /recovery)
log_info "Limpiando cachés y runtimes residuales de Flatpak..."
rm -rf /var/lib/flatpak/runtime/* /var/lib/flatpak/app/* /var/lib/flatpak/.removed/* 2>/dev/null || true

# Eliminar archivos temporales y cachés preservando directorios de construcción
log_info "Borrando cachés de paquetes y listas APT..."
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*
rm -rf /var/cache/debconf/*-old
rm -rf /var/cache/fontconfig/*
rm -rf /var/cache/man/*
rm -rf /root/.cache/* /home/*/.cache/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} +

# Limpieza segura de /tmp y /var/tmp sin tocar scripts en ejecución
find /tmp -mindepth 1 -maxdepth 1 ! -name 'scripts' ! -name 'defokos*' -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

# Truncar machine-id para que systemd regenere un ID único en el primer arranque
log_info "Restableciendo machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

log_success "Aprovisionamiento dentro del chroot completado con éxito."
