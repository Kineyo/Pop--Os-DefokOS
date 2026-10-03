#!/usr/bin/env bash
# ==============================================================================
#  DEFOKOS // DISTRO BUILD SYSTEM (build.sh)
#  Generador de ISO personalizada basada en Pop!_OS con COSMIC Desktop
#  Temática: Defoko / Utane Uta (#b49fcc & #24272e)
# ==============================================================================

set -euo pipefail

# --- Colores para la interfaz de consola ---
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_LAVENDER="\033[38;2;180;159;204m"
C_CHARCOAL="\033[38;2;111;115;126m"
C_CYAN="\033[38;2;136;192;208m"
C_GREEN="\033[38;2;142;192;156m"
C_YELLOW="\033[38;2;222;193;138m"
C_RED="\033[38;2;216;124;149m"

log_banner() {
    echo -e "${C_LAVENDER}${C_BOLD}"
    cat << 'EOF'
  ██████╗ ███████╗███████╗ ██████╗ ██╗  ██╗ ██████╗ ███████╗
  ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║ ██╔╝██╔═══██╗██╔════╝
  ██║  ██║█████╗  █████╗  ██║   ██║█████═╝ ██║   ██║███████╗
  ██║  ██║██╔══╝  ██╔══╝  ██║   ██║██╔═██╗ ██║   ██║╚════██║
  ██████╔╝███████╗██║     ╚██████╔╝██║ ╚██╗╚██████╔╝███████║
  ╚═════╝ ╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
      [ UTANE UTA // VOICE SYNTHESIS & DEV WORKSTATION ]
EOF
    echo -e "${C_RESET}"
}

log_info()    { echo -e "${C_BOLD}${C_LAVENDER}[BUILD:INFO]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
log_success() { echo -e "${C_BOLD}${C_GREEN}[BUILD:OK]${C_RESET} $*"; }
log_warn()    { echo -e "${C_BOLD}${C_YELLOW}[BUILD:WARN]${C_RESET} $*"; }
log_err()     { echo -e "${C_BOLD}${C_RED}[BUILD:ERROR]${C_RESET} $*" >&2; }

# --- Ayuda preliminar sin requerir sudo ---
if [[ " $* " =~ " --help " ]] || [[ " $* " =~ " -h " ]]; then
    echo "Uso: sudo $0 [--bootstrap] [--repack] [--pack-only] [--iso /ruta/a/base.iso]"
    echo ""
    echo "Opciones:"
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

# --- Verificación de privilegios de superusuario ---
if [[ "${EUID}" -ne 0 ]]; then
    log_err "Este script requiere privilegios de root para administrar chroot, montajes y permisos."
    log_err "Por favor, ejecútalo con: sudo $0"
    exit 1
fi

# --- Variables y Rutas del Proyecto ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROJECT_ROOT}/work"
OUT_DIR="${PROJECT_ROOT}/out"
OVERLAY_DIR="${PROJECT_ROOT}/overlay"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

ISO_MOUNT_DIR="${WORK_DIR}/iso_mount"
ISO_EXTRACT_DIR="${WORK_DIR}/iso_extracted"
CHROOT_DIR="${WORK_DIR}/squashfs_root"

# URL oficial de la ISO base Pop!_OS 24.04 LTS con COSMIC Desktop (Wayland)
DEFAULT_BASE_URL="https://iso.pop-os.org/24.04/amd64/generic/28/pop-os_24.04_amd64_generic_28.iso"
BASE_ISO_URL="${BASE_ISO_URL:-${DEFAULT_BASE_URL}}"

# Nombre de la ISO resultante
DATE_TAG="$(date +%Y%m%d)"
DEFOKOS_VERSION="24.04"
ISO_OUTPUT_NAME="DefokOS-${DEFOKOS_VERSION}-amd64-${DATE_TAG}.iso"
VOLUME_LABEL="DEFOKOS_24_04"

# Parámetros opcionales
LOCAL_BASE_ISO=""
BOOTSTRAP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --help|-h)
            echo "Uso: sudo $0 [--bootstrap] [--repack] [--pack-only] [--iso /ruta/a/base.iso]"
            echo ""
            echo "Opciones:"
            echo "  --bootstrap             Construye el sistema desde cero vía debootstrap y repositorios oficiales System76"
            echo "  --repack                Aplica overlay al chroot existente y recomprime SquashFS e ISO (~2-3 min)"
            echo "  --pack-only             Omite aprovisionamiento y SquashFS; empaqueta la ISO directamente (~10 seg)"
            echo "  --iso /ruta/a/base.iso  Usa una imagen base local existente"
            echo ""
            echo "Variables de entorno opcionales:"
            echo "  BASE_ISO_URL    URL para descargar la ISO base si no se especifica --iso ni --bootstrap"
            echo "  COMPRESSION     Algoritmo de compresión para squashfs (zstd o xz, por defecto: zstd)"
            exit 0
            ;;
        *)
            log_err "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

COMPRESSION="${COMPRESSION:-zstd}"

# Auto-detección inteligente de la ISO oficial local de Pop!_OS 24.04
if [[ -z "${LOCAL_BASE_ISO}" ]]; then
    REAL_USER="${SUDO_USER:-${USER}}"
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
    # Desmontar puntos de montaje chroot en orden inverso
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

    # Retirar policy-rc.d temporal si sobrevivió a un fallo
    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        log_err "La construcción falló con código de salida: $exit_code"
    fi
    exit $exit_code
}
trap cleanup_mounts EXIT INT TERM

log_banner

# ==============================================================================
# PASO 1: VERIFICACIÓN DE DEPENDENCIAS DEL HOST
# ==============================================================================
log_step "Paso 1: Verificando herramientas necesarias en el host"

DEPENDENCIES=(xorriso mksquashfs unsquashfs curl rsync sha256sum awk du)
MISSING_DEPS=()

for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    log_err "Faltan las siguientes dependencias en el sistema anfitrión: ${MISSING_DEPS[*]}"
    log_err "Instálalas con: apt-get update && apt-get install -y xorriso squashfs-tools curl rsync coreutils"
    exit 1
fi
log_success "Todas las dependencias del host están presentes."

# ==============================================================================
# PASO 2: PREPARACIÓN DE DIRECTORIOS DE TRABAJO
# ==============================================================================
log_step "Paso 2: Preparando espacio de trabajo"

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${ISO_MOUNT_DIR}" "${ISO_EXTRACT_DIR}"
log_info "Directorio de trabajo: ${WORK_DIR}"
log_info "Directorio de salida:   ${OUT_DIR}"

if [[ "${PACK_ONLY}" == "true" ]]; then
    log_info "Modo --pack-only activado."
    log_info "Omitiendo descarga, aprovisionamiento chroot y compresión de SquashFS."
    if [[ ! -d "${ISO_EXTRACT_DIR}" ]]; then
        log_err "No se encontró el directorio extraído: ${ISO_EXTRACT_DIR}."
        log_err "Debes ejecutar una compilación completa al menos una vez antes de usar --pack-only."
        exit 1
    fi
elif [[ "${REPACK}" == "true" ]]; then
    log_info "Modo --repack activado."
    log_info "Reutilizando chroot y árbol ISO existentes..."
    if [[ ! -d "${CHROOT_DIR}" ]] || [[ ! -d "${ISO_EXTRACT_DIR}" ]]; then
        log_err "No se encontraron los directorios de trabajo previos (${CHROOT_DIR})."
        log_err "Debes ejecutar una compilación completa al menos una vez antes de usar --repack."
        exit 1
    fi
    SQUASHFS_IMAGE=""
    for candidate in \
        "${ISO_EXTRACT_DIR}/casper/filesystem.squashfs" \
        "${ISO_EXTRACT_DIR}/live/filesystem.squashfs" \
        "${ISO_EXTRACT_DIR}"/casper*/filesystem.squashfs; do
        if [[ -f "$candidate" ]]; then
            SQUASHFS_IMAGE="$(realpath "$candidate")"
            break
        fi
    done
elif [[ "${BOOTSTRAP}" == "true" ]]; then
    log_info "Modo --bootstrap activado: Construyendo imagen base desde repositorios oficiales..."
    if ! command -v debootstrap >/dev/null 2>&1; then
        log_info "Instalando debootstrap en el sistema host..."
        apt-get update -y && apt-get install -y debootstrap
    fi

    # Limpiar y preparar chroot para construcción limpia
    if [[ -d "${CHROOT_DIR}" ]]; then
        log_warn "Eliminando chroot anterior para una instalación limpia..."
        rm -rf "${CHROOT_DIR}"
    fi
    mkdir -p "${CHROOT_DIR}"

    log_info "Ejecutando debootstrap noble (Ubuntu 24.04 LTS base)..."
    if ! debootstrap --arch=amd64 noble "${CHROOT_DIR}" http://apt.pop-os.org/ubuntu; then
        log_warn "Fallo con mirror de Pop!_OS. Reintentando con mirror oficial de Ubuntu..."
        debootstrap --arch=amd64 noble "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    fi

    mkdir -p "${ISO_EXTRACT_DIR}/casper"
    SQUASHFS_IMAGE="${ISO_EXTRACT_DIR}/casper/filesystem.squashfs"
else

# ==============================================================================
# PASO 3: OBTENCIÓN DE LA ISO BASE
# ==============================================================================
log_step "Paso 3: Localizando o descargando la ISO base de Pop!_OS"

NEED_DOWNLOAD=false

# 1. Si el usuario especificó una ISO local con --iso
if [[ -n "${LOCAL_BASE_ISO}" ]]; then
    if [[ ! -f "${LOCAL_BASE_ISO}" ]]; then
        log_err "El archivo especificado con --iso no existe: ${LOCAL_BASE_ISO}"
        exit 1
    fi
    LOCAL_SIZE=$(stat -c%s "${LOCAL_BASE_ISO}" 2>/dev/null || echo 0)
    if [[ $LOCAL_SIZE -lt 500000000 ]]; then
        log_err "El archivo ${LOCAL_BASE_ISO} es demasiado pequeño ($(( LOCAL_SIZE / 1024 / 1024 )) MB). Parece estar incompleto o dañado."
        exit 1
    fi
    log_info "Usando ISO local provista por el usuario: ${LOCAL_BASE_ISO} ($(( LOCAL_SIZE / 1024 / 1024 )) MB)"
    BASE_ISO_FILE="${LOCAL_BASE_ISO}"

# 2. Si ya existe un archivo base.iso en work/
elif [[ -f "${BASE_ISO_FILE}" ]]; then
    CACHED_SIZE=$(stat -c%s "${BASE_ISO_FILE}" 2>/dev/null || echo 0)
    # Detectar si la imagen en caché pertenece a la versión 22.04 anterior (GNOME/X11)
    if file "${BASE_ISO_FILE}" 2>/dev/null | grep -qi "22\.04"; then
        log_warn "Se detectó que la ISO en caché es Pop!_OS 22.04 (versión previa con GNOME/X11)."
        log_warn "Purgando caché antigua para actualizar a Pop!_OS 24.04 LTS con COSMIC Desktop nativo..."
        rm -f "${BASE_ISO_FILE}"
        rm -rf "${ISO_EXTRACT_DIR}" "${CHROOT_DIR}"
        NEED_DOWNLOAD=true
    elif [[ $CACHED_SIZE -lt 500000000 ]]; then
        log_warn "Se encontró un archivo base.iso en caché pero está incompleto o dañado ($(( CACHED_SIZE / 1024 / 1024 )) MB)."
        log_warn "Eliminándolo y procediendo a descargar la imagen oficial..."
        rm -f "${BASE_ISO_FILE}"
        NEED_DOWNLOAD=true
    else
        log_info "Se encontró una imagen base válida en caché: ${BASE_ISO_FILE} ($(( CACHED_SIZE / 1024 / 1024 )) MB)"
        NEED_DOWNLOAD=false
    fi
else
    NEED_DOWNLOAD=true
fi

# 3. Descarga oficial si no se dispone de imagen local válida
if [[ "${NEED_DOWNLOAD}" == "true" ]]; then
    log_info "Descargando imagen ISO base desde:"
    log_info "  ${BASE_ISO_URL}"
    rm -f "${BASE_ISO_FILE}.tmp"
    if ! curl -L -C - --fail --progress-bar -o "${BASE_ISO_FILE}.tmp" "${BASE_ISO_URL}"; then
        log_err "Error crítico al descargar la ISO base (Código de salida de curl: $?)."
        log_err "URL intentada: ${BASE_ISO_URL}"
        log_err "Posibles causas:"
        log_err "  1. La máquina no tiene conexión a Internet o falló la resolución DNS (código 6)."
        log_err "  2. El enlace remoto ha caducado o cambió."
        log_err "Solución: Puedes descargar manualmente cualquier ISO de Pop!_OS y ejecutar:"
        log_err "  sudo $0 --iso /ruta/a/tu/imagen.iso"
        rm -f "${BASE_ISO_FILE}.tmp" 2>/dev/null || true
        exit 6
    fi
    mv "${BASE_ISO_FILE}.tmp" "${BASE_ISO_FILE}"
    log_success "Descarga de ISO base completada exitosamente."
fi

# ==============================================================================
# PASO 4: EXTRACCIÓN DE LA ISO Y METADATOS DE ARRANQUE (EL TORITO)
# ==============================================================================
log_step "Paso 4: Extrayendo contenido de la ISO base y geometría de arranque"

if [[ ! -f "${BASE_ISO_FILE}" ]]; then
    log_err "No se encontró el archivo ISO requerido: ${BASE_ISO_FILE}"
    exit 1
fi

# Extraer parámetros exactos de arranque con xorriso para garantizar booteo EFI y BIOS
BOOT_OPTS_FILE="${WORK_DIR}/el_torito_opts.txt"
log_info "Analizando estructura híbrida de arranque con xorriso..."
xorriso -indev "${BASE_ISO_FILE}" -report_el_torito as_mkisofs > "${BOOT_OPTS_FILE}" 2>/dev/null || true

# Extracción de la ISO (Primero intenta montaje loop; si el kernel o entorno falla, usa xorriso directo)
log_info "Extrayendo árbol de archivos de la ISO base..."
mkdir -p "${ISO_MOUNT_DIR}" "${ISO_EXTRACT_DIR}"

if mount -o loop,ro "${BASE_ISO_FILE}" "${ISO_MOUNT_DIR}" 2>/dev/null; then
    log_info "Montaje loop exitoso. Sincronizando árbol con rsync..."
    rsync -a --delete --info=progress2 "${ISO_MOUNT_DIR}/" "${ISO_EXTRACT_DIR}/"
    umount -lf "${ISO_MOUNT_DIR}" 2>/dev/null || true
    log_success "Árbol de la ISO extraído correctamente vía loop mount."
else
    log_warn "El montaje loop no estuvo disponible (código 32 o entorno restringido). Extrayendo directamente con xorriso..."
    rm -rf "${ISO_EXTRACT_DIR:?}"/* 2>/dev/null || true
    xorriso -osirrox on -indev "${BASE_ISO_FILE}" -extract / "${ISO_EXTRACT_DIR}" 2>/dev/null
    chmod -R u+w "${ISO_EXTRACT_DIR}"
    log_success "Árbol de la ISO extraído correctamente vía xorriso."
fi

# ==============================================================================
# PASO 5: DESCOMPRESIÓN DEL SISTEMA DE ARCHIVOS SQUASHFS
# ==============================================================================
log_step "Paso 5: Descomprimiendo filesystem.squashfs"

SQUASHFS_IMAGE=""
for candidate in \
    "${ISO_EXTRACT_DIR}/casper/filesystem.squashfs" \
    "${ISO_EXTRACT_DIR}/live/filesystem.squashfs"; do
    if [[ -f "$candidate" ]]; then
        SQUASHFS_IMAGE="$candidate"
        break
    fi
done

if [[ -z "${SQUASHFS_IMAGE}" ]]; then
    log_err "No se pudo localizar filesystem.squashfs dentro de la ISO extraída."
    exit 1
fi

log_info "SquashFS detectado en: ${SQUASHFS_IMAGE}"

if [[ -d "${CHROOT_DIR}" ]]; then
    log_warn "El directorio chroot anterior (${CHROOT_DIR}) ya existe. Eliminándolo para una build limpia..."
    rm -rf "${CHROOT_DIR}"
fi

log_info "Descomprimiendo SquashFS en: ${CHROOT_DIR} (esto puede tomar un par de minutos)..."
unsquashfs -f -d "${CHROOT_DIR}" "${SQUASHFS_IMAGE}"
log_success "SquashFS descomprimido."
fi

# ==============================================================================
# PASO 6: PREPARACIÓN DEL ENTORNO CHROOT Y MONTURAS BIND
# ==============================================================================
if [[ "${PACK_ONLY}" != "true" ]]; then
log_step "Paso 6: Preparando monturas virtuales y políticas en chroot"

# Configurar resolución DNS temporal en chroot
# Importante: /etc/resolv.conf en hosts modernos apunta a 127.0.0.53 (systemd-resolved stub),
# el cual NO se ejecuta dentro del chroot. Debemos usar los DNS reales y públicos.
rm -f "${CHROOT_DIR}/etc/resolv.conf"
if [[ -f /run/systemd/resolve/resolv.conf ]]; then
    # Copiar servidores DNS upstream reales de systemd-resolved
    cp -L /run/systemd/resolve/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
elif [[ -f /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
fi

# Eliminar 127.0.0.53 si fue copiado para evitar cuelgues o fallas de resolución
if [[ -f "${CHROOT_DIR}/etc/resolv.conf" ]]; then
    sed -i '/127\.0\.0\.53/d' "${CHROOT_DIR}/etc/resolv.conf" 2>/dev/null || true
fi

# Garantizar DNS públicos de alta disponibilidad (Cloudflare y Google)
cat << 'EOF' >> "${CHROOT_DIR}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
log_info "Configuración DNS en chroot establecida con éxito."

# Prevenir que servicios/daemons arranquen durante la instalación de paquetes
cat << 'EOF' > "${CHROOT_DIR}/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "${CHROOT_DIR}/usr/sbin/policy-rc.d"

# Convertir el chroot en un punto de montaje con propagación slave
# Esto permite que bubblewrap (bwrap) y flatpak puedan gestionar namespaces sin error 'Failed to make / slave'
mount --bind "${CHROOT_DIR}" "${CHROOT_DIR}"
mount --make-rslave "${CHROOT_DIR}"

# Montar sistemas de archivos virtuales requeridos por apt, dkms, systemd y flatpak
log_info "Montando /dev, /proc, /sys y /run en chroot..."
mount --bind /dev "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sysfs "${CHROOT_DIR}/sys"
mount -t tmpfs tmpfs "${CHROOT_DIR}/run"

# ==============================================================================
# PASO 7: APLICACIÓN DEL OVERLAY DEL SISTEMA
# ==============================================================================
log_step "Paso 7: Sincronizando capas del overlay (dotfiles, fondos, schemas)"

if [[ -d "${OVERLAY_DIR}" ]]; then
    # Sincronizar iconos de branding desde assets si está presente
    if [[ -f "${PROJECT_ROOT}/assets/Pop!_OS_Icon.png" ]]; then
        log_info "Sincronizando iconos de branding desde assets/Pop!_OS_Icon.png..."
        python3 "${SCRIPTS_DIR}/generate-branding-icons.py" "${PROJECT_ROOT}/assets/Pop!_OS_Icon.png" "${OVERLAY_DIR}" 2>/dev/null || true
    fi

    log_info "Inyectando overlay desde ${OVERLAY_DIR} hacia ${CHROOT_DIR}..."
    rsync -av "${OVERLAY_DIR}/" "${CHROOT_DIR}/"
    log_success "Overlay inyectado exitosamente."

    # Sincronizar fondo, logotipo y título del menú de arranque en la ISO extraída
    log_info "Sincronizando menú y fondo de arranque en la imagen ISO..."
    if [[ -d "${ISO_EXTRACT_DIR}/boot/grub/themes/pop" ]]; then
        if [[ -f "${PROJECT_ROOT}/assets/boot_background_1080p.png" ]]; then
            cp -f "${PROJECT_ROOT}/assets/boot_background_1080p.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/background.png"
        fi
        if [[ -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" ]]; then
            cp -f "${OVERLAY_DIR}/boot/grub/themes/pop/logo.png" "${ISO_EXTRACT_DIR}/boot/grub/themes/pop/logo.png"
        fi
    fi
    if [[ -f "${OVERLAY_DIR}/boot/efi/splash.bmp" ]]; then
        cp -f "${OVERLAY_DIR}/boot/efi/splash.bmp" "${ISO_EXTRACT_DIR}/splash.bmp" 2>/dev/null || true
        mkdir -p "${ISO_EXTRACT_DIR}/boot/efi" 2>/dev/null || true
        cp -f "${OVERLAY_DIR}/boot/efi/splash.bmp" "${ISO_EXTRACT_DIR}/boot/efi/splash.bmp" 2>/dev/null || true
    fi
    if [[ -f "${ISO_EXTRACT_DIR}/boot/grub/grub.cfg" ]]; then
        sed -i 's/Try or Install Pop_OS/DefokOS 24.04 LTS (Utane Uta Edition) - COSMIC Desktop/g' "${ISO_EXTRACT_DIR}/boot/grub/grub.cfg"
    fi
    if [[ -f "${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg" ]]; then
        sed -i 's/default pop-os/default defokos/g; s/label pop-os/label defokos/g' "${ISO_EXTRACT_DIR}/isolinux/isolinux.cfg"
    fi
else
    log_warn "No se encontró el directorio overlay (${OVERLAY_DIR}). Omitiendo..."
fi

# ==============================================================================
# PASO 8: EJECUCIÓN DE SCRIPTS DE APROVISIONAMIENTO DENTRO DE CHROOT
# ==============================================================================
log_step "Paso 8: Ejecutando scripts de configuración dentro del chroot"

# Copiar scripts al chroot en ubicación protegida (fuera de /tmp para evitar borrado accidental)
BUILD_SCRIPTS_STAGE="${CHROOT_DIR}/opt/defokos-build-scripts"
mkdir -p "${BUILD_SCRIPTS_STAGE}"
cp -r "${SCRIPTS_DIR}/"* "${BUILD_SCRIPTS_STAGE}/"
chmod +x "${BUILD_SCRIPTS_STAGE}/"*.sh

# Copiar paquetes deb locales al chroot si existen (YouTube Music, Discord, Steam)
BUILD_PACKAGES_STAGE="${CHROOT_DIR}/opt/defokos-packages"
mkdir -p "${BUILD_PACKAGES_STAGE}"
if [[ -d "${PROJECT_ROOT}/debs" ]]; then
    log_info "Copiando paquetes .deb locales (YouTube Music, Discord, Steam) al chroot..."
    cp -f "${PROJECT_ROOT}/debs/"*.deb "${BUILD_PACKAGES_STAGE}/" 2>/dev/null || true
fi

# 1. Aprovisionamiento de paquetes y repositorios
log_info "Ejecutando chroot-setup.sh..."
chroot "${CHROOT_DIR}" /bin/bash /opt/defokos-build-scripts/chroot-setup.sh

# 2. Inyección de tema visual, COSMIC y dotfiles
log_info "Ejecutando apply-theme.sh..."
chroot "${CHROOT_DIR}" /bin/bash /opt/defokos-build-scripts/apply-theme.sh

# Limpiar directorios de scripts y paquetes temporales
rm -rf "${BUILD_SCRIPTS_STAGE}" "${BUILD_PACKAGES_STAGE}"
log_success "Scripts ejecutados satisfactoriamente."

# ==============================================================================
# PASO 9: LIMPIEZA DEL ENTORNO CHROOT Y DESMONTAJE
# ==============================================================================
log_step "Paso 9: Desmontando y limpiando entorno chroot"

# Retirar policy-rc.d
rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d"

# Restaurar resolv.conf estándar para systemd-resolved
rm -f "${CHROOT_DIR}/etc/resolv.conf"
ln -sf /run/systemd/resolve/stub-resolv.conf "${CHROOT_DIR}/etc/resolv.conf" 2>/dev/null || true

# Desmontar puntos de montaje en orden inverso
umount -lf "${CHROOT_DIR}/run" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true
umount -lf "${CHROOT_DIR}" 2>/dev/null || true

log_success "Chroot desmontado y limpio."

# ==============================================================================
# PASO 10: ACTUALIZACIÓN DE MANIFEST Y RECONSTRUCCIÓN DE SQUASHFS
# ==============================================================================
log_step "Paso 10: Actualizando metadatos y recomprimiendo filesystem.squashfs"

CASPER_DIR="$(dirname "${SQUASHFS_IMAGE}")"

# Limpieza preventiva para asegurar que SquashFS quepa cómodamente en la partición /recovery (límite 4GB FAT32)
log_info "Verificando higiene de espacio para partición /recovery..."
rm -rf "${CHROOT_DIR}/var/lib/flatpak/runtime/"* 2>/dev/null || true
rm -rf "${CHROOT_DIR}/var/cache/apt/archives/"*.deb 2>/dev/null || true
rm -rf "${CHROOT_DIR}/var/lib/apt/lists/"* 2>/dev/null || true
rm -rf "${CHROOT_DIR}/root/.cache/"* 2>/dev/null || true

# Sincronizar kernel e initrd para el arranque de la ISO live
LATEST_KERNEL=$(ls -t "${CHROOT_DIR}/boot/vmlinuz"* 2>/dev/null | head -n1 || true)
LATEST_INITRD=$(ls -t "${CHROOT_DIR}/boot/initrd.img"* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_KERNEL}" ]] && [[ -f "${LATEST_KERNEL}" ]]; then
    log_info "Sincronizando kernel con la imagen live: $(basename "${LATEST_KERNEL}")..."
    cp -f "${LATEST_KERNEL}" "${CASPER_DIR}/vmlinuz.efi"
fi
if [[ -n "${LATEST_INITRD}" ]] && [[ -f "${LATEST_INITRD}" ]]; then
    log_info "Sincronizando initrd con la imagen live: $(basename "${LATEST_INITRD}")..."
    cp -f "${LATEST_INITRD}" "${CASPER_DIR}/initrd.gz"
fi

# Actualizar tamaño real del sistema de archivos
log_info "Calculando filesystem.size..."
printf $(du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1) > "${CASPER_DIR}/filesystem.size"

# Regenerar manifest de paquetes instalados
log_info "Generando nuevo filesystem.manifest..."
chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package} ${Version}\n' > "${CASPER_DIR}/filesystem.manifest"
cp "${CASPER_DIR}/filesystem.manifest" "${CASPER_DIR}/filesystem.manifest-desktop" || true

# Eliminar imagen squashfs anterior
rm -f "${SQUASHFS_IMAGE}"

# Recomprimir con mksquashfs
log_info "Comprimiendo nuevo SquashFS con ${COMPRESSION} (esto puede tomar varios minutos)..."
MKSQUASHFS_OPTS=(-noappend -b 1048576 -no-recovery -always-use-fragments)

if [[ "${COMPRESSION}" == "zstd" ]]; then
    MKSQUASHFS_OPTS+=(-comp zstd -Xcompression-level 19)
elif [[ "${COMPRESSION}" == "xz" ]]; then
    MKSQUASHFS_OPTS+=(-comp xz)
else
    MKSQUASHFS_OPTS+=(-comp gzip)
fi

mksquashfs "${CHROOT_DIR}" "${SQUASHFS_IMAGE}" "${MKSQUASHFS_OPTS[@]}"
log_success "Nuevo filesystem.squashfs generado exitosamente."

# Actualizar checksums md5sum.txt de la ISO
log_info "Regenerando md5sum.txt para el instalador live..."
(
    cd "${ISO_EXTRACT_DIR}"
    rm -f md5sum.txt
    find . -type f ! -path "./md5sum.txt" ! -path "./boot.catalog" -exec md5sum {} + > md5sum.txt
)
log_success "md5sum.txt actualizado."
fi

# ==============================================================================
# PASO 11: RECONSTRUCCIÓN DE LA ISO HÍBRIDA BOOTEABLE CON XORRISO
# ==============================================================================
log_step "Paso 11: Creando ISO híbrida booteable (UEFI + BIOS) con xorriso"

FINAL_ISO_PATH="${OUT_DIR}/${ISO_OUTPUT_NAME}"
rm -f "${FINAL_ISO_PATH}"

# Verificar si se dispone del reporte el_torito de la base o construir parámetros híbridos
MBR_TEMPLATE=""
if [[ -f "${ISO_EXTRACT_DIR}/isolinux/boot.cat" ]]; then
    log_info "Detectado cargador ISOLINUX tradicional."
fi

# Detectar imagen EFI
EFI_IMG=""
for candidate in \
    "boot/grub/efi.img" \
    "EFI/boot/efi.img" \
    "EFI/boot/bootx64.efi"; do
    if [[ -f "${ISO_EXTRACT_DIR}/${candidate}" ]]; then
        EFI_IMG="${candidate}"
        break
    fi
done

# Argumentos base para xorriso en modo mkisofs
XORRISO_ARGS=(
    -as mkisofs
    -r
    -V "${VOLUME_LABEL}"
    -o "${FINAL_ISO_PATH}"
    -J -l
    -b isolinux/isolinux.bin
    -c isolinux/boot.cat
    -no-emul-boot
    -boot-load-size 4
    -boot-info-table
)

# Soporte EFI si existe imagen efi.img
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

# Inyección de código de arranque MBR híbrido si se dispone de la base o binario de sistema
if [[ -f "${BASE_ISO_FILE}" ]]; then
    log_info "Inyectando código de arranque MBR híbrido desde la ISO base..."
    XORRISO_ARGS+=(
        -isohybrid-mbr "--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:${BASE_ISO_FILE}"
        --mbr-force-bootable
        -partition_cyl_align off
    )
elif [[ -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]]; then
    log_info "Inyectando código de arranque MBR híbrido estándar (/usr/lib/ISOLINUX/isohdpfx.bin)..."
    XORRISO_ARGS+=(
        -isohybrid-mbr "/usr/lib/ISOLINUX/isohdpfx.bin"
        --mbr-force-bootable
        -partition_cyl_align off
    )
fi

log_info "Empaquetando imagen ISO híbrida booteable con xorriso..."
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
