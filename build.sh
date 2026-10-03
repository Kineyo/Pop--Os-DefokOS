#!/usr/bin/env bash
# ==============================================================================
#  DEFOKOS LINUX // MASTER BUILD ORCHESTRATOR (build.sh)
#  Edición: Utane Uta // Base: Pop!_OS 24.04 LTS (Noble) // COSMIC Desktop Wayland
#  Paleta: Lavanda (#b49fcc) & Pizarra Oscura (#24272e)
# ==============================================================================

set -euo pipefail

# --- Definición de Colores ---
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_LAVENDER="\033[38;2;180;159;204m"
C_CHARCOAL="\033[38;2;36;39;46m"
C_CYAN="\033[38;2;136;192;208m"
C_GREEN="\033[38;2;142;192;156m"
C_YELLOW="\033[38;2;222;193;138m"
C_RED="\033[38;2;216;124;149m"

log_info()    { echo -e "${C_BOLD}${C_LAVENDER}[DEFOKOS:INFO]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_success() { echo -e "${C_BOLD}${C_GREEN}[DEFOKOS:OK]${C_RESET} $*"; }
log_warn()    { echo -e "${C_BOLD}${C_YELLOW}[DEFOKOS:WARN]${C_RESET} $*"; }
log_err()     { echo -e "${C_BOLD}${C_RED}[DEFOKOS:ERROR]${C_RESET} $*" >&2; }

log_banner() {
    echo -e "${C_BOLD}${C_LAVENDER}"
    cat << "EOF"
======================================================================
  ____       __       _    ___  ____  
 |  _ \  ___/ _| ___ | | _/ _ \/ ___| 
 | | | |/ _ \ |_ / _ \| |/ / | \___ \ 
 | |_| |  __/  _| (_) |   <| |_| |__) |
 |____/ \___|_|  \___/|_|\_\\___/|____/ 
  Utane Uta Edition // COSMIC Desktop // Pop!_OS 24.04 LTS Noble
======================================================================
EOF
    echo -e "${C_RESET}"
}

# --- Ayuda preliminar sin requerir sudo ---
if [[ " $* " =~ " --help " ]] || [[ " $* " =~ " -h " ]]; then
    echo "Uso: sudo $0 [--clean] [--bootstrap] [--repack] [--pack-only] [--iso /ruta/a/base.iso]"
    echo ""
    echo "Opciones:"
    echo "  --clean                 Elimina completamente la base anterior para una reconstrucción 100% limpia"
    echo "  --bootstrap             Construye el sistema desde cero vía debootstrap y repositorios oficiales System76"
    echo "  --repack                Aplica overlay al chroot existente y recomprime SquashFS e ISO (~2-3 min)"
    echo "  --pack-only             Omite aprovisionamiento y SquashFS; empaqueta la ISO directamente (~10 seg)"
    echo "  --iso /ruta/a/base.iso  Usa una imagen base local existente"
    echo ""
    echo "Variables de entorno opcionales:"
    echo "  BASE_ISO_URL    URL para descargar la ISO base si no se especifica --iso ni --bootstrap"
    echo "  COMPRESSION     Algoritmo de compresión para squashfs (zstd o xz, por defecto: zstd)"
    exit 0
fi

# --- Verificación de Privilegios Root ---
if [[ "${EUID}" -ne 0 ]]; then
    log_warn "Elevando privilegios a superusuario (root)..."
    exec sudo "$0" "$@"
fi

# --- Variables y Rutas del Proyecto ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROJECT_ROOT}/work"
OUT_DIR="${PROJECT_ROOT}/out"
OVERLAY_DIR="${PROJECT_ROOT}/overlay"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
ASSETS_DIR="${PROJECT_ROOT}/assets"
DEBS_DIR="${PROJECT_ROOT}/debs"

ISO_MOUNT_DIR="${WORK_DIR}/iso_mount"
ISO_EXTRACT_DIR="${WORK_DIR}/iso_extracted"
CHROOT_DIR="${WORK_DIR}/squashfs_root"

# URL oficial de Pop!_OS 24.04 LTS COSMIC Desktop (Wayland)
DEFAULT_BASE_URL="https://iso.pop-os.org/24.04/amd64/generic/28/pop-os_24.04_amd64_generic_28.iso"
BASE_ISO_URL="${BASE_ISO_URL:-${DEFAULT_BASE_URL}}"

# Nombre de la ISO resultante
DATE_TAG="$(date +%Y%m%d)"
DEFOKOS_VERSION="24.04"
ISO_OUTPUT_NAME="DefokOS-${DEFOKOS_VERSION}-amd64-${DATE_TAG}.iso"
VOLUME_LABEL="DEFOKOS_24_04"

# Parámetros y banderas inicializadas
LOCAL_BASE_ISO=""
BOOTSTRAP=false
PACK_ONLY=false
REPACK=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=true
            shift
            ;;
        --bootstrap)
            BOOTSTRAP=true
            shift
            ;;
        --iso)
            LOCAL_BASE_ISO="$2"
            shift 2
            ;;
        --pack-only)
            PACK_ONLY=true
            shift
            ;;
        --repack)
            REPACK=true
            shift
            ;;
        *)
            log_err "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

COMPRESSION="${COMPRESSION:-zstd}"

# Auto-detección de la ISO oficial local de Pop!_OS 24.04
REAL_USER="${SUDO_USER:-${USER}}"
if [[ -z "${LOCAL_BASE_ISO}" ]]; then
    for candidate_iso in \
        "/home/alex/Descargas/pop-os_24.04_amd64_generic_28.iso" \
        "/home/${REAL_USER}/Descargas/pop-os_24.04_amd64_generic_28.iso" \
        "/home/${REAL_USER}/Descargas/pop-os_24.04"*.iso \
        "/home/${REAL_USER}/Downloads/pop-os_24.04"*.iso \
        "${HOME}/Descargas/pop-os_24.04"*.iso \
        "${HOME}/Downloads/pop-os_24.04"*.iso; do
        if [[ -f "${candidate_iso}" ]]; then
            LOCAL_BASE_ISO="${candidate_iso}"
            log_info "Auto-detectada imagen base local de Pop!_OS 24.04: ${LOCAL_BASE_ISO}"
            break
        fi
    done
fi

BASE_ISO_FILE="${LOCAL_BASE_ISO:-${WORK_DIR}/base.iso}"
BOOT_OPTS_FILE="${WORK_DIR}/el_torito_opts.txt"

# --- Manejador de Limpieza y Salida Segura (Trap) ---
cleanup_mounts() {
    local exit_code=$?
    log_warn "Ejecutando rutina de desmontaje seguro y limpieza de recursos..."

    set +e
    for mp in \
        "${CHROOT_DIR}/opt/defokos-build-scripts" \
        "${CHROOT_DIR}/tmp/scripts" \
        "${CHROOT_DIR}/run" \
        "${CHROOT_DIR}/sys" \
        "${CHROOT_DIR}/proc" \
        "${CHROOT_DIR}/dev/pts" \
        "${CHROOT_DIR}/dev" \
        "${CHROOT_DIR}" \
        "${ISO_MOUNT_DIR}"; do
        if mountpoint -q "$mp" 2>/dev/null; then
            log_info "Desmontando: $mp"
            umount -lf "$mp" 2>/dev/null || true
        fi
    done

    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        log_err "La construcción falló con código de salida: $exit_code"
    fi
    exit $exit_code
}
trap cleanup_mounts EXIT INT TERM

log_banner

# ==============================================================================
# PASO 0: LIMPIEZA DE BASE PREVIA (SI SE SOLICITA O ES POP!_OS 22.04 OBSOLETA)
# ==============================================================================
log_step "Paso 0: Comprobando estado del espacio de trabajo"

if [[ -f "${WORK_DIR}/base.iso" ]]; then
    if file "${WORK_DIR}/base.iso" 2>/dev/null | grep -qi "22\.04"; then
        log_warn "Se detectó que work/base.iso es Pop!_OS 22.04 (antigua con GNOME/X11)."
        log_warn "Purgando archivo obsoleto para garantizar una instalación limpia de Pop!_OS 24.04..."
        rm -f "${WORK_DIR}/base.iso"
        CLEAN=true
    fi
fi

if [[ "${CLEAN}" == "true" ]]; then
    log_warn "Opción --clean activada: Purgando chroot, extracciones y archivos temporales..."
    set +e
    for mp in "${CHROOT_DIR}/run" "${CHROOT_DIR}/sys" "${CHROOT_DIR}/proc" "${CHROOT_DIR}/dev/pts" "${CHROOT_DIR}/dev" "${CHROOT_DIR}" "${ISO_MOUNT_DIR}"; do
        if mountpoint -q "$mp" 2>/dev/null; then umount -lf "$mp" 2>/dev/null || true; fi
    done
    set -e
    rm -rf "${CHROOT_DIR}" "${ISO_EXTRACT_DIR}" "${ISO_MOUNT_DIR}" "${WORK_DIR}/base.iso" "${BOOT_OPTS_FILE}"
fi

# ==============================================================================
# PASO 1: INSTALACIÓN AUTOMÁTICA DE HERRAMIENTAS EN EL HOST
# ==============================================================================
log_step "Paso 1: Verificando e instalando herramientas necesarias en el host"

HOST_PACKAGES=(
    xorriso
    squashfs-tools
    curl
    rsync
    mtools
    dosfstools
    python3
    imagemagick
    ffmpeg
    fontconfig
    debootstrap
    coreutils
)

MISSING_TOOLS=()
for tool in xorriso mksquashfs unsquashfs curl rsync mcopy mformat python3 convert ffmpeg fc-cache; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    log_warn "Faltan herramientas en el host: ${MISSING_TOOLS[*]}"
    log_info "Instalando paquetes requeridos vía apt-get..."
    apt-get update -y
    apt-get install -y --no-install-recommends "${HOST_PACKAGES[@]}"
fi
log_success "Todas las herramientas del host están listas."

# ==============================================================================
# PASO 2: PREPARACIÓN DE DIRECTORIOS Y RECURSOS
# ==============================================================================
log_step "Paso 2: Preparando espacio de trabajo y directorios"

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${OVERLAY_DIR}" "${SCRIPTS_DIR}" "${ASSETS_DIR}" "${DEBS_DIR}"
mkdir -p "${ISO_MOUNT_DIR}" "${ISO_EXTRACT_DIR}"
log_info "Directorio de trabajo: ${WORK_DIR}"
log_info "Directorio de salida:   ${OUT_DIR}"

# ==============================================================================
# PASO 3: OBTENCIÓN Y PREPARACIÓN DE ASSETS, FUENTES, ICONOS Y PAQUETES .DEB
# ==============================================================================
log_step "Paso 3: Recolectando assets, iconos, fuentes y aplicaciones nativas"

# 1. Icono personalizado Defoko Pop!_OS
ICON_SOURCE=""
for cand in \
    "${ASSETS_DIR}/Pop!_OS_Icon.png" \
    "/home/alex/Descargas/Pop!_OS_Icon.png" \
    "/home/${REAL_USER}/Descargas/Pop!_OS_Icon.png" \
    "${HOME}/Descargas/Pop!_OS_Icon.png"; do
    if [[ -f "$cand" ]]; then
        ICON_SOURCE="$cand"
        break
    fi
done

if [[ -n "${ICON_SOURCE}" ]]; then
    log_info "Utilizando icono fuente: ${ICON_SOURCE}"
    cp -f "${ICON_SOURCE}" "${ASSETS_DIR}/Pop!_OS_Icon.png"
fi

# 2. Fondo de pantalla de arranque del sistema (systemd_defoko_background)
BG_SOURCE=""
for cand in \
    "${ASSETS_DIR}/systemd_defoko_background.jpeg" \
    "/home/alex/Descargas/systemd_defoko_background.jpeg" \
    "/home/${REAL_USER}/Descargas/systemd_defoko_background.jpeg" \
    "${HOME}/Descargas/systemd_defoko_background.jpeg"; do
    if [[ -f "$cand" ]]; then
        BG_SOURCE="$cand"
        break
    fi
done

if [[ -n "${BG_SOURCE}" ]]; then
    log_info "Procesando fondo de arranque desde: ${BG_SOURCE}"
    cp -f "${BG_SOURCE}" "${ASSETS_DIR}/systemd_defoko_background.jpeg"
    
    # Generar versión PNG 1080p para GRUB
    ffmpeg -y -i "${BG_SOURCE}" -vf "scale=1920:1080" "${ASSETS_DIR}/boot_background_1080p.png" 2>/dev/null || true
    
    # Generar versión BMP 24-bit sin compresión 1920x1080 para systemd-boot (UEFI)
    ffmpeg -y -i "${BG_SOURCE}" -vf "scale=1920:1080" -pix_fmt bgr24 "${ASSETS_DIR}/splash.bmp" 2>/dev/null || true
fi

# 3. Fuente Pixelify Sans
mkdir -p "${ASSETS_DIR}/fonts"
FONT_TARGET="${ASSETS_DIR}/fonts/PixelifySans-VariableFont_wght.ttf"
if [[ ! -f "${FONT_TARGET}" ]]; then
    if [[ -f "/home/alex/Descargas/Pixelify_Sans.zip" ]]; then
        unzip -p "/home/alex/Descargas/Pixelify_Sans.zip" "*PixelifySans*.ttf" > "${FONT_TARGET}" 2>/dev/null || true
    fi
fi
if [[ ! -f "${FONT_TARGET}" ]] || [[ $(stat -c%s "${FONT_TARGET}" 2>/dev/null || echo 0) -lt 1000 ]]; then
    log_info "Descargando Pixelify Sans desde Google Fonts..."
    curl -fsSL --connect-timeout 15 -o "${FONT_TARGET}" \
        "https://github.com/google/fonts/raw/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf" || true
fi

# 4. Paquetes nativos .deb (YouTube Music, Discord, Steam)
if [[ ! -f "${DEBS_DIR}/youtube-music.deb" ]]; then
    log_info "Descargando YouTube Music Desktop .deb..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/youtube-music.deb" \
        "https://github.com/ytmdesktop/ytmdesktop/releases/download/v2.0.12/youtube-music-desktop-app_2.0.12_amd64.deb" || true
fi

if [[ ! -f "${DEBS_DIR}/discord.deb" ]]; then
    log_info "Descargando Discord .deb..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/discord.deb" \
        "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=linux&arch=x64&format=deb" || true
fi

if [[ ! -f "${DEBS_DIR}/steam.deb" ]]; then
    log_info "Descargando Steam .deb..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/steam.deb" \
        "https://cdn.fastly.steamstatic.com/client/installer/steam.deb" || true
fi

# 5. Extensión PreMiD para Firefox
PREMID_XPI=""
for cand in \
    "/home/alex/Descargas/PreMiD.xpi" \
    "/home/${REAL_USER}/Descargas/PreMiD.xpi" \
    "${HOME}/Descargas/PreMiD.xpi"; do
    if [[ -f "$cand" ]]; then
        PREMID_XPI="$cand"
        break
    fi
done

# ==============================================================================
# PASO 4: GENERACIÓN DE SCRIPTS AUXILIARES Y PLANTILLAS OVERLAY
# ==============================================================================
log_step "Paso 4: Generando plantillas del sistema, overlay y scripts"

# --- 1. Generador de Iconos de Branding (Python) ---
cat << 'EOF' > "${SCRIPTS_DIR}/generate-branding-icons.py"
#!/usr/bin/env python3
import os
import sys
import subprocess
import base64

def generate_icons(source_path, overlay_dir):
    if not os.path.exists(source_path):
        return False

    sizes = [16, 22, 24, 32, 48, 64, 128, 256, 512]
    cache = {}

    for s in sizes:
        png_tmp = f"/tmp/pop_icon_{s}.png"
        subprocess.run(["convert", source_path, "-background", "none", "-resize", f"{s}x{s}", png_tmp], check=True)
        with open(png_tmp, "rb") as f:
            data = f.read()
        b64 = base64.b64encode(data).decode("utf-8")
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{s}" height="{s}" viewBox="0 0 {s} {s}">
  <image width="{s}" height="{s}" xlink:href="data:image/png;base64,{b64}"/>
</svg>'''
        cache[s] = (data, svg)

    for s in sizes:
        dim = f"{s}x{s}"
        places_dir = os.path.join(overlay_dir, "usr/share/icons/Pop", dim, "places")
        os.makedirs(places_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.svg", "distributor-logo.svg", "start-here-pop-os.svg", "pop-os-logo-icon.svg", "pop-os.svg"]:
            with open(os.path.join(places_dir, name), "w") as f:
                f.write(cache[s][1])

    for s in sizes:
        dim = f"{s}x{s}"
        apps_dir = os.path.join(overlay_dir, "usr/share/icons/hicolor", dim, "apps")
        os.makedirs(apps_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
            with open(os.path.join(apps_dir, name), "wb") as f:
                f.write(cache[s][0])

    branding_dir = os.path.join(overlay_dir, "usr/share/icons/pop-os-branding")
    os.makedirs(branding_dir, exist_ok=True)
    with open(os.path.join(branding_dir, "pop_icon.svg"), "w") as f:
        f.write(cache[512][1])

    for s in [16, 22, 24, 32, 48, 64]:
        round_dir = os.path.join(branding_dir, f"round-logos/{s}")
        os.makedirs(round_dir, exist_ok=True)
        with open(os.path.join(round_dir, "distributor-logo.svg"), "w") as f:
            f.write(cache[s][1])

    apps_256 = os.path.join(branding_dir, "256x256/apps")
    os.makedirs(apps_256, exist_ok=True)
    with open(os.path.join(apps_256, "ubuntu-logo-icon.png"), "wb") as f:
        f.write(cache[256][0])

    pixmaps_dir = os.path.join(overlay_dir, "usr/share/pixmaps")
    os.makedirs(pixmaps_dir, exist_ok=True)
    for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
        with open(os.path.join(pixmaps_dir, name), "wb") as f:
            f.write(cache[256][0])
    subprocess.run(["cp", "-f", source_path, os.path.join(pixmaps_dir, "Pop!_OS_Icon.png")], check=True)

    pop_basic = os.path.join(overlay_dir, "usr/share/plymouth/themes/pop-basic")
    os.makedirs(pop_basic, exist_ok=True)
    with open(os.path.join(pop_basic, "header-image.png"), "wb") as f:
        f.write(cache[256][0])
    with open(os.path.join(pop_basic, "bgrt-fallback.png"), "wb") as f:
        f.write(cache[256][0])

    spinner = os.path.join(overlay_dir, "usr/share/plymouth/themes/spinner")
    os.makedirs(spinner, exist_ok=True)
    with open(os.path.join(spinner, "bgrt-fallback.png"), "wb") as f:
        f.write(cache[256][0])
    subprocess.run(["convert", source_path, "-background", "none", "-resize", "x87", os.path.join(spinner, "watermark.png")], check=True)

    grub_theme_dir = os.path.join(overlay_dir, "boot/grub/themes/pop")
    os.makedirs(grub_theme_dir, exist_ok=True)
    with open(os.path.join(grub_theme_dir, "logo.png"), "wb") as f:
        f.write(cache[128][0])

    calamares_dir = os.path.join(overlay_dir, "etc/calamares/branding/defokos")
    os.makedirs(calamares_dir, exist_ok=True)
    with open(os.path.join(calamares_dir, "logo.png"), "wb") as f:
        f.write(cache[128][0])
    return True

if __name__ == "__main__":
    src = sys.argv[1]
    tgt = sys.argv[2]
    generate_icons(src, tgt)
EOF
chmod +x "${SCRIPTS_DIR}/generate-branding-icons.py"

# Generar iconos si el source existe
if [[ -f "${ASSETS_DIR}/Pop!_OS_Icon.png" ]]; then
    python3 "${SCRIPTS_DIR}/generate-branding-icons.py" "${ASSETS_DIR}/Pop!_OS_Icon.png" "${OVERLAY_DIR}" || true
fi

# --- 2. Overlay: Identificación del Sistema (os-release, issue, lsb-release) ---
mkdir -p "${OVERLAY_DIR}/etc"
cat << 'EOF' > "${OVERLAY_DIR}/etc/os-release"
NAME="Pop!_OS"
PRETTY_NAME="DefokOS 24.04 LTS (Utane Uta Edition)"
ID=pop
ID_LIKE="ubuntu debian"
DEFOKOS_NAME="DefokOS"
DEFOKOS_EDITION="Utane Uta Edition"
VERSION="24.04 LTS"
VERSION_ID="24.04"
VERSION_CODENAME="noble"
UBUNTU_CODENAME="noble"
HOME_URL="https://github.com/defokos"
SUPPORT_URL="https://github.com/defokos/issues"
BUG_REPORT_URL="https://github.com/defokos/issues"
PRIVACY_POLICY_URL="https://github.com/defokos"
BUILD_ID="rolling"
LOGO="distributor-logo-pop-os"
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/lsb-release"
DISTRIB_ID=Pop
DISTRIB_RELEASE=24.04
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="DefokOS 24.04 LTS (Utane Uta Edition)"
EOF

echo "DefokOS 24.04 LTS \n \l" > "${OVERLAY_DIR}/etc/issue"
echo "DefokOS 24.04 LTS" > "${OVERLAY_DIR}/etc/issue.net"

# --- 3. Overlay: Repositorios Oficiales de System76 y Llaves GPG ---
mkdir -p "${OVERLAY_DIR}/etc/apt/sources.list.d" "${OVERLAY_DIR}/etc/apt/trusted.gpg.d"
cat << 'EOF' > "${OVERLAY_DIR}/etc/apt/sources.list.d/system76.sources"
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

# Descargar llaves de archivo oficiales de Pop!_OS si no existen
if [[ ! -f "${OVERLAY_DIR}/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg" ]]; then
    curl -fsSL --connect-timeout 10 "https://apt.pop-os.org/proprietary/archive.key" | gpg --dearmor -o "${OVERLAY_DIR}/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg" 2>/dev/null || true
fi
if [[ ! -f "${OVERLAY_DIR}/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg" ]]; then
    curl -fsSL --connect-timeout 10 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x871920D1991BC93C" | gpg --dearmor -o "${OVERLAY_DIR}/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg" 2>/dev/null || true
fi

# --- 4. Overlay: Configuración de Fuentes (Pixelify Sans por defecto) ---
mkdir -p "${OVERLAY_DIR}/etc/fonts" "${OVERLAY_DIR}/usr/share/fonts/truetype/pixelify-sans"
cat << 'EOF' > "${OVERLAY_DIR}/etc/fonts/local.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Pixelify Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>system-ui</family>
    <prefer>
      <family>Pixelify Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>Cantarell</family>
    <prefer>
      <family>Pixelify Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>Ubuntu</family>
    <prefer>
      <family>Pixelify Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>Fira Sans</family>
    <prefer>
      <family>Pixelify Sans</family>
    </prefer>
  </alias>
</fontconfig>
EOF

if [[ -f "${FONT_TARGET}" ]]; then
    cp -f "${FONT_TARGET}" "${OVERLAY_DIR}/usr/share/fonts/truetype/pixelify-sans/"
fi

# --- 5. Overlay: Entorno COSMIC Desktop y Fuentes ---
mkdir -p "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTk/v1"
mkdir -p "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1"
mkdir -p "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTheme.Mode/v1"

cat << 'EOF' > "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTk/v1/interface_font"
(
    family: "Pixelify Sans",
    weight: Normal,
    stretch: Normal,
    style: Normal,
)
EOF

echo '"DefokOS-Lavender"' > "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1/name"
echo 'Some((red: 0.7058824, green: 0.6235294, blue: 0.8))' > "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTheme.Dark/v1/accent"
echo 'true' > "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"

# --- 6. Overlay: Gestor de Arranque y Fondos (systemd-boot + GRUB) ---
mkdir -p "${OVERLAY_DIR}/boot/efi/loader" "${OVERLAY_DIR}/boot/grub/themes/pop" "${OVERLAY_DIR}/etc/default/grub.d" "${OVERLAY_DIR}/etc/kernel/postinst.d"
mkdir -p "${OVERLAY_DIR}/usr/share/backgrounds"

cat << 'EOF' > "${OVERLAY_DIR}/boot/efi/loader/loader.conf"
timeout 5
default Pop_OS-current
splash /splash.bmp
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/default/grub.d/99_defokos_splash.cfg"
GRUB_BACKGROUND="/usr/share/backgrounds/systemd_defoko_background.jpeg"
GRUB_THEME="/boot/grub/themes/pop/theme.txt"
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/kernel/postinst.d/zz-defokos-splash"
#!/bin/sh
set -e
if [ -d /boot/efi ]; then
    if [ -f /usr/share/backgrounds/systemd_defoko_background.bmp ]; then
        cp -f /usr/share/backgrounds/systemd_defoko_background.bmp /boot/efi/splash.bmp 2>/dev/null || true
        mkdir -p /boot/efi/loader 2>/dev/null || true
        cp -f /usr/share/backgrounds/systemd_defoko_background.bmp /boot/efi/loader/splash.bmp 2>/dev/null || true
    fi
    LOADER_CONF="/boot/efi/loader/loader.conf"
    if [ -f "${LOADER_CONF}" ]; then
        if ! grep -q "splash" "${LOADER_CONF}"; then
            echo "splash /splash.bmp" >> "${LOADER_CONF}"
        fi
        if ! grep -q "timeout" "${LOADER_CONF}"; then
            echo "timeout 5" >> "${LOADER_CONF}"
        fi
    fi
fi
exit 0
EOF
chmod +x "${OVERLAY_DIR}/etc/kernel/postinst.d/zz-defokos-splash"

if [[ -f "${ASSETS_DIR}/splash.bmp" ]]; then
    cp -f "${ASSETS_DIR}/splash.bmp" "${OVERLAY_DIR}/boot/efi/splash.bmp"
    cp -f "${ASSETS_DIR}/splash.bmp" "${OVERLAY_DIR}/boot/efi/loader/splash.bmp"
    cp -f "${ASSETS_DIR}/splash.bmp" "${OVERLAY_DIR}/usr/share/backgrounds/systemd_defoko_background.bmp"
fi
if [[ -f "${ASSETS_DIR}/boot_background_1080p.png" ]]; then
    cp -f "${ASSETS_DIR}/boot_background_1080p.png" "${OVERLAY_DIR}/boot/grub/themes/pop/background.png"
fi
if [[ -f "${ASSETS_DIR}/systemd_defoko_background.jpeg" ]]; then
    cp -f "${ASSETS_DIR}/systemd_defoko_background.jpeg" "${OVERLAY_DIR}/usr/share/backgrounds/systemd_defoko_background.jpeg"
fi

# --- 7. Overlay: Instalador Universal Calamares ---
mkdir -p "${OVERLAY_DIR}/etc/calamares/branding/defokos" "${OVERLAY_DIR}/usr/share/applications"
cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/settings.conf"
---
modules-search: [ local ]
instances:
- id:       defokos
  module:   branding
  config:   branding.desc
sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - initramfs
  - grubcfg
  - bootloader
  - umount
- show:
  - finished
branding: defokos
prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false
quit-at-end: false
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/branding/defokos/branding.desc"
---
componentName:       defokos
welcomeStyleCalamares: false
welcomeExpandingLogo: true
windowExpanding:     normal
windowSize:          800px,520px
windowPosition:      center
strings:
    productName:         DefokOS
    shortProductName:    DefokOS
    version:             24.04 LTS
    shortVersion:        24.04
    versionedName:       DefokOS 24.04 LTS (Utane Uta Edition)
    shortVersionedName:  DefokOS 24.04
    bootloaderEntryName: DefokOS
    productUrl:          https://github.com/defokos
    supportUrl:          https://github.com/defokos/issues
    knownIssuesUrl:      https://github.com/defokos/issues
    releaseNotesUrl:     https://github.com/defokos
images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "welcome.png"
style:
   SidebarBackground:    "#24272e"
   SidebarText:          "#ffffff"
   SidebarTextSelect:    "#24272e"
   SidebarTextHighlight: "#b49fcc"
EOF

cat << 'EOF' > "${OVERLAY_DIR}/usr/share/applications/io.calamares.calamares.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Install DefokOS
GenericName=Live System Installer
Comment=Install DefokOS 24.04 LTS (Utane Uta Edition) to disk
Exec=sh -c "pkexec calamares"
Icon=distributor-logo-pop-os
Terminal=false
StartupNotify=true
Categories=System;
EOF

# --- 8. Overlay: Extensión PreMiD para Firefox ---
mkdir -p "${OVERLAY_DIR}/etc/firefox/policies" "${OVERLAY_DIR}/usr/lib/firefox/distribution"
mkdir -p "${OVERLAY_DIR}/usr/lib/firefox/browser/extensions"
mkdir -p "${OVERLAY_DIR}/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"

cat << 'EOF' > "${OVERLAY_DIR}/etc/firefox/policies/policies.json"
{
  "policies": {
    "ExtensionSettings": {
      "support@premid.app": {
        "installation_mode": "normal_installed",
        "install_url": "file:///usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi"
      }
    }
  }
}
EOF
cp -f "${OVERLAY_DIR}/etc/firefox/policies/policies.json" "${OVERLAY_DIR}/usr/lib/firefox/distribution/policies.json"

if [[ -n "${PREMID_XPI}" ]]; then
    cp -f "${PREMID_XPI}" "${OVERLAY_DIR}/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi"
    cp -f "${PREMID_XPI}" "${OVERLAY_DIR}/usr/lib/firefox/browser/extensions/support@premid.app.xpi"
fi

# --- 9. Script de Aprovisionamiento Chroot (chroot-setup.sh) ---
cat << 'EOF' > "${SCRIPTS_DIR}/chroot-setup.sh"
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "[CHROOT] Iniciando aprovisionamiento del sistema..."

# 1. Arquitectura de 32-bit (Steam, Wine)
dpkg --add-architecture i386 || true

# 2. Configuración de repositorios
apt-get update -y || apt-get update -y --fix-missing || true
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release software-properties-common

add-apt-repository -y universe || true
add-apt-repository -y multiverse || true
add-apt-repository -y restricted || true

# VSCodium
if [ ! -f /etc/apt/keyrings/vscodium-archive-keyring.gpg ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL --connect-timeout 10 "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" | gpg --dearmor -o /etc/apt/keyrings/vscodium-archive-keyring.gpg 2>/dev/null || true
fi
echo 'deb [ signed-by=/etc/apt/keyrings/vscodium-archive-keyring.gpg ] https://download.vscodium.com/debs vscodium main' > /etc/apt/sources.list.d/vscodium.list

# Fastfetch PPA
if ! apt-cache show fastfetch >/dev/null 2>&1; then
    add-apt-repository -y ppa:zhangsongcui3371/fastfetch || true
fi

apt-get update -y || apt-get update -y --fix-missing || true

# 3. Desinstalar bloatware no deseado
echo "[CHROOT] Purgando thunderbird, popsicle, xterm, gnome-terminal..."
apt-get purge -y thunderbird 'thunderbird-locale-*' popsicle popsicle-gtk xterm gnome-terminal gnome-terminal-data || true
rm -f /usr/share/applications/thunderbird.desktop /usr/share/applications/popsicle*.desktop /usr/share/applications/*xterm*.desktop /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true

# 4. Instalación de paquetes principales
APT_PACKAGES=(
    linux-generic casper systemd systemd-sysv udev sudo locales network-manager net-tools
    pop-de-cosmic cosmic-session cosmic-store cosmic-term cosmic-edit cosmic-files cosmic-greeter cosmic-app-library
    mesa-vulkan-drivers mesa-utils vulkan-tools libvulkan1 libgl1-mesa-dri libgl1 libglu1-mesa libegl-mesa0 libglx-mesa0
    pipewire pipewire-pulse pipewire-alsa pipewire-audio-client-libraries wireplumber pulseaudio-utils pavucontrol audacity sox ffmpeg ladspa-sdk
    calamares calamares-settings-ubuntu-common
    kitty fastfetch htop btop neovim tmux git curl wget rsync ripgrep jq tree build-essential codium fuse3
)

if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2t64)
elif apt-cache show libfuse2 >/dev/null 2>&1; then
    APT_PACKAGES+=(libfuse2)
fi

INSTALLABLE=()
for pkg in "${APT_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        INSTALLABLE+=("$pkg")
    fi
done

echo "[CHROOT] Instalando paquetes principales (${#INSTALLABLE[@]} disponibles)..."
apt-get install -y --no-install-recommends "${INSTALLABLE[@]}" || {
    echo "[CHROOT:WARN] Instalando paquete por paquete..."
    for pkg in "${INSTALLABLE[@]}"; do
        apt-get install -y --no-install-recommends "$pkg" || true
    done
    apt-get install -f -y --no-install-recommends || true
}

# Gráficos 32-bit para Steam
apt-get install -y --no-install-recommends libvulkan1:i386 mesa-vulkan-drivers:i386 || true

# Usuario Live defokos
if ! id defokos >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev defokos || true
    echo "defokos:defokos" | chpasswd || true
    echo "defokos ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/defokos
    chmod 0440 /etc/sudoers.d/defokos
fi

# 5. Instalación de paquetes .deb locales (YouTube Music, Discord, Steam)
DEBS_STAGE="/opt/defokos-packages"
if [[ -d "${DEBS_STAGE}" ]]; then
    for deb in "${DEBS_STAGE}"/*.deb; do
        if [[ -f "$deb" ]]; then
            echo "[CHROOT] Instalando $(basename "$deb")..."
            apt-get install -y --no-install-recommends "$deb" || apt-get install -f -y --no-install-recommends || true
        fi
    done
fi

# 6. Flatpak
apt-get install -y --no-install-recommends flatpak || true
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak uninstall --system -y com.discordapp.Discord 2>/dev/null || true

# 7. Permisos PreMiD
for ext in "/usr/lib/firefox/browser/extensions/support@premid.app.xpi" "/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi"; do
    if [[ -f "$ext" ]]; then chmod 644 "$ext" || true; fi
done

# 8. Limpieza Profunda para asegurar que SquashFS quepa en partición /recovery (límite 4GB FAT32)
echo "[CHROOT] Purgando runtimes de flatpak y cachés para optimizar tamaño..."
rm -rf /var/lib/flatpak/runtime/* /var/lib/flatpak/app/* /var/lib/flatpak/.removed/* 2>/dev/null || true
apt-get autoremove -y --purge || true
apt-get clean -y || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /root/.cache/* /home/*/.cache/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true

echo "[CHROOT] Aprovisionamiento completado exitosamente."
EOF
chmod +x "${SCRIPTS_DIR}/chroot-setup.sh"

# --- 10. Script de Aplicación de Tema (apply-theme.sh) ---
cat << 'EOF' > "${SCRIPTS_DIR}/apply-theme.sh"
#!/usr/bin/env bash
set -euo pipefail

echo "[THEME] Aplicando caché de fuentes y configuración visual..."

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv /usr/share/fonts/ 2>/dev/null || true
fi

if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
fi

if command -v update-grub >/dev/null 2>&1; then
    update-grub 2>/dev/null || true
fi

echo "[THEME] Personalización aplicada correctamente."
EOF
chmod +x "${SCRIPTS_DIR}/apply-theme.sh"

log_success "Plantillas, scripts y overlay generados exitosamente."

# ==============================================================================
# PASO 5: OBTENCIÓN DE LA IMAGEN ISO BASE POP!_OS 24.04
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]] && [[ "${REPACK}" != "true" ]] && [[ "${BOOTSTRAP}" != "true" ]]; then
    log_step "Paso 5: Localizando imagen base Pop!_OS 24.04"

    if [[ -n "${LOCAL_BASE_ISO}" ]] && [[ -f "${LOCAL_BASE_ISO}" ]]; then
        log_info "Utilizando imagen base local: ${LOCAL_BASE_ISO}"
        BASE_ISO_FILE="${LOCAL_BASE_ISO}"
    elif [[ -f "${WORK_DIR}/base.iso" ]]; then
        log_info "Utilizando imagen base en caché: ${WORK_DIR}/base.iso"
        BASE_ISO_FILE="${WORK_DIR}/base.iso"
    else
        log_info "Descargando imagen oficial Pop!_OS 24.04 LTS..."
        curl -L -C - --fail --progress-bar -o "${WORK_DIR}/base.iso.tmp" "${BASE_ISO_URL}"
        mv "${WORK_DIR}/base.iso.tmp" "${WORK_DIR}/base.iso"
        BASE_ISO_FILE="${WORK_DIR}/base.iso"
        log_success "Descarga de imagen base completada."
    fi

    # Extracción de la ISO
    log_info "Extrayendo árbol de archivos y geometría El Torito de la ISO base..."
    xorriso -indev "${BASE_ISO_FILE}" -report_el_torito as_mkisofs > "${BOOT_OPTS_FILE}" 2>/dev/null || true

    rm -rf "${ISO_EXTRACT_DIR:?}"/* 2>/dev/null || true
    if mount -o loop,ro "${BASE_ISO_FILE}" "${ISO_MOUNT_DIR}" 2>/dev/null; then
        rsync -a "${ISO_MOUNT_DIR}/" "${ISO_EXTRACT_DIR}/"
        umount -lf "${ISO_MOUNT_DIR}" 2>/dev/null || true
    else
        xorriso -osirrox on -indev "${BASE_ISO_FILE}" -extract / "${ISO_EXTRACT_DIR}" 2>/dev/null || true
        chmod -R u+w "${ISO_EXTRACT_DIR}" 2>/dev/null || true
    fi

    # Localizar SquashFS
    SQUASHFS_IMAGE=""
    for cand in "${ISO_EXTRACT_DIR}/casper/filesystem.squashfs" "${ISO_EXTRACT_DIR}"/casper*/filesystem.squashfs "${ISO_EXTRACT_DIR}/live/filesystem.squashfs"; do
        if [[ -f "$cand" ]]; then SQUASHFS_IMAGE="$(realpath "$cand")"; break; fi
    done

    if [[ -z "${SQUASHFS_IMAGE}" ]]; then
        log_err "No se localizó filesystem.squashfs en la ISO base."
        exit 1
    fi

    # Descompresión de SquashFS
    log_info "Descomprimiendo SquashFS en ${CHROOT_DIR}..."
    rm -rf "${CHROOT_DIR}"
    unsquashfs -f -d "${CHROOT_DIR}" "${SQUASHFS_IMAGE}"
    log_success "SquashFS descomprimido limpiamente."

elif [[ "${BOOTSTRAP}" == "true" ]]; then
    log_step "Paso 5: Construcción base vía debootstrap noble"
    rm -rf "${CHROOT_DIR}"
    mkdir -p "${CHROOT_DIR}"
    debootstrap --arch=amd64 noble "${CHROOT_DIR}" http://apt.pop-os.org/ubuntu || \
    debootstrap --arch=amd64 noble "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    mkdir -p "${ISO_EXTRACT_DIR}/casper"
    SQUASHFS_IMAGE="${ISO_EXTRACT_DIR}/casper/filesystem.squashfs"
fi

# ==============================================================================
# PASO 6: PREPARACIÓN DE CHROOT, BIND MOUNTS Y POLÍTICAS
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]]; then
    log_step "Paso 6: Preparando monturas virtuales y DNS en chroot"

    rm -f "${CHROOT_DIR}/etc/resolv.conf"
    cat << 'EOF' > "${CHROOT_DIR}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

    cat << 'EOF' > "${CHROOT_DIR}/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
    chmod +x "${CHROOT_DIR}/usr/sbin/policy-rc.d"

    mount --bind "${CHROOT_DIR}" "${CHROOT_DIR}"
    mount --make-rslave "${CHROOT_DIR}"

    mount --bind /dev "${CHROOT_DIR}/dev"
    mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    mount -t proc proc "${CHROOT_DIR}/proc"
    mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    mount -t tmpfs tmpfs "${CHROOT_DIR}/run"

    # ==============================================================================
    # PASO 7: APLICACIÓN DEL OVERLAY Y PERSONALIZACIÓN DE ARRANQUE EN ISO
    # ==============================================================================
    log_step "Paso 7: Inyectando overlay en chroot y actualizando menú de la ISO"

    rsync -av "${OVERLAY_DIR}/" "${CHROOT_DIR}/"

    # Sincronizar fondo, logotipo y título en el menú de la ISO
    if [[ -d "${ISO_EXTRACT_DIR}/boot/grub/themes/pop" ]]; then
        if [[ -f "${ASSETS_DIR}/boot_background_1080p.png" ]]; then
            cp -f "${ASSETS_DIR}/boot_background_1080p.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/background.png"
        fi
        if [[ -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" ]]; then
            cp -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/logo.png"
        fi
    fi
    if [[ -f "${ASSETS_DIR}/splash.bmp" ]]; then
        cp -f "${ASSETS_DIR}/splash.bmp" "${ISO_EXTRACT_DIR}/splash.bmp" 2>/dev/null || true
        mkdir -p "${ISO_EXTRACT_DIR}/boot/efi" 2>/dev/null || true
        cp -f "${ASSETS_DIR}/splash.bmp" "${ISO_EXTRACT_DIR}/boot/efi/splash.bmp" 2>/dev/null || true
    fi
    if [[ -f "${ISO_EXTRACT_DIR}/boot/grub/grub.cfg" ]]; then
        sed -i 's/Try or Install Pop_OS/DefokOS 24.04 LTS (Utane Uta Edition) - COSMIC Desktop/g' "${ISO_EXTRACT_DIR}/boot/grub/grub.cfg"
    fi
    if [[ -f "${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg" ]]; then
        sed -i 's/default pop-os/default defokos/g; s/label pop-os/label defokos/g' "${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
    fi

    # ==============================================================================
    # PASO 8: EJECUCIÓN DE APROVISIONAMIENTO Y TEMAS DENTRO DEL CHROOT
    # ==============================================================================
    log_step "Paso 8: Ejecutando aprovisionamiento y personalización en chroot"

    STAGE_SCRIPTS="${CHROOT_DIR}/opt/defokos-build-scripts"
    STAGE_DEBS="${CHROOT_DIR}/opt/defokos-packages"
    mkdir -p "${STAGE_SCRIPTS}" "${STAGE_DEBS}"

    cp -r "${SCRIPTS_DIR}/"* "${STAGE_SCRIPTS}/"
    chmod +x "${STAGE_SCRIPTS}/"*.sh

    if ls "${DEBS_DIR}"/*.deb >/dev/null 2>&1; then
        cp -f "${DEBS_DIR}/"*.deb "${STAGE_DEBS}/"
    fi

    chroot "${CHROOT_DIR}" /bin/bash /opt/defokos-build-scripts/chroot-setup.sh
    chroot "${CHROOT_DIR}" /bin/bash /opt/defokos-build-scripts/apply-theme.sh

    rm -rf "${STAGE_SCRIPTS}" "${STAGE_DEBS}"
    log_success "Aprovisionamiento en chroot finalizado satisfactoriamente."

    # ==============================================================================
    # PASO 9: DESMONTAJE Y LIMPIEZA DE CHROOT
    # ==============================================================================
    log_step "Paso 9: Desmontando sistemas de archivos virtuales"

    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d"
    rm -f "${CHROOT_DIR}/etc/resolv.conf"
    ln -sf /run/systemd/resolve/stub-resolv.conf "${CHROOT_DIR}/etc/resolv.conf" 2>/dev/null || true

    umount -lf "${CHROOT_DIR}/run" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}" 2>/dev/null || true

    # ==============================================================================
    # PASO 10: HIGIENE DE ESPACIO, KERNEL SYNC Y COMPRESIÓN SQUASHFS
    # ==============================================================================
    log_step "Paso 10: Comprimiendo nuevo filesystem.squashfs"

    # Determinar ruta de SquashFS
    if [[ -z "${SQUASHFS_IMAGE:-}" ]]; then
        for cand in "${ISO_EXTRACT_DIR}/casper/filesystem.squashfs" "${ISO_EXTRACT_DIR}"/casper*/filesystem.squashfs; do
            if [[ -f "$cand" ]]; then SQUASHFS_IMAGE="$(realpath "$cand")"; break; fi
        done
        SQUASHFS_IMAGE="${SQUASHFS_IMAGE:-${ISO_EXTRACT_DIR}/casper/filesystem.squashfs}"
    fi
    CASPER_DIR="$(dirname "${SQUASHFS_IMAGE}")"
    mkdir -p "${CASPER_DIR}"

    # Limpieza estricta para garantizar que quepa en la partición /recovery (4GB FAT32)
    rm -rf "${CHROOT_DIR}/var/lib/flatpak/runtime/"* 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/var/lib/flatpak/app/"* 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/var/lib/flatpak/.removed/"* 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/var/cache/apt/archives/"*.deb 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/var/lib/apt/lists/"* 2>/dev/null || true
    rm -rf "${CHROOT_DIR}/root/.cache/"* 2>/dev/null || true

    # Sincronizar kernel e initrd con el live boot
    LATEST_KERNEL=$(ls -t "${CHROOT_DIR}/boot/vmlinuz"* 2>/dev/null | head -n1 || true)
    LATEST_INITRD=$(ls -t "${CHROOT_DIR}/boot/initrd.img"* 2>/dev/null | head -n1 || true)
    if [[ -n "${LATEST_KERNEL}" ]] && [[ -f "${LATEST_KERNEL}" ]]; then
        cp -f "${LATEST_KERNEL}" "${CASPER_DIR}/vmlinuz.efi"
    fi
    if [[ -n "${LATEST_INITRD}" ]] && [[ -f "${LATEST_INITRD}" ]]; then
        cp -f "${LATEST_INITRD}" "${CASPER_DIR}/initrd.gz"
    fi

    # Actualizar metadata
    printf $(du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1) > "${CASPER_DIR}/filesystem.size"
    chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package} ${Version}\n' > "${CASPER_DIR}/filesystem.manifest" 2>/dev/null || true
    cp -f "${CASPER_DIR}/filesystem.manifest" "${CASPER_DIR}/filesystem.manifest-desktop" 2>/dev/null || true

    rm -f "${SQUASHFS_IMAGE}"
    log_info "Comprimiendo SquashFS con ${COMPRESSION} (nivel máximo de compresión)..."
    MKSQUASHFS_OPTS=(-noappend -b 1048576 -no-recovery -always-use-fragments)
    if [[ "${COMPRESSION}" == "zstd" ]]; then
        MKSQUASHFS_OPTS+=(-comp zstd -Xcompression-level 19)
    elif [[ "${COMPRESSION}" == "xz" ]]; then
        MKSQUASHFS_OPTS+=(-comp xz)
    else
        MKSQUASHFS_OPTS+=(-comp gzip)
    fi

    mksquashfs "${CHROOT_DIR}" "${SQUASHFS_IMAGE}" "${MKSQUASHFS_OPTS[@]}"
    log_success "filesystem.squashfs generado exitosamente."

    (
        cd "${ISO_EXTRACT_DIR}"
        rm -f md5sum.txt
        find . -type f ! -path "./md5sum.txt" ! -path "./boot.catalog" -exec md5sum {} + > md5sum.txt
    )
fi

# ==============================================================================
# PASO 11: CREACIÓN DE ISO HÍBRIDA BOOTEABLE CON XORRISO
# ==============================================================================
log_step "Paso 11: Empaquetando ISO híbrida booteable (UEFI + BIOS) con xorriso"

FINAL_ISO_PATH="${OUT_DIR}/${ISO_OUTPUT_NAME}"
rm -f "${FINAL_ISO_PATH}"

EFI_IMG=""
for cand in \
    "boot/grub/efi.img" \
    "EFI/boot/efi.img" \
    "EFI/boot/bootx64.efi" \
    "efi/boot/bootx64.efi" \
    "efi/boot/efi.img"; do
    if [[ -f "${ISO_EXTRACT_DIR}/${cand}" ]]; then
        EFI_IMG="${cand}"
        break
    fi
done

XORRISO_ARGS=(
    -as mkisofs
    -r
    -V "${VOLUME_LABEL}"
    -o "${FINAL_ISO_PATH}"
    -J -l
)

if [[ -f "${ISO_EXTRACT_DIR}/isolinux/isolinux.bin" ]] && [[ -f "${ISO_EXTRACT_DIR}/isolinux/boot.cat" ]]; then
    log_info "Añadiendo soporte de arranque ISOLINUX tradicional..."
    XORRISO_ARGS+=(
        -b isolinux/isolinux.bin
        -c isolinux/boot.cat
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
fi

if [[ -n "${EFI_IMG}" ]]; then
    log_info "Añadiendo soporte de arranque UEFI con imagen: ${EFI_IMG}"
    XORRISO_ARGS+=(
        -eltorito-alt-boot
        -e "${EFI_IMG}"
        -no-emul-boot
        -boot-load-size 8192
        -isohybrid-gpt-basdat
    )
fi

if [[ -n "${BASE_ISO_FILE}" ]] && [[ -f "${BASE_ISO_FILE}" ]]; then
    log_info "Inyectando código de arranque MBR híbrido desde la ISO base..."
    XORRISO_ARGS+=(
        -isohybrid-mbr "--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:${BASE_ISO_FILE}"
        --mbr-force-bootable
        -partition_cyl_align off
    )
elif [[ -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]]; then
    log_info "Inyectando código de arranque MBR híbrido estándar (isohdpfx.bin)..."
    XORRISO_ARGS+=(
        -isohybrid-mbr "/usr/lib/ISOLINUX/isohdpfx.bin"
        --mbr-force-bootable
        -partition_cyl_align off
    )
fi

(
    cd "${ISO_EXTRACT_DIR}"
    xorriso "${XORRISO_ARGS[@]}" .
)

# ==============================================================================
# PASO 12: GENERACIÓN DE CHECKSUMS Y REPORTE FINAL
# ==============================================================================
log_step "Paso 12: Generando checksums criptográficos"

(
    cd "${OUT_DIR}"
    sha256sum "${ISO_OUTPUT_NAME}" > "${ISO_OUTPUT_NAME}.sha256"
)

ISO_SIZE="$(du -h "${FINAL_ISO_PATH}" | cut -f1)"
SHA256_HASH="$(cut -d' ' -f1 "${FINAL_ISO_PATH}.sha256")"

echo -e "\n${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}  ¡CONSTRUCCIÓN DE DEFOKOS COMPLETADA EXITOSAMENTE!${C_RESET}"
echo -e "${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}"
echo -e "${C_BOLD}Archivo ISO:     ${C_CYAN}${FINAL_ISO_PATH}${C_RESET}"
echo -e "${C_BOLD}Tamaño:          ${C_CYAN}${ISO_SIZE}${C_RESET}"
echo -e "${C_BOLD}SHA256:          ${C_CHARCOAL}${SHA256_HASH}${C_RESET}"
echo -e "${C_BOLD}Checksum File:   ${C_CYAN}${FINAL_ISO_PATH}.sha256${C_RESET}"
echo -e "${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}\n"
