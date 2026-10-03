#!/usr/bin/env bash
# ==============================================================================
# DefokOS - Script de Desmontaje de Chroot y Liberación de Permisos
# ==============================================================================
# Propósito:
#   1. Desmontar de forma segura todos los puntos de montaje del chroot
#      (/dev, /dev/pts, /proc, /sys, /run, scripts, etc.) que hayan quedado colgados.
#   2. Asignar la propiedad de todos los archivos del proyecto (scripts, overlay,
#      assets, out, debs) al usuario normal sin privilegios (SUDO_USER).
#   3. Aplicar ACLs (Access Control Lists) recursivas sobre work/squashfs_root
#      para que el usuario pueda editar y reparar cualquier archivo del sistema
#      raíz directamente desde su editor de código sin requerir 'sudo' y sin
#      romper la propiedad 'root:root' necesaria para el empaquetado de la ISO.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()     { echo -e "${RED}[ERROR]${NC} $*"; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROJECT_DIR}/work"
CHROOT_DIR="${WORK_DIR}/squashfs_root"

# Verificar que se ejecute con privilegios de root para poder desmontar
if [[ $EUID -ne 0 ]]; then
    log_err "Este script requiere privilegios de superusuario para desmontar recursos del kernel."
    echo -e "Ejecútalo con: ${CYAN}sudo $0${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-${USER}}"
if [[ "${REAL_USER}" == "root" ]]; then
    # Si se ejecutó directamente como root, buscar el usuario con UID 1000
    REAL_USER=$(id -nu 1000 2>/dev/null || echo "root")
fi
REAL_GROUP=$(id -gn "${REAL_USER}" 2>/dev/null || echo "${REAL_USER}")

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}      DefokOS - Reparación y Liberación del Espacio de Trabajo  ${NC}"
echo -e "${CYAN}================================================================${NC}"
log_info "Directorio del proyecto : ${PROJECT_DIR}"
log_info "Usuario objetivo        : ${REAL_USER} (Grupo: ${REAL_GROUP})"
echo ""

# ==============================================================================
# FASE 1: DESMONTAJE SEGURO Y LIMPIEZA DEL CHROOT
# ==============================================================================
log_info "Fase 1: Verificando y desmontando puntos de montaje activos..."

# Buscar cualquier montura dentro del árbol de trabajo
if [[ -d "${WORK_DIR}" ]]; then
    # Leer monturas activas que comiencen con la ruta del proyecto o del chroot (orden inverso)
    ACTIVE_MOUNTS=$(grep -E " ${PROJECT_DIR}/" /proc/mounts 2>/dev/null | awk '{print $2}' | sort -r || true)

    if [[ -n "${ACTIVE_MOUNTS}" ]]; then
        for mp in ${ACTIVE_MOUNTS}; do
            log_warn "Desmontando punto activo: ${mp}"
            umount -lf "${mp}" 2>/dev/null || true
        done
        log_success "Monturas detectadas desmontadas."
    else
        log_info "No se encontraron monturas activas en /proc/mounts."
    fi
fi

# Puntos de montaje estándar por seguridad adicional
CANDIDATE_MOUNTS=(
    "${CHROOT_DIR}/opt/defokos-build-scripts"
    "${CHROOT_DIR}/tmp/scripts"
    "${CHROOT_DIR}/run"
    "${CHROOT_DIR}/sys"
    "${CHROOT_DIR}/proc"
    "${CHROOT_DIR}/dev/pts"
    "${CHROOT_DIR}/dev"
    "${CHROOT_DIR}"
)

for mp in "${CANDIDATE_MOUNTS[@]}"; do
    if mountpoint -q "$mp" 2>/dev/null; then
        log_warn "Desmontando forzosamente: ${mp}"
        umount -lf "$mp" 2>/dev/null || true
    fi
done

# Limpieza de bloqueos del chroot
if [[ -f "${CHROOT_DIR}/usr/sbin/policy-rc.d" ]]; then
    log_info "Eliminando bloqueo de servicios residual: ${CHROOT_DIR}/usr/sbin/policy-rc.d"
    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d" 2>/dev/null || true
fi

log_success "Chroot apagado y desconectado limpiamente."
echo ""

# ==============================================================================
# FASE 2: ASIGNACIÓN DE PROPIEDAD AL USUARIO NORMAL
# ==============================================================================
log_info "Fase 2: Concediendo propiedad al usuario '${REAL_USER}' sobre archivos de origen..."

# Carpetas del código fuente y recursos del proyecto
DEV_DIRS=(
    "${PROJECT_DIR}/overlay"
    "${PROJECT_DIR}/scripts"
    "${PROJECT_DIR}/assets"
    "${PROJECT_DIR}/debs"
    "${PROJECT_DIR}/out"
)

for dir in "${DEV_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        log_info "Asignando propiedad de: ${dir} -> ${REAL_USER}:${REAL_GROUP}"
        chown -R "${REAL_USER}:${REAL_GROUP}" "${dir}" 2>/dev/null || true
        chmod -R u+rwX,g+rX "${dir}" 2>/dev/null || true
    fi
done

# Archivos sueltos en el directorio raíz del repositorio (build.sh, etc.)
find "${PROJECT_DIR}" -maxdepth 1 -type f -exec chown "${REAL_USER}:${REAL_GROUP}" {} + 2>/dev/null || true

# Eliminar el archivo residual del instalador en overlay/etc/skel si aún existía
if [[ -f "${PROJECT_DIR}/overlay/etc/skel/Desktop/install-defokos.desktop" ]]; then
    rm -f "${PROJECT_DIR}/overlay/etc/skel/Desktop/install-defokos.desktop" 2>/dev/null || true
    log_info "Eliminado acceso directo residual de instalación en /etc/skel."
fi

log_success "Archivos de desarrollo liberados para edición directa."
echo ""

# ==============================================================================
# FASE 3: HABILITACIÓN DE EDICIÓN DIRECTA EN EL CHROOT MEDIANTE ACLs
# ==============================================================================
if [[ -d "${WORK_DIR}" ]]; then
    log_info "Fase 3: Habilitando permisos de edición directa en '${WORK_DIR}'..."
    log_info "(Se preservan permisos root/SUID internos para empaquetado ISO mediante POSIX ACLs)"

    if command -v setfacl >/dev/null 2>&1; then
        setfacl -R -m "u:${REAL_USER}:rwX" "${WORK_DIR}" 2>/dev/null || true
        setfacl -R -d -m "u:${REAL_USER}:rwX" "${WORK_DIR}" 2>/dev/null || true
        log_success "ACLs aplicadas exitosamente sobre ${WORK_DIR}."
        log_info "Ahora puedes abrir, editar y guardar cualquier archivo en 'work/squashfs_root/'"
        log_info "directamente desde VS Code o tu editor sin necesidad de sudo."
    else
        log_warn "setfacl no encontrado. Aplicando chmod permisivo en directorios de trabajo."
        chmod -R a+rwX "${WORK_DIR}" 2>/dev/null || true
    fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}   ¡Listo! El espacio de trabajo ha sido liberado exitosamente.  ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Puedes modificar scripts, overlays y el sistema raíz sin 'Permission Denied'."
echo -e "Cuando desees volver a empaquetar la ISO, simplemente ejecuta:"
echo -e "   ${CYAN}sudo ./build.sh --repack${NC}"
