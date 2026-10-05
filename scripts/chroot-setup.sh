#!/usr/bin/env bash
# ==============================================================================
# DEFOKOS LINUX // CHROOT PROVISIONING SCRIPT (chroot-setup.sh)
# Ecosistema Pop!_OS 24.04 LTS (Noble) // COSMIC Desktop // Repositorios Oficiales
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Evitar prompts de conffiles (p.ej. /etc/casper.conf del overlay) conservando la versión del overlay
cat > /etc/apt/apt.conf.d/99defokos-noninteractive << 'APTCONF_EOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APTCONF_EOF

echo "[CHROOT] === Configurando arquitectura i386 para soporte multilib (Steam) ==="
dpkg --add-architecture i386 || true

echo "[CHROOT] === Instalando y verificando paquetes base de red y criptografía ==="
apt-get update -y || true
apt-get install -y --no-install-recommends ca-certificates curl gnupg gpg dirmngr lsb-release software-properties-common

# ==============================================================================
# 1. CONFIGURACIÓN DE REPOSITORIOS OFICIALES POP!_OS Y FIRMAS GPG
# ==============================================================================
echo "[CHROOT] === Configurando repositorios oficiales y llaves GPG de Pop!_OS ==="

mkdir -p /etc/apt/trusted.gpg.d /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d /etc/apt/apt.conf.d

# Llave Pop!_OS Archive (2017)
# Fingerprint: 63C46DF0140D738961429F4E204DD8AEC33A7AFF
POP_KEY_PATH="/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg"
if [ ! -s "${POP_KEY_PATH}" ] || [ $(stat -c%s "${POP_KEY_PATH}" 2>/dev/null || echo 0) -lt 500 ]; then
    echo "[CHROOT] Obteniendo llave oficial de Pop!_OS desde keyserver..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x63C46DF0140D738961429F4E204DD8AEC33A7AFF" | gpg --dearmor -o "${POP_KEY_PATH}" || true
fi
cp -f "${POP_KEY_PATH}" /usr/share/keyrings/pop-archive-keyring.gpg 2>/dev/null || true
chmod 644 "${POP_KEY_PATH}" /usr/share/keyrings/pop-archive-keyring.gpg 2>/dev/null || true

# Llave Ubuntu Archive (2018)
# Fingerprint: F6ECB3762474EDA9D21B7022871920D1991BC93C / 871920D1991BC93C
UBUNTU_KEY_PATH="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
if [ ! -s "${UBUNTU_KEY_PATH}" ] || [ $(stat -c%s "${UBUNTU_KEY_PATH}" 2>/dev/null || echo 0) -lt 500 ]; then
    echo "[CHROOT] Obteniendo llave oficial de Ubuntu desde keyserver..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x871920D1991BC93C" | gpg --dearmor -o "${UBUNTU_KEY_PATH}" || true
fi
cp -f "${UBUNTU_KEY_PATH}" /usr/share/keyrings/ubuntu-archive-keyring.gpg 2>/dev/null || true
chmod 644 "${UBUNTU_KEY_PATH}" /usr/share/keyrings/ubuntu-archive-keyring.gpg 2>/dev/null || true

# Limpiar /etc/apt/sources.list tradicional y archivos antiguos para evitar fuentes duplicadas
echo "# Repositories managed in /etc/apt/sources.list.d/*.sources" > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/system76.sources /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true

# Configurar fuentes oficiales de Pop!_OS formato deb822
cat << 'EOF' > /etc/apt/sources.list.d/pop-os-apps.sources
X-Repolib-Name: Pop_OS Applications
Enabled: yes
Types: deb
URIs: http://apt.pop-os.org/proprietary
Suites: noble
Components: main
Signed-By: /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg
EOF

cat << 'EOF' > /etc/apt/sources.list.d/pop-os-release.sources
X-Repolib-Name: Pop_OS Release Sources
Enabled: yes
Types: deb deb-src
URIs: http://apt.pop-os.org/release
Suites: noble
Components: main
Signed-By: /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg
EOF

cat << 'EOF' > /etc/apt/sources.list.d/system.sources
X-Repolib-Name: Pop_OS System Sources
Enabled: yes
Types: deb deb-src
URIs: http://apt.pop-os.org/ubuntu
Suites: noble noble-security noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg
X-Repolib-ID: system
X-Repolib-Default-Mirror: http://apt.pop-os.org/ubuntu
EOF

chmod 644 /etc/apt/sources.list.d/*.sources 2>/dev/null || true

# Pinning prioritario de Pop!_OS (o=pop-os-release -> Pin-Priority 1001)
cat << 'EOF' > /etc/apt/preferences.d/pop-default-settings
Package: *
Pin: release o=pop-os-release
Pin-Priority: 1001
EOF
chmod 644 /etc/apt/preferences.d/pop-default-settings

# Configuración de Phased-Updates para Pop!_OS
cat << 'EOF' > /etc/apt/apt.conf.d/76pop-default-settings
APT::Get::Always-Include-Phased-Updates "true";
EOF
chmod 644 /etc/apt/apt.conf.d/76pop-default-settings

# Vincular plantillas oficiales de Pop!_OS para aptsources / python-apt
mkdir -p /usr/share/python-apt/templates
ln -sf Ubuntu.info /usr/share/python-apt/templates/Pop.info 2>/dev/null || true
ln -sf Ubuntu.mirrors /usr/share/python-apt/templates/Pop.mirrors 2>/dev/null || true

# Repositorio Fastfetch (PPA directo vía list/gpg)
if [ ! -f /etc/apt/sources.list.d/fastfetch.list ]; then
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/fastfetch.gpg] https://ppa.launchpadcontent.net/zhangsongcui3371/fastfetch/ubuntu noble main" > /etc/apt/sources.list.d/fastfetch.list
    curl -fsSL --connect-timeout 10 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x83A1440263673F60" | gpg --dearmor -o /etc/apt/trusted.gpg.d/fastfetch.gpg 2>/dev/null || true
fi

# Actualización limpia y desatendida de repositorios APT
echo "[CHROOT] Ejecutando apt-get update limpio e ininterrumpido..."
apt-get clean
if ! apt-get update -y; then
    echo "[CHROOT:WARN] apt-get update falló; se elimina el repositorio externo de Fastfetch y se reintenta..."
    rm -f /etc/apt/sources.list.d/fastfetch.list /etc/apt/trusted.gpg.d/fastfetch.gpg
    apt-get update -y
fi

if ! apt-cache show pop-de-cosmic >/dev/null 2>&1; then
    echo "[CHROOT:WARN] pop-de-cosmic no detectado de inmediato. Reintentando actualización con fix-missing..."
    apt-get update -y --fix-missing || true
fi

# Desinstalar bloatware no deseado
echo "[CHROOT] Purgando thunderbird, popsicle, xterm, gnome-terminal..."
apt-get purge -y thunderbird 'thunderbird-locale-*' popsicle popsicle-gtk xterm gnome-terminal gnome-terminal-data || true
rm -f /usr/share/applications/thunderbird.desktop /usr/share/applications/popsicle*.desktop /usr/share/applications/*xterm*.desktop /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true

# ==============================================================================
# 2. INSTALACIÓN DE COMPONENTES DEL SISTEMA, COSMIC DESKTOP Y DEPENDENCIAS
# ==============================================================================
APT_PACKAGES=(
    # Núcleo del sistema y soporte Live Boot
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
    firefox

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

    # Pila de Audio: Pipewire y PulseAudio
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

    # Herramientas de arranque y particionado
    grub-pc-bin
    grub-efi-amd64-bin
    grub-common
    shim-signed
    mtools
    dosfstools

    # Instalador universal independiente
    calamares
    calamares-settings-ubuntu-common
    gparted
    x11-xserver-utils
    policykit-1-gnome

    # Terminal y utilidades modernas
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
    fuse3

    # Librerías y dependencias runtime compartidas para Steam, Discord, Codium y YouTube Music
    libasound2t64
    libasound2-plugins
    libatk1.0-0t64
    libatk-bridge2.0-0t64
    libatspi0t64
    libatomic1
    libcairo2
    libdbus-1-3
    libexpat1
    libgbm1
    libglib2.0-0t64
    libgtk-3-0t64
    libnotify4
    libnspr4
    libnss3
    libpango-1.0-0
    libstdc++6
    libudev1
    libx11-6
    libxcb1
    libxcb-dri3-0
    libxcomposite1
    libxdamage1
    libxext6
    libxfixes3
    libxkbcommon0
    libxrandr2
    libxtst6
    libsecret-1-0
    xdg-utils
    xdg-user-dirs
    zenity
    xz-utils
    lsof
)

# Compatibilidad para nombres de paquetes legacy vs t64 (noble)
for fallback_pkg in libasound2 libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 libglib2.0-0 libgtk-3-0 libfuse2t64 libfuse2; do
    if apt-cache show "$fallback_pkg" >/dev/null 2>&1; then
        APT_PACKAGES+=("$fallback_pkg")
    fi
done

INSTALLABLE=()
for pkg in "${APT_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        INSTALLABLE+=("$pkg")
    fi
done

echo "[CHROOT] Instalando componentes principales (${#INSTALLABLE[@]} paquetes)..."
apt-get install -y --no-install-recommends "${INSTALLABLE[@]}" || {
    echo "[CHROOT:WARN] Ejecutando instalación resiliente paquete por paquete..."
    for pkg in "${INSTALLABLE[@]}"; do
        apt-get install -y --no-install-recommends "$pkg" || true
    done
    apt-get install -f -y --no-install-recommends || true
}

# Gráficos 32-bit para Steam
apt-get install -y --no-install-recommends libvulkan1:i386 mesa-vulkan-drivers:i386 || true

# Verificación: apt-cache puede omitir paquetes silenciosamente; abortar si falta algo esencial
for essential_pkg in linux-generic casper calamares pop-de-cosmic cosmic-greeter; do
    if ! dpkg -s "${essential_pkg}" >/dev/null 2>&1; then
        echo "[CHROOT:ERROR] Paquete esencial no instalado: ${essential_pkg}" >&2
        exit 1
    fi
done
for optional_pkg in firefox fastfetch kitty; do
    if ! dpkg -s "${optional_pkg}" >/dev/null 2>&1; then
        echo "[CHROOT:WARN] Paquete opcional no instalado: ${optional_pkg}"
    fi
done
if [ ! -x /usr/lib/firefox/firefox ]; then
    echo "[CHROOT:WARN] Firefox no está disponible como .deb (en Ubuntu noble puede ser un paquete snap)."
    echo "[CHROOT:WARN] La política de PreMiD no tendrá efecto; considera instalar org.mozilla.firefox vía Flatpak."
fi

# Asegurar que existan los grupos secundarios (useradd falla si falta alguno)
for grp in render input plugdev netdev lpadmin; do
    getent group "$grp" >/dev/null 2>&1 || groupadd -r "$grp" || true
done

# Configuración de usuario Live defokos
if ! id defokos >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,render,input,plugdev,netdev defokos || true
    echo "defokos:defokos" | chpasswd || true
    echo "defokos ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/defokos
    chmod 0440 /etc/sudoers.d/defokos
else
    usermod -aG sudo,audio,video,render,input,plugdev,netdev defokos || true
fi

# Copiar acceso directo al instalador en el Escritorio del usuario Live
mkdir -p /home/defokos/Desktop
rm -f /etc/skel/Desktop/install-defokos.desktop 2>/dev/null || true
if [ -f /usr/share/applications/io.calamares.calamares.desktop ]; then
    cp -f /usr/share/applications/io.calamares.calamares.desktop /home/defokos/Desktop/install-defokos.desktop
    chmod +x /home/defokos/Desktop/install-defokos.desktop 2>/dev/null || true
    chown -R defokos:defokos /home/defokos/Desktop 2>/dev/null || true
fi
chmod +x /usr/local/bin/calamares-launch 2>/dev/null || true

# Configuración de Casper para Live Boot y Hostname
cat << 'EOCASPER' > /etc/casper.conf
export USERNAME="defokos"
export USERFULLNAME="DefokOS Live User"
export HOST="defokos"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="DefokOS"
EOCASPER

echo "defokos" > /etc/hostname
cp -f /etc/os-release /usr/lib/os-release 2>/dev/null || true

# Instalar y habilitar display manager
systemctl enable cosmic-greeter.service 2>/dev/null || true
systemctl set-default graphical.target 2>/dev/null || true

# ==============================================================================
# 3. VERIFICACIÓN DE PAQUETES LOCALES Y CONFIGURACIÓN DE HOOKS DE INSTALADOR
# ==============================================================================
echo "[CHROOT] === Verificando directorio de paquetes locales /opt/defokos-installer/debs/ ==="
mkdir -p /opt/defokos-installer/debs
chmod 755 /opt/defokos-installer /opt/defokos-installer/debs

if compgen -G "/opt/defokos-installer/debs/*.deb" > /dev/null; then
    chmod 644 /opt/defokos-installer/debs/*.deb
    echo "[CHROOT] Paquetes locales listos en /opt/defokos-installer/debs:"
    ls -lh /opt/defokos-installer/debs/
else
    echo "[CHROOT:WARN] /opt/defokos-installer/debs no contiene archivos .deb todavía (se sincronizarán desde el host)."
fi

# Asegurar script post-instalación en /opt/defokos-installer/post-install.sh
cat << 'EOFPOST' > /opt/defokos-installer/post-install.sh
#!/usr/bin/env bash
# ==============================================================================
# DefokOS - Hook de Post-Instalación en Disco Destino (Chroot)
# Ejecución desatendida para instalación de software local y purga limpia
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

INSTALLER_DIR="/opt/defokos-installer"
DEBS_DIR="${INSTALLER_DIR}/debs"

echo "[DEFOKOS:POSTINST] Iniciando post-instalación desatendida en disco destino..."

# Habilitar soporte multilib por compatibilidad
dpkg --add-architecture i386 2>/dev/null || true

# 1. Instalar los 4 programas usando dpkg -i /opt/defokos-installer/debs/*.deb
if [ -d "${DEBS_DIR}" ] && compgen -G "${DEBS_DIR}/*.deb" > /dev/null; then
    echo "[DEFOKOS:POSTINST] Instalando paquetes locales con dpkg..."
    dpkg --force-confdef --force-confold -i "${DEBS_DIR}"/*.deb || true

    # 2. Forzar la resolución de dependencias con apt-get install -f -y
    echo "[DEFOKOS:POSTINST] Forzando resolución de dependencias con apt-get install -f -y..."
    apt-get update -y || true
    apt-get install -f -y || echo "[DEFOKOS:POSTINST] WARN: apt-get install -f falló (¿sin red?)"
else
    echo "[DEFOKOS:POSTINST] No se encontraron paquetes .deb para instalar."
fi

# 3. Purga destructiva de /opt/defokos-installer/debs/
echo "[DEFOKOS:POSTINST] Ejecutando purga destructiva de paquetes temporales..."
rm -rf "${DEBS_DIR}"
rm -rf "${INSTALLER_DIR}" 2>/dev/null || true

# 4. Eliminar cachés (apt-get clean, apt-get autoremove -y)
echo "[DEFOKOS:POSTINST] Limpiando cachés de APT y paquetes huérfanos..."
apt-get autoremove -y --purge || true
apt-get clean -y || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /var/cache/apt/*.bin /tmp/* /var/tmp/* 2>/dev/null || true

# 5. Borrar logs temporales para no dejar rastro
echo "[DEFOKOS:POSTINST] Eliminando logs temporales..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} + 2>/dev/null || true
rm -f /var/log/dpkg.log* /var/log/apt/* /var/log/defokos*.log 2>/dev/null || true

# 6. Limpiar artefactos de la sesión Live que NO deben quedar en el sistema instalado
echo "[DEFOKOS:POSTINST] Eliminando artefactos de la sesión Live..."
rm -f /etc/sudoers.d/defokos 2>/dev/null || true
rm -f /etc/xdg/autostart/io.calamares.calamares.desktop /usr/share/applications/io.calamares.calamares.desktop 2>/dev/null || true
rm -f /home/*/Desktop/install-defokos.desktop /etc/skel/Desktop/install-defokos.desktop 2>/dev/null || true
for fav in /usr/share/cosmic/com.system76.CosmicAppList/v1/favorites \
           /etc/skel/.config/cosmic/com.system76.CosmicAppList/v1/favorites \
           /home/*/.config/cosmic/com.system76.CosmicAppList/v1/favorites; do
    if [ -f "$fav" ]; then sed -i '/"io.calamares.calamares"/d' "$fav" 2>/dev/null || true; fi
done
# El autologin del usuario Live (initial_session) impediría iniciar sesión en el sistema instalado
if [ -f /etc/greetd/cosmic-greeter.toml ]; then
    sed -i '/^\[initial_session\]/,/^$/d' /etc/greetd/cosmic-greeter.toml 2>/dev/null || true
fi
# Eliminar el usuario Live (defokos:defokos) solo si existe otro usuario normal
if id defokos >/dev/null 2>&1; then
    OTHER_USERS="$(getent passwd | awk -F: '$3>=1000 && $3<60000 && $1!="defokos" {print $1}')"
    if [ -n "${OTHER_USERS}" ]; then
        userdel -r defokos 2>/dev/null || true
    fi
fi

# Desactivar y remover servicio de primera ejecución si existiera
systemctl disable defokos-postinstall.service 2>/dev/null || true
rm -f /etc/systemd/system/defokos-postinstall.service 2>/dev/null || true

echo "[DEFOKOS:POSTINST] Instalación de software completada y sistema 100% limpio."
exit 0
EOFPOST
chmod 755 /opt/defokos-installer/post-install.sh

# Integración con Pop!_OS distinst hooks (chroot hook automático)
mkdir -p /usr/lib/distinst/hooks/post-install /etc/distinst/hooks/post-install
cat << 'EOFDISTINST' > /usr/lib/distinst/hooks/post-install/99-defokos-postinstall
#!/bin/bash
if [ -x /opt/defokos-installer/post-install.sh ]; then
    /bin/bash /opt/defokos-installer/post-install.sh
fi
EOFDISTINST
chmod +x /usr/lib/distinst/hooks/post-install/99-defokos-postinstall
cp -f /usr/lib/distinst/hooks/post-install/99-defokos-postinstall /etc/distinst/hooks/post-install/99-defokos-postinstall

# Integración con Ubiquity / Casper hooks
mkdir -p /usr/lib/ubiquity/target-config
cat << 'EOFUBI' > /usr/lib/ubiquity/target-config/99-defokos-postinstall
#!/bin/bash
if [ -x /opt/defokos-installer/post-install.sh ]; then
    /bin/bash /opt/defokos-installer/post-install.sh
fi
EOFUBI
chmod +x /usr/lib/ubiquity/target-config/99-defokos-postinstall

# Servicio systemd de contingencia en caso de instalador sin soporte directo de hooks
cat << 'EOFSRV' > /etc/systemd/system/defokos-postinstall.service
[Unit]
Description=DefokOS Target Disk Post-Install Setup
ConditionPathExists=/opt/defokos-installer/debs
ConditionKernelCommandLine=!boot=casper
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/defokos-installer/post-install.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOFSRV
systemctl enable defokos-postinstall.service 2>/dev/null || true

# Soporte Flatpak base
apt-get install -y --no-install-recommends flatpak || true
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak uninstall --system -y com.discordapp.Discord 2>/dev/null || true

# Permisos extensión PreMiD
for ext in "/usr/lib/firefox/browser/extensions/support@premid.app.xpi" "/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi"; do
    if [[ -f "$ext" ]]; then chmod 644 "$ext" || true; fi
done

# ==============================================================================
# 4. LIMPIEZA PROFUNDA DE BUILD-TIME (PRESERVANDO /opt/defokos-installer)
# ==============================================================================
echo "[CHROOT] Asegurando soporte overlayfs en initramfs-tools..."
mkdir -p /etc/initramfs-tools
if ! grep -q "^overlay" /etc/initramfs-tools/modules 2>/dev/null; then
    echo "overlay" >> /etc/initramfs-tools/modules
fi

if [ -f /usr/share/initramfs-tools/scripts/casper-helpers ]; then
    sed -i 's/\[ "${BUILD_SYSTEM}" = "Debian" \] || \[ "${BUILD_SYSTEM}" = "Ubuntu" \]/[ "${BUILD_SYSTEM}" = "Debian" ] || [ "${BUILD_SYSTEM}" = "Ubuntu" ] || [ "${BUILD_SYSTEM}" = "DefokOS" ]/g' /usr/share/initramfs-tools/scripts/casper-helpers || true
fi

echo "[CHROOT] Generando initramfs de arranque Live (Casper) para los kernels instalados..."
dpkg --configure -a || true
for kver in $(ls -1 /lib/modules 2>/dev/null); do
    echo "[CHROOT] Compilando initramfs para kernel ${kver}..."
    if [ ! -f "/boot/initrd.img-${kver}" ]; then
        update-initramfs -c -k "${kver}" || update-initramfs -u -k "${kver}" || true
    else
        update-initramfs -u -k "${kver}" || true
    fi
done
if ! ls /boot/initrd.img-* >/dev/null 2>&1; then
    echo "[CHROOT] Forzando creación general de initramfs (update-initramfs -c -k all)..."
    update-initramfs -c -k all || true
fi
LATEST_KIMG=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1 || true)
if [ -n "${LATEST_KIMG}" ]; then
    KVER="${LATEST_KIMG##*/vmlinuz-}"
    ln -sf "vmlinuz-${KVER}" /boot/vmlinuz
    if [ -f "/boot/initrd.img-${KVER}" ]; then
        ln -sf "initrd.img-${KVER}" /boot/initrd.img
    fi
fi

echo "[CHROOT] Optimizando y limpiando cachés del entorno base para compresión compacta..."
rm -rf /var/lib/flatpak/runtime/* /var/lib/flatpak/app/* /var/lib/flatpak/.removed/* 2>/dev/null || true
apt-get autoremove -y --purge || true
apt-get clean -y || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /root/.cache/* /home/*/.cache/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true

rm -f /etc/apt/apt.conf.d/99defokos-noninteractive
echo "[CHROOT] Aprovisionamiento completado con éxito."
