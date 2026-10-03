#!/usr/bin/env bash
# ==============================================================================
#  DEFOKOS LINUX // MASTER COMPILATION ORCHESTRATOR (build.sh)
#  Construcción desde Cero: Sin ISOs precompiladas // Vía Repositorios Oficiales
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
  Utane Uta Edition // COSMIC Desktop // Compilación desde Repositorios
======================================================================
EOF
    echo -e "${C_RESET}"
}

# --- Ayuda preliminar sin requerir sudo ---
if [[ " $* " =~ " --help " ]] || [[ " $* " =~ " -h " ]]; then
    echo "Uso: sudo $0 [--repack] [--pack-only]"
    echo ""
    echo "Modo por defecto: Compilación total desde cero vía debootstrap noble"
    echo "y repositorios oficiales System76/Pop!_OS (Sin usar ISOs precompiladas)."
    echo ""
    echo "Opciones opcionales:"
    echo "  --repack                Aplica overlay al chroot existente y recompone la ISO (~2-3 min)"
    echo "  --pack-only             Omite aprovisionamiento y recompone la ISO directamente (~15 seg)"
    echo ""
    echo "Variables de entorno:"
    echo "  COMPRESSION     Algoritmo de compresión squashfs (zstd o xz, por defecto: zstd)"
    exit 0
fi

# --- Elevación Automática de Privilegios a Root ---
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

ISO_EXTRACT_DIR="${WORK_DIR}/iso_extracted"
CHROOT_DIR="${WORK_DIR}/squashfs_root"

# Metadatos de la ISO
DATE_TAG="$(date +%Y%m%d)"
DEFOKOS_VERSION="24.04"
ISO_OUTPUT_NAME="DefokOS-${DEFOKOS_VERSION}-amd64-${DATE_TAG}.iso"
VOLUME_LABEL="DEFOKOS_24_04"

# Parámetros y banderas inicializadas
PACK_ONLY=false
REPACK=false
COMPRESSION="${COMPRESSION:-zstd}"

while [[ $# -gt 0 ]]; do
    case "$1" in
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

REAL_USER="${SUDO_USER:-${USER}}"

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
        "${CHROOT_DIR}"; do
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
# PASO 0: LIMPIEZA INICIAL DEL ESPACIO DE TRABAJO
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]] && [[ "${REPACK}" != "true" ]]; then
    log_step "Paso 0: Purgando y limpiando espacio de trabajo anterior"

    set +e
    for mp in "${CHROOT_DIR}/run" "${CHROOT_DIR}/sys" "${CHROOT_DIR}/proc" "${CHROOT_DIR}/dev/pts" "${CHROOT_DIR}/dev" "${CHROOT_DIR}"; do
        if mountpoint -q "$mp" 2>/dev/null; then umount -lf "$mp" 2>/dev/null || true; fi
    done
    set -e

    rm -rf "${WORK_DIR}" "${OUT_DIR}" "${OVERLAY_DIR}" "${SCRIPTS_DIR}" "${ASSETS_DIR}" "${DEBS_DIR}"
fi

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${OVERLAY_DIR}" "${SCRIPTS_DIR}" "${ASSETS_DIR}" "${DEBS_DIR}" "${ISO_EXTRACT_DIR}"

# ==============================================================================
# PASO 1: INSTALACIÓN AUTOMÁTICA DE DEPENDENCIAS EN EL HOST
# ==============================================================================
log_step "Paso 1: Instalando y verificando herramientas necesarias en el host"

HOST_DEPS=(
    debootstrap
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
    coreutils
    grub-common
    grub-pc-bin
    grub-efi-amd64-bin
    isolinux
    syslinux-common
)

log_info "Asegurando dependencias en el sistema anfitrión..."
apt-get update -y
apt-get install -y --no-install-recommends "${HOST_DEPS[@]}"
log_success "Todas las dependencias del host están instaladas y listas."

# ==============================================================================
# PASO 2: RECOLECCIÓN DE ASSETS Y APLICACIONES (.DEB, FUENTES, FONDOS, ICONOS)
# ==============================================================================
log_step "Paso 2: Recolectando icono Defoko, fondo de arranque, fuentes y paquetes .deb"

# 1. Icono personalizado de Defoko
ICON_FOUND=""
for cand in \
    "/home/alex/Descargas/Pop!_OS_Icon.png" \
    "/home/${REAL_USER}/Descargas/Pop!_OS_Icon.png" \
    "${HOME}/Descargas/Pop!_OS_Icon.png"; do
    if [[ -f "$cand" ]]; then
        ICON_FOUND="$cand"
        break
    fi
done

if [[ -n "${ICON_FOUND}" ]]; then
    log_info "Utilizando icono fuente: ${ICON_FOUND}"
    cp -f "${ICON_FOUND}" "${ASSETS_DIR}/Pop!_OS_Icon.png"
fi

# 2. Fondo de arranque del sistema (systemd_defoko_background)
BG_FOUND=""
for cand in \
    "/home/alex/Descargas/systemd_defoko_background.jpeg" \
    "/home/${REAL_USER}/Descargas/systemd_defoko_background.jpeg" \
    "${HOME}/Descargas/systemd_defoko_background.jpeg"; do
    if [[ -f "$cand" ]]; then
        BG_FOUND="$cand"
        break
    fi
done

if [[ -n "${BG_FOUND}" ]]; then
    log_info "Procesando fondo temático de arranque: ${BG_FOUND}"
    cp -f "${BG_FOUND}" "${ASSETS_DIR}/systemd_defoko_background.jpeg"
    ffmpeg -y -i "${BG_FOUND}" -vf "scale=1920:1080" "${ASSETS_DIR}/boot_background_1080p.png" 2>/dev/null || true
    ffmpeg -y -i "${BG_FOUND}" -vf "scale=1920:1080" -pix_fmt bgr24 "${ASSETS_DIR}/splash.bmp" 2>/dev/null || true
    ffmpeg -y -i "${BG_FOUND}" -vf "scale=640:480" "${ASSETS_DIR}/isolinux_splash.png" 2>/dev/null || true
fi

# 3. Fuente Pixelify Sans
mkdir -p "${ASSETS_DIR}/fonts"
FONT_FILE="${ASSETS_DIR}/fonts/PixelifySans-VariableFont_wght.ttf"
if [[ -f "/home/alex/Descargas/Pixelify_Sans.zip" ]]; then
    unzip -p "/home/alex/Descargas/Pixelify_Sans.zip" "*PixelifySans*.ttf" > "${FONT_FILE}" 2>/dev/null || true
fi
if [[ ! -f "${FONT_FILE}" ]] || [[ $(stat -c%s "${FONT_FILE}" 2>/dev/null || echo 0) -lt 1000 ]]; then
    log_info "Descargando Pixelify Sans desde Google Fonts..."
    curl -fsSL --connect-timeout 15 -o "${FONT_FILE}" \
        "https://github.com/google/fonts/raw/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf" || true
fi

# 4. Paquetes nativos .deb (YouTube Music, Discord, Steam)
if [[ ! -f "${DEBS_DIR}/youtube-music.deb" ]]; then
    log_info "Descargando YouTube Music Desktop .deb oficial..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/youtube-music.deb" \
        "https://github.com/ytmdesktop/ytmdesktop/releases/download/v2.0.12/youtube-music-desktop-app_2.0.12_amd64.deb" || true
fi

if [[ ! -f "${DEBS_DIR}/discord.deb" ]]; then
    log_info "Descargando Discord .deb oficial..."
    curl -fsSL --connect-timeout 20 -o "${DEBS_DIR}/discord.deb" \
        "https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=linux&arch=x64&format=deb" || true
fi

if [[ ! -f "${DEBS_DIR}/steam.deb" ]]; then
    log_info "Descargando Steam .deb oficial..."
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
# PASO 3: GENERACIÓN DINÁMICA DE PLANTILLAS Y CONFIGURACIONES
# ==============================================================================
log_step "Paso 3: Generando estructura de overlay, temas y scripts de aprovisionamiento"

# --- 1. Generador de Iconos en Python ---
cat << 'EOF' > "${SCRIPTS_DIR}/generate-branding-icons.py"
#!/usr/bin/env python3
import os
import sys
import subprocess
import base64
import tempfile

def generate_icons(source_path, overlay_dir):
    if not os.path.exists(source_path):
        print(f"[ICONS:WARN] Archivo fuente no encontrado: {source_path}")
        return False

    sizes = [16, 22, 24, 32, 48, 64, 128, 256, 512]
    cache = {}

    with tempfile.TemporaryDirectory(prefix="defokos_icon_") as tmpdir:
        for s in sizes:
            png_tmp = os.path.join(tmpdir, f"pop_icon_{s}.png")
            try:
                subprocess.run(["convert", source_path, "-background", "none", "-resize", f"{s}x{s}", png_tmp], check=True)
                with open(png_tmp, "rb") as f:
                    data = f.read()
            except Exception as e:
                print(f"[ICONS:WARN] Error generando resolución {s}x{s}: {e}")
                continue

            b64 = base64.b64encode(data).decode("utf-8")
            svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{s}" height="{s}" viewBox="0 0 {s} {s}">
  <image width="{s}" height="{s}" xlink:href="data:image/png;base64,{b64}"/>
</svg>'''
            cache[s] = (data, svg)

    for s in sizes:
        if s not in cache:
            continue
        dim = f"{s}x{s}"
        places_dir = os.path.join(overlay_dir, "usr/share/icons/Pop", dim, "places")
        os.makedirs(places_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.svg", "distributor-logo.svg", "start-here-pop-os.svg", "pop-os-logo-icon.svg", "pop-os.svg"]:
            with open(os.path.join(places_dir, name), "w") as f:
                f.write(cache[s][1])

    for s in sizes:
        if s not in cache:
            continue
        dim = f"{s}x{s}"
        apps_dir = os.path.join(overlay_dir, "usr/share/icons/hicolor", dim, "apps")
        os.makedirs(apps_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
            with open(os.path.join(apps_dir, name), "wb") as f:
                f.write(cache[s][0])

    branding_dir = os.path.join(overlay_dir, "usr/share/icons/pop-os-branding")
    os.makedirs(branding_dir, exist_ok=True)
    if 512 in cache:
        with open(os.path.join(branding_dir, "pop_icon.svg"), "w") as f:
            f.write(cache[512][1])
    elif cache:
        largest = max(cache.keys())
        with open(os.path.join(branding_dir, "pop_icon.svg"), "w") as f:
            f.write(cache[largest][1])

    for s in [16, 22, 24, 32, 48, 64]:
        if s in cache:
            round_dir = os.path.join(branding_dir, f"round-logos/{s}")
            os.makedirs(round_dir, exist_ok=True)
            with open(os.path.join(round_dir, "distributor-logo.svg"), "w") as f:
                f.write(cache[s][1])

    if 256 in cache:
        apps_256 = os.path.join(branding_dir, "256x256/apps")
        os.makedirs(apps_256, exist_ok=True)
        with open(os.path.join(apps_256, "ubuntu-logo-icon.png"), "wb") as f:
            f.write(cache[256][0])

    pixmaps_dir = os.path.join(overlay_dir, "usr/share/pixmaps")
    os.makedirs(pixmaps_dir, exist_ok=True)
    best_px = cache.get(256, cache.get(128, None))
    if best_px:
        for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
            with open(os.path.join(pixmaps_dir, name), "wb") as f:
                f.write(best_px[0])
    subprocess.run(["cp", "-f", source_path, os.path.join(pixmaps_dir, "Pop!_OS_Icon.png")], check=False)

    pop_basic = os.path.join(overlay_dir, "usr/share/plymouth/themes/pop-basic")
    os.makedirs(pop_basic, exist_ok=True)
    if best_px:
        with open(os.path.join(pop_basic, "header-image.png"), "wb") as f:
            f.write(best_px[0])
        with open(os.path.join(pop_basic, "bgrt-fallback.png"), "wb") as f:
            f.write(best_px[0])

    spinner = os.path.join(overlay_dir, "usr/share/plymouth/themes/spinner")
    os.makedirs(spinner, exist_ok=True)
    if best_px:
        with open(os.path.join(spinner, "bgrt-fallback.png"), "wb") as f:
            f.write(best_px[0])
    try:
        subprocess.run(["convert", source_path, "-background", "none", "-resize", "x87", os.path.join(spinner, "watermark.png")], check=True)
    except Exception:
        pass

    grub_theme_dir = os.path.join(overlay_dir, "boot/grub/themes/pop")
    os.makedirs(grub_theme_dir, exist_ok=True)
    if 128 in cache:
        with open(os.path.join(grub_theme_dir, "logo.png"), "wb") as f:
            f.write(cache[128][0])

    calamares_dir = os.path.join(overlay_dir, "etc/calamares/branding/defokos")
    os.makedirs(calamares_dir, exist_ok=True)
    if 128 in cache:
        with open(os.path.join(calamares_dir, "logo.png"), "wb") as f:
            f.write(cache[128][0])
    return True

if __name__ == "__main__":
    src = sys.argv[1]
    tgt = sys.argv[2]
    generate_icons(src, tgt)
EOF
chmod +x "${SCRIPTS_DIR}/generate-branding-icons.py"

if [[ -f "${ASSETS_DIR}/Pop!_OS_Icon.png" ]]; then
    python3 "${SCRIPTS_DIR}/generate-branding-icons.py" "${ASSETS_DIR}/Pop!_OS_Icon.png" "${OVERLAY_DIR}" || true
fi

# --- 2. Overlay: Identificación del Sistema y Releases ---
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

# Sincronización robusta de llaves GPG de Pop!_OS y Ubuntu (host o keyserver)
mkdir -p "${OVERLAY_DIR}/etc/apt/trusted.gpg.d" "${OVERLAY_DIR}/usr/share/keyrings"

POP_KEY="${OVERLAY_DIR}/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg"
if [[ -s "/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg" ]]; then
    log_info "Copiando llave oficial de Pop!_OS desde el sistema anfitrión..."
    cp -f "/etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg" "${POP_KEY}"
elif [[ -s "/usr/share/keyrings/pop-archive-keyring.gpg" ]]; then
    log_info "Copiando llave oficial de Pop!_OS desde /usr/share/keyrings..."
    cp -f "/usr/share/keyrings/pop-archive-keyring.gpg" "${POP_KEY}"
else
    log_info "Descargando llave de Pop!_OS desde keyserver oficial de Ubuntu..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x63C46DF0140D738961429F4E204DD8AEC33A7AFF" | gpg --dearmor -o "${POP_KEY}" 2>/dev/null || true
fi
cp -f "${POP_KEY}" "${OVERLAY_DIR}/usr/share/keyrings/pop-archive-keyring.gpg" 2>/dev/null || true

UBUNTU_KEY="${OVERLAY_DIR}/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
if [[ -s "/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg" ]]; then
    log_info "Copiando llave oficial de Ubuntu desde el sistema anfitrión..."
    cp -f "/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg" "${UBUNTU_KEY}"
elif [[ -s "/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]]; then
    log_info "Copiando llave oficial de Ubuntu desde /usr/share/keyrings..."
    cp -f "/usr/share/keyrings/ubuntu-archive-keyring.gpg" "${UBUNTU_KEY}"
else
    log_info "Descargando llave de Ubuntu desde keyserver oficial..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x871920D1991BC93C" | gpg --dearmor -o "${UBUNTU_KEY}" 2>/dev/null || true
fi
cp -f "${UBUNTU_KEY}" "${OVERLAY_DIR}/usr/share/keyrings/ubuntu-archive-keyring.gpg" 2>/dev/null || true

# Verificación de integridad de las llaves
if [[ ! -s "${POP_KEY}" ]] || [[ $(stat -c%s "${POP_KEY}" 2>/dev/null || echo 0) -lt 500 ]]; then
    log_warn "Reintentando descarga de llave Pop!_OS desde keyserver..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x63C46DF0140D738961429F4E204DD8AEC33A7AFF" | gpg --dearmor -o "${POP_KEY}" 2>/dev/null || true
    cp -f "${POP_KEY}" "${OVERLAY_DIR}/usr/share/keyrings/pop-archive-keyring.gpg" 2>/dev/null || true
fi

# --- 4. Overlay: Configuración de Fuente por Defecto (Pixelify Sans) ---
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

if [[ -f "${FONT_FILE}" ]]; then
    cp -f "${FONT_FILE}" "${OVERLAY_DIR}/usr/share/fonts/truetype/pixelify-sans/"
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

# COSMIC Dock Favorites (Inyectar instalador al inicio del dock)
mkdir -p "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicAppList/v1" \
         "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicAppList/v1"

cat << 'EOF' > "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites"
[
    "io.calamares.calamares",
    "firefox",
    "com.system76.CosmicFiles",
    "com.system76.CosmicTerm",
    "com.system76.CosmicStore",
    "com.system76.CosmicSettings",
]
EOF
cp -f "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites" "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicAppList/v1/favorites"

# Fondo de Pantalla COSMIC Desktop
mkdir -p "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicBackground/v1" \
         "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicBackground/v1" \
         "${OVERLAY_DIR}/usr/share/backgrounds/cosmic"

cat << 'EOF' > "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicBackground/v1/all"
(
    output: "all",
    source: Path("/usr/share/backgrounds/systemd_defoko_background.jpeg"),
    filter_by_theme: false,
    rotation_frequency: 0,
    filter_method: Lanczos,
    scaling_mode: Zoom,
    sampling_method: Alphanumeric,
)
EOF
cp -f "${OVERLAY_DIR}/usr/share/cosmic/com.system76.CosmicBackground/v1/all" "${OVERLAY_DIR}/etc/skel/.config/cosmic/com.system76.CosmicBackground/v1/all"

# Greetd: Autologin directo al entorno COSMIC para la sesión Live
mkdir -p "${OVERLAY_DIR}/etc/greetd"
cat << 'EOF' > "${OVERLAY_DIR}/etc/greetd/cosmic-greeter.toml"
[terminal]
vt = "1"

[general]
service = "cosmic-greeter"

[initial_session]
command = "cosmic-session"
user = "defokos"

[default_session]
command = "cosmic-greeter-start"
user = "cosmic-greeter"
EOF

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
mkdir -p "${OVERLAY_DIR}/etc/calamares/modules" \
         "${OVERLAY_DIR}/etc/calamares/branding/defokos" \
         "${OVERLAY_DIR}/usr/share/applications" \
         "${OVERLAY_DIR}/etc/skel/Desktop" \
         "${OVERLAY_DIR}/etc/xdg/autostart" \
         "${OVERLAY_DIR}/usr/local/bin"

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/settings.conf"
---
modules-search:
  - /usr/lib/x86_64-linux-gnu/calamares/modules
  - /usr/share/calamares/modules
  - /usr/lib/calamares/modules
  - local

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

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/unpackfs.conf"
---
unpack:
    -   source: "/cdrom/casper/filesystem.squashfs"
        sourcefs: "squashfs"
        destination: ""
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/welcome.conf"
---
showSupportUrl:         true
showKnownIssuesUrl:     false
showReleaseNotesUrl:    false

requirements:
    requiredStorage:    8.0
    requiredRam:        1.0

    check:
        - storage
        - ram
        - power
        - root
    required:
        - root
        - storage
        - ram

geoip:
    style:  "none"
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/partition.conf"
---
efiSystemPartition: "/boot/efi"
userSwapChoices:
    - none
    - file
initialSwapChoice: file
drawNestedPartitions: true
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs"]
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/users.conf"
---
doAutologin: false
setRootPassword: false
sudoersGroup: sudo
defaultGroups:
    - adm
    - cdrom
    - dip
    - lpadmin
    - plugdev
    - sudo
    - audio
    - video
    - netdev
passwordRequirements:
    minLength: 1
    maxLength: -1
user:
  shell: /bin/bash
  forbidden_names: [ root ]
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/displaymanager.conf"
---
displaymanagers:
  - cosmic-greeter
  - greetd

defaultDesktopEnvironment:
    executable: "cosmic-session"
    desktopFile: "cosmic"

basicSetup: false
sysconfigSetup: false
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/networkcfg.conf"
---
type: "nm"
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/hwclock.conf"
---
setUtc: true
EOF

cat << 'EOF' > "${OVERLAY_DIR}/etc/calamares/modules/initramfs.conf"
---
kernel: ""
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

if [[ -f "${ASSETS_DIR}/boot_background_1080p.png" ]]; then
    cp -f "${ASSETS_DIR}/boot_background_1080p.png" "${OVERLAY_DIR}/etc/calamares/branding/defokos/welcome.png"
elif [[ -f "${OVERLAY_DIR}/etc/calamares/branding/defokos/logo.png" ]]; then
    cp -f "${OVERLAY_DIR}/etc/calamares/branding/defokos/logo.png" "${OVERLAY_DIR}/etc/calamares/branding/defokos/welcome.png"
fi

# Script lanzador resiliente para Wayland / Xwayland
cat << 'EOF' > "${OVERLAY_DIR}/usr/local/bin/calamares-launch"
#!/usr/bin/env bash
# ==============================================================================
# DEFOKOS LIVE INSTALLER LAUNCHER (Calamares)
# ==============================================================================
set -e

# Permitir conexiones al servidor X/Xwayland desde root
if command -v xhost >/dev/null 2>&1; then
    xhost +si:localuser:root 2>/dev/null || xhost + 2>/dev/null || true
fi

# Detectar y asegurar montaje del medio live en /cdrom
if [ ! -f /cdrom/casper/filesystem.squashfs ]; then
    for cand in /run/initramfs/cdrom /media/cdrom /mnt/cdrom /run/casper*; do
        if [ -f "$cand/casper/filesystem.squashfs" ]; then
            mkdir -p /cdrom
            mount --bind "$cand" /cdrom 2>/dev/null || ln -sfn "$cand" /cdrom 2>/dev/null || true
            break
        fi
    done
fi

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ -n "${WAYLAND_DISPLAY}" ] && [ -e "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
    chmod 666 "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" 2>/dev/null || true
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export QT_AUTO_SCREEN_SCALE_FACTOR=1

exec sudo -E env \
    DISPLAY="${DISPLAY}" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM}" \
    /usr/bin/calamares -d "$@"
EOF
chmod +x "${OVERLAY_DIR}/usr/local/bin/calamares-launch"

# Desktop Entry y Autostart
cat << 'EOF' > "${OVERLAY_DIR}/usr/share/applications/io.calamares.calamares.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Install DefokOS
GenericName=Live System Installer
Comment=Install DefokOS 24.04 LTS (Utane Uta Edition) to disk
Exec=/usr/local/bin/calamares-launch
Icon=distributor-logo-pop-os
Terminal=false
StartupNotify=true
Categories=System;
EOF

cp -f "${OVERLAY_DIR}/usr/share/applications/io.calamares.calamares.desktop" "${OVERLAY_DIR}/etc/skel/Desktop/install-defokos.desktop"
chmod +x "${OVERLAY_DIR}/etc/skel/Desktop/install-defokos.desktop"
cp -f "${OVERLAY_DIR}/usr/share/applications/io.calamares.calamares.desktop" "${OVERLAY_DIR}/etc/xdg/autostart/io.calamares.calamares.desktop"

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

# --- 9. Script de Aprovisionamiento en Chroot (chroot-setup.sh) ---
cat << 'EOF' > "${SCRIPTS_DIR}/chroot-setup.sh"
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "[CHROOT] Configurando arquitectura i386 para compatibilidad de 32-bit (Steam)..."
dpkg --add-architecture i386 || true

echo "[CHROOT] Asegurando certificados y herramientas base..."
apt-get update -y || true
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release software-properties-common

echo "[CHROOT] Verificando llaves oficiales de Pop!_OS y repositorios System76..."
mkdir -p /etc/apt/trusted.gpg.d /usr/share/keyrings
if [ ! -s /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg ] || [ $(stat -c%s /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg 2>/dev/null || echo 0) -lt 500 ]; then
    echo "[CHROOT] Descargando llave oficial de Pop!_OS desde keyserver..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x63C46DF0140D738961429F4E204DD8AEC33A7AFF" | gpg --dearmor -o /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg || true
fi
cp -f /etc/apt/trusted.gpg.d/pop-keyring-2017-archive.gpg /usr/share/keyrings/pop-archive-keyring.gpg 2>/dev/null || true

if [ ! -s /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg ] || [ $(stat -c%s /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg 2>/dev/null || echo 0) -lt 500 ]; then
    echo "[CHROOT] Descargando llave oficial de Ubuntu desde keyserver..."
    curl -fsSL --connect-timeout 15 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x871920D1991BC93C" | gpg --dearmor -o /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg || true
fi
cp -f /etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg /usr/share/keyrings/ubuntu-archive-keyring.gpg 2>/dev/null || true

add-apt-repository -y universe || true
add-apt-repository -y multiverse || true
add-apt-repository -y restricted || true

# Repositorio VSCodium
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

if ! apt-cache show pop-de-cosmic >/dev/null 2>&1; then
    echo "[CHROOT:WARN] pop-de-cosmic aún no aparece en cache. Verificando repositorios Pop!_OS..."
    apt-get update -y || true
fi

# Configurar live boot Casper
cat << 'EOCASPER' > /etc/casper.conf
export USERNAME="defokos"
export USERFULLNAME="DefokOS Live User"
export HOST="defokos"
export BUILD_SYSTEM="DefokOS"
EOCASPER

# Desinstalar bloatware
echo "[CHROOT] Purgando thunderbird, popsicle, xterm, gnome-terminal..."
apt-get purge -y thunderbird 'thunderbird-locale-*' popsicle popsicle-gtk xterm gnome-terminal gnome-terminal-data || true
rm -f /usr/share/applications/thunderbird.desktop /usr/share/applications/popsicle*.desktop /usr/share/applications/*xterm*.desktop /usr/share/applications/org.gnome.Terminal.desktop 2>/dev/null || true

# Lista de paquetes nativos esenciales
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
    codium
    fuse3
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
mkdir -p /etc/skel/Desktop /home/defokos/Desktop
if [ -f /usr/share/applications/io.calamares.calamares.desktop ]; then
    cp -f /usr/share/applications/io.calamares.calamares.desktop /etc/skel/Desktop/install-defokos.desktop
    cp -f /usr/share/applications/io.calamares.calamares.desktop /home/defokos/Desktop/install-defokos.desktop
    chmod +x /etc/skel/Desktop/install-defokos.desktop /home/defokos/Desktop/install-defokos.desktop 2>/dev/null || true
    chown -R defokos:defokos /home/defokos/Desktop 2>/dev/null || true
fi
chmod +x /usr/local/bin/calamares-launch 2>/dev/null || true

# Instalar display manager
systemctl enable cosmic-greeter.service 2>/dev/null || true
systemctl set-default graphical.target 2>/dev/null || true

# Instalación de paquetes .deb locales (YouTube Music, Discord, Steam)
DEBS_STAGE="/opt/defokos-packages"
if [[ -d "${DEBS_STAGE}" ]]; then
    for deb in "${DEBS_STAGE}"/*.deb; do
        if [[ -f "$deb" ]]; then
            echo "[CHROOT] Instalando paquete nativo $(basename "$deb")..."
            apt-get install -y --no-install-recommends "$deb" || apt-get install -f -y --no-install-recommends || true
        fi
    done
fi

# Flatpak soporte base
apt-get install -y --no-install-recommends flatpak || true
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak uninstall --system -y com.discordapp.Discord 2>/dev/null || true

# Permisos PreMiD
for ext in "/usr/lib/firefox/browser/extensions/support@premid.app.xpi" "/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/support@premid.app.xpi"; do
    if [[ -f "$ext" ]]; then chmod 644 "$ext" || true; fi
done

# Limpieza Profunda para mantener SquashFS por debajo de 3 GB
echo "[CHROOT] Optimizando y limpiando cachés para compresión compacta..."
rm -rf /var/lib/flatpak/runtime/* /var/lib/flatpak/app/* /var/lib/flatpak/.removed/* 2>/dev/null || true
apt-get autoremove -y --purge || true
apt-get clean -y || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /root/.cache/* /home/*/.cache/* 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true

echo "[CHROOT] Aprovisionamiento completado con éxito."
EOF
chmod +x "${SCRIPTS_DIR}/chroot-setup.sh"

# --- 10. Script de Tema (apply-theme.sh) ---
cat << 'EOF' > "${SCRIPTS_DIR}/apply-theme.sh"
#!/usr/bin/env bash
set -euo pipefail

echo "[THEME] Registrando Pixelify Sans en fc-cache..."
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv /usr/share/fonts/ 2>/dev/null || true
fi

if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme -R spinner 2>/dev/null || plymouth-set-default-theme -R pop-basic 2>/dev/null || true
fi

if command -v update-grub >/dev/null 2>&1; then
    update-grub 2>/dev/null || true
fi

echo "[THEME] Tema y fuentes aplicados correctamente."
EOF
chmod +x "${SCRIPTS_DIR}/apply-theme.sh"

log_success "Estructura de overlay y scripts dinámicos generados."

# ==============================================================================
# PASO 4: CONSTRUCCIÓN DEL SISTEMA BASE VÍA DEBOOTSTRAP NOBLE (DESDE CERO)
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]] && [[ "${REPACK}" != "true" ]]; then
    log_step "Paso 4: Construyendo el sistema raíz con debootstrap noble (Ubuntu 24.04 LTS)"

    rm -rf "${CHROOT_DIR}"
    mkdir -p "${CHROOT_DIR}"

    log_info "Descargando y construyendo chroot minimal con debootstrap..."
    if ! debootstrap --arch=amd64 --include=ca-certificates,curl,gnupg noble "${CHROOT_DIR}" http://apt.pop-os.org/ubuntu; then
        log_warn "Reintentando con mirror oficial de Ubuntu..."
        debootstrap --arch=amd64 --include=ca-certificates,curl,gnupg noble "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    fi
    log_success "Sistema base debootstrap completado con éxito."
fi

# ==============================================================================
# PASO 5: PREPARACIÓN DE MONTURAS VIRTUALES Y DNS EN CHROOT
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]]; then
    log_step "Paso 5: Configurando monturas virtuales (/dev, /proc, /sys, /run) y DNS"

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

    # Inyección de overlay en chroot
    log_info "Inyectando overlay temático en el chroot..."
    rsync -av "${OVERLAY_DIR}/" "${CHROOT_DIR}/"

    # ==============================================================================
    # PASO 6: EJECUCIÓN DE SCRIPTS DE APROVISIONAMIENTO Y COSMIC DESKTOP
    # ==============================================================================
    log_step "Paso 6: Aprovisionando COSMIC Desktop, Mesa, Vulkan, Pipewire y Apps .deb"

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
    log_success "Aprovisionamiento dentro del chroot completado."

    # ==============================================================================
    # PASO 7: DESMONTAJE SEGURO DEL CHROOT
    # ==============================================================================
    log_step "Paso 7: Desmontando sistemas de archivos virtuales"

    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d"
    rm -f "${CHROOT_DIR}/etc/resolv.conf"
    ln -sf /run/systemd/resolve/stub-resolv.conf "${CHROOT_DIR}/etc/resolv.conf" 2>/dev/null || true

    umount -lf "${CHROOT_DIR}/run" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}" 2>/dev/null || true
    log_success "Chroot desmontado limpiamente."
fi

# ==============================================================================
# PASO 8: PREPARACIÓN DEL ÁRBOL BOOTEABLE LIVE ISO
# ==============================================================================
log_step "Paso 8: Estructurando árbol Live (Kernel, Initrd, GRUB y Bootloader UEFI/BIOS)"

mkdir -p "${ISO_EXTRACT_DIR}/casper"
mkdir -p "${ISO_EXTRACT_DIR}/boot/grub/themes/pop"
mkdir -p "${ISO_EXTRACT_DIR}/EFI/BOOT"
mkdir -p "${ISO_EXTRACT_DIR}/isolinux"

# 1. Sincronizar Kernel e Initramfs desde el chroot
LATEST_KERNEL=$(ls -t "${CHROOT_DIR}/boot/vmlinuz"* 2>/dev/null | head -n1 || true)
LATEST_INITRD=$(ls -t "${CHROOT_DIR}/boot/initrd.img"* 2>/dev/null | head -n1 || true)

if [[ -z "${LATEST_KERNEL}" ]] || [[ -z "${LATEST_INITRD}" ]]; then
    log_err "No se encontró el kernel o initrd en ${CHROOT_DIR}/boot/."
    exit 1
fi

log_info "Copiando kernel: $(basename "${LATEST_KERNEL}")..."
cp -f "${LATEST_KERNEL}" "${ISO_EXTRACT_DIR}/casper/vmlinuz"

log_info "Copiando initrd: $(basename "${LATEST_INITRD}")..."
cp -f "${LATEST_INITRD}" "${ISO_EXTRACT_DIR}/casper/initrd"

# 2. Generación del binario EFI (BOOTX64.EFI) con GRUB standalone
log_info "Compilando binario de arranque UEFI con GRUB standalone..."
cat << 'EOF' > "${WORK_DIR}/grub-embedded.cfg"
search --file --set=root /casper/vmlinuz
set prefix=($root)/boot/grub
source $prefix/grub.cfg
EOF

if command -v grub-mkstandalone >/dev/null 2>&1; then
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${ISO_EXTRACT_DIR}/EFI/BOOT/BOOTX64.EFI" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${WORK_DIR}/grub-embedded.cfg"
else
    chroot "${CHROOT_DIR}" grub-mkstandalone \
        --format=x86_64-efi \
        --output="/boot/bootx64.efi" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${WORK_DIR}/grub-embedded.cfg"
    cp -f "${CHROOT_DIR}/boot/bootx64.efi" "${ISO_EXTRACT_DIR}/EFI/BOOT/BOOTX64.EFI"
fi

# 3. Creación de imagen de partición EFI efi.img para El Torito
log_info "Generando imagen FAT efi.img para arranque UEFI El Torito..."
dd if=/dev/zero of="${ISO_EXTRACT_DIR}/boot/grub/efi.img" bs=1k count=8192 status=none
mkfs.vfat -F 12 "${ISO_EXTRACT_DIR}/boot/grub/efi.img" >/dev/null
mmd -i "${ISO_EXTRACT_DIR}/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "${ISO_EXTRACT_DIR}/boot/grub/efi.img" "${ISO_EXTRACT_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI

# 4. Configuración de Menú de Arranque GRUB (grub.cfg)
cat << 'EOF' > "${ISO_EXTRACT_DIR}/boot/grub/grub.cfg"
set timeout=10
set default=0

insmod font
insmod efi_gop
insmod efi_uga
insmod gfxterm
insmod png
insmod gfxmenu

terminal_output gfxterm

if [ -f /boot/grub/themes/pop/background.png ]; then
    background_image /boot/grub/themes/pop/background.png
fi

menuentry "DefokOS 24.04 LTS (Utane Uta Edition) - COSMIC Desktop" --class defokos --class pop-os {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "DefokOS 24.04 LTS (Safe Graphics)" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}
EOF

# 5. Configuración de Cargador BIOS tradicional con ISOLINUX
if [[ -f /usr/lib/ISOLINUX/isolinux.bin ]]; then
    cp -f /usr/lib/ISOLINUX/isolinux.bin "${ISO_EXTRACT_DIR}/isolinux/"
    cp -f /usr/lib/syslinux/modules/bios/*.c32 "${ISO_EXTRACT_DIR}/isolinux/" 2>/dev/null || true

    if [[ -f "${ASSETS_DIR}/isolinux_splash.png" ]]; then
        cp -f "${ASSETS_DIR}/isolinux_splash.png" "${ISO_EXTRACT_DIR}/isolinux/splash.png"
    fi

    cat << 'EOF' > "${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
UI vesamenu.c32
TIMEOUT 100
PROMPT 0

MENU TITLE DefokOS 24.04 LTS (Utane Uta Edition)
MENU BACKGROUND splash.png
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #90b49fcc #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 none

LABEL live
  MENU LABEL ^Probar o Instalar DefokOS 24.04 (COSMIC Desktop)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---

LABEL safe
  MENU LABEL ^DefokOS 24.04 (Graficos Seguros / Safe Graphics)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper nomodeset quiet splash ---
EOF
fi

# 6. Sincronizar fondos y logos en el árbol de arranque de la ISO
if [[ -f "${ASSETS_DIR}/boot_background_1080p.png" ]]; then
    cp -f "${ASSETS_DIR}/boot_background_1080p.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/background.png"
fi
if [[ -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" ]]; then
    cp -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/logo.png"
fi
if [[ -f "${ASSETS_DIR}/splash.bmp" ]]; then
    cp -f "${ASSETS_DIR}/splash.bmp" "${ISO_EXTRACT_DIR}/splash.bmp"
fi

# ==============================================================================
# PASO 9: COMPRESIÓN SQUASHFS DEL SISTEMA DE ARCHIVOS
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]]; then
    log_step "Paso 9: Comprimiendo filesystem.squashfs con compresión ${COMPRESSION}"

    SQUASHFS_FILE="${ISO_EXTRACT_DIR}/casper/filesystem.squashfs"
    rm -f "${SQUASHFS_FILE}"

    # Metadata de la imagen
    printf $(du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1) > "${ISO_EXTRACT_DIR}/casper/filesystem.size"
    chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package} ${Version}\n' > "${ISO_EXTRACT_DIR}/casper/filesystem.manifest" 2>/dev/null || true
    cp -f "${ISO_EXTRACT_DIR}/casper/filesystem.manifest" "${ISO_EXTRACT_DIR}/casper/filesystem.manifest-desktop" 2>/dev/null || true

    MKSQUASHFS_OPTS=(-noappend -b 1048576 -always-use-fragments)
    if [[ "${COMPRESSION}" == "zstd" ]]; then
        MKSQUASHFS_OPTS+=(-comp zstd -Xcompression-level 19)
    elif [[ "${COMPRESSION}" == "xz" ]]; then
        MKSQUASHFS_OPTS+=(-comp xz)
    else
        MKSQUASHFS_OPTS+=(-comp gzip)
    fi

    log_info "Generando filesystem.squashfs (esto puede tardar unos minutos)..."
    mksquashfs "${CHROOT_DIR}" "${SQUASHFS_FILE}" "${MKSQUASHFS_OPTS[@]}"
    log_success "filesystem.squashfs generado exitosamente."

    (
        cd "${ISO_EXTRACT_DIR}"
        rm -f md5sum.txt
        find . -type f ! -path "./md5sum.txt" ! -path "./boot.catalog" -exec md5sum {} + > md5sum.txt
    )
fi

# ==============================================================================
# PASO 10: CREACIÓN DE ISO HÍBRIDA BOOTEABLE CON XORRISO
# ==============================================================================
log_step "Paso 10: Creando imagen ISO híbrida (UEFI + BIOS) con xorriso"

FINAL_ISO_PATH="${OUT_DIR}/${ISO_OUTPUT_NAME}"
rm -f "${FINAL_ISO_PATH}"

XORRISO_ARGS=(
    -as mkisofs
    -r
    -V "${VOLUME_LABEL}"
    -o "${FINAL_ISO_PATH}"
    -J -l
)

if [[ -f "${ISO_EXTRACT_DIR}/isolinux/isolinux.bin" ]]; then
    XORRISO_ARGS+=(
        -b isolinux/isolinux.bin
        -c isolinux/boot.cat
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
fi

if [[ -f "${ISO_EXTRACT_DIR}/boot/grub/efi.img" ]]; then
    XORRISO_ARGS+=(
        -eltorito-alt-boot
        -e boot/grub/efi.img
        -no-emul-boot
        -boot-load-size 8192
        -isohybrid-gpt-basdat
    )
fi

if [[ -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]]; then
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
# PASO 11: CHECKSUMS Y REPORTE FINAL
# ==============================================================================
log_step "Paso 11: Generando checksums criptográficos"

(
    cd "${OUT_DIR}"
    sha256sum "${ISO_OUTPUT_NAME}" > "${ISO_OUTPUT_NAME}.sha256"
)

ISO_SIZE="$(du -h "${FINAL_ISO_PATH}" | cut -f1)"
SHA256_HASH="$(cut -d' ' -f1 "${FINAL_ISO_PATH}.sha256")"

echo -e "\n${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}  ¡CONSTRUCCIÓN DE DEFOKOS DESDE CERO COMPLETADA EXITOSAMENTE!${C_RESET}"
echo -e "${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}"
echo -e "${C_BOLD}Archivo ISO:     ${C_CYAN}${FINAL_ISO_PATH}${C_RESET}"
echo -e "${C_BOLD}Tamaño:          ${C_CYAN}${ISO_SIZE}${C_RESET}"
echo -e "${C_BOLD}SHA256:          ${C_CHARCOAL}${SHA256_HASH}${C_RESET}"
echo -e "${C_BOLD}Checksum File:   ${C_CYAN}${FINAL_ISO_PATH}.sha256${C_RESET}"
echo -e "${C_BOLD}${C_LAVENDER}======================================================================${C_RESET}\n"
