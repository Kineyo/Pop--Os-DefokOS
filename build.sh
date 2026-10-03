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

# URL oficial de la ISO base (Pop!_OS Intel/AMD).
# System76 migró sus imágenes a iso.pop-os.org
DEFAULT_BASE_URL="https://iso.pop-os.org/22.04/amd64/intel/58/pop-os_22.04_amd64_intel_58.iso"
BASE_ISO_URL="${BASE_ISO_URL:-${DEFAULT_BASE_URL}}"

# Nombre de la ISO resultante
DATE_TAG="$(date +%Y%m%d)"
DEFOKOS_VERSION="24.04"
ISO_OUTPUT_NAME="DefokOS-${DEFOKOS_VERSION}-amd64-${DATE_TAG}.iso"
VOLUME_LABEL="DefokOS_${DEFOKOS_VERSION}_amd64"

# Parámetro opcional: ruta a ISO base local (para evitar descarga)
LOCAL_BASE_ISO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            LOCAL_BASE_ISO="$2"
            shift 2
            ;;
        --help|-h)
            echo "Uso: sudo $0 [--iso /ruta/a/base.iso]"
            echo ""
            echo "Variables de entorno opcionales:"
            echo "  BASE_ISO_URL    URL para descargar la ISO base si no se especifica --iso"
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

# --- Manejador de Limpieza y Salida Segura (Trap) ---
cleanup_mounts() {
    local exit_code=$?
    log_warn "Ejecutando rutina de desmontaje seguro y limpieza de recursos..."

    set +e
    # Desmontar puntos de montaje chroot en orden inverso
    for mp in \
        "${CHROOT_DIR}/tmp/scripts" \
        "${CHROOT_DIR}/run" \
        "${CHROOT_DIR}/sys" \
        "${CHROOT_DIR}/proc" \
        "${CHROOT_DIR}/dev/pts" \
        "${CHROOT_DIR}/dev" \
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

# ==============================================================================
# PASO 3: OBTENCIÓN DE LA ISO BASE
# ==============================================================================
log_step "Paso 3: Localizando o descargando la ISO base de Pop!_OS"

BASE_ISO_FILE="${WORK_DIR}/base.iso"

if [[ -n "${LOCAL_BASE_ISO}" ]] && [[ -f "${LOCAL_BASE_ISO}" ]]; then
    log_info "Usando ISO local provista por el usuario: ${LOCAL_BASE_ISO}"
    BASE_ISO_FILE="${LOCAL_BASE_ISO}"
elif [[ -f "${BASE_ISO_FILE}" ]]; then
    log_info "Se encontró una imagen base en caché: ${BASE_ISO_FILE}"
    log_info "Descargando imagen ISO base desde:"
    log_info "  ${BASE_ISO_URL}"
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
    log_success "Descarga de ISO base completada."
fi

# ==============================================================================
# PASO 4: EXTRACCIÓN DE LA ISO Y METADATOS DE ARRANQUE (EL TORITO)
# ==============================================================================
log_step "Paso 4: Extrayendo contenido de la ISO base y geometría de arranque"

# Extraer parámetros exactos de arranque con xorriso para garantizar booteo EFI y BIOS
BOOT_OPTS_FILE="${WORK_DIR}/el_torito_opts.txt"
log_info "Analizando estructura híbrida de arranque con xorriso..."
xorriso -indev "${BASE_ISO_FILE}" -report_el_torito as_mkisofs > "${BOOT_OPTS_FILE}" 2>/dev/null || true

# Montar y copiar archivos de la ISO al directorio de extracción
log_info "Montando imagen ISO base..."
mount -o loop,ro "${BASE_ISO_FILE}" "${ISO_MOUNT_DIR}"

log_info "Extrayendo árbol de archivos de la ISO (rsync)..."
rsync -a --delete --info=progress2 "${ISO_MOUNT_DIR}/" "${ISO_EXTRACT_DIR}/"

umount -lf "${ISO_MOUNT_DIR}"
log_success "Árbol de la ISO extraído correctamente."

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

# ==============================================================================
# PASO 6: PREPARACIÓN DEL ENTORNO CHROOT Y MONTURAS BIND
# ==============================================================================
log_step "Paso 6: Preparando monturas virtuales y políticas en chroot"

# Configurar resolución DNS temporal heredando la del host
if [[ -f /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
fi

# Prevenir que servicios/daemons arranquen durante la instalación de paquetes
cat << 'EOF' > "${CHROOT_DIR}/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "${CHROOT_DIR}/usr/sbin/policy-rc.d"

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
    log_info "Inyectando overlay desde ${OVERLAY_DIR} hacia ${CHROOT_DIR}..."
    rsync -av "${OVERLAY_DIR}/" "${CHROOT_DIR}/"
    log_success "Overlay inyectado exitosamente."
else
    log_warn "No se encontró el directorio overlay (${OVERLAY_DIR}). Omitiendo..."
fi

# ==============================================================================
# PASO 8: EJECUCIÓN DE SCRIPTS DE APROVISIONAMIENTO DENTRO DE CHROOT
# ==============================================================================
log_step "Paso 8: Ejecutando scripts de configuración dentro del chroot"

# Copiar scripts al chroot temporalmente
mkdir -p "${CHROOT_DIR}/tmp/scripts"
cp -r "${SCRIPTS_DIR}/"* "${CHROOT_DIR}/tmp/scripts/"
chmod +x "${CHROOT_DIR}/tmp/scripts/"*.sh

# 1. Aprovisionamiento de paquetes y repositorios
log_info "Ejecutando /tmp/scripts/chroot-setup.sh..."
chroot "${CHROOT_DIR}" /bin/bash /tmp/scripts/chroot-setup.sh

# 2. Inyección de tema visual, COSMIC y dotfiles
log_info "Ejecutando /tmp/scripts/apply-theme.sh..."
chroot "${CHROOT_DIR}" /bin/bash /tmp/scripts/apply-theme.sh

# Limpiar directorio temporal de scripts
rm -rf "${CHROOT_DIR}/tmp/scripts"
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

# Desmontar puntos de montaje
umount -lf "${CHROOT_DIR}/run" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true

log_success "Chroot desmontado y limpio."

# ==============================================================================
# PASO 10: ACTUALIZACIÓN DE MANIFEST Y RECONSTRUCCIÓN DE SQUASHFS
# ==============================================================================
log_step "Paso 10: Actualizando metadatos y recomprimiendo filesystem.squashfs"

CASPER_DIR="$(dirname "${SQUASHFS_IMAGE}")"

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
        -isohybrid-gpt-basdat
    )
fi

# Fallback si el_torito_opts.txt tiene argumentos válidos
if [[ -s "${BOOT_OPTS_FILE}" ]] && grep -q "\-b" "${BOOT_OPTS_FILE}"; then
    log_info "Utilizando parámetros originales extraídos de la ISO base..."
    # Ejecución utilizando el árbol de la ISO extraída
    (
        cd "${ISO_EXTRACT_DIR}"
        # Leer opciones del archivo descartando rutas absolutas no pertinentes
        RAW_OPTS=$(cat "${BOOT_OPTS_FILE}" | sed -e 's/xorriso -as mkisofs //' -e "s/-o '[^']*'//")
        xorriso -as mkisofs -r -V "${VOLUME_LABEL}" -o "${FINAL_ISO_PATH}" ${RAW_OPTS} .
    )
else
    log_info "Empaquetando con configuración híbrida estándar..."
    (
        cd "${ISO_EXTRACT_DIR}"
        xorriso "${XORRISO_ARGS[@]}" .
    )
fi

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
