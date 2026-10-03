#!/usr/bin/env bash
# ==============================================================================
# DefokOS - Entrar de forma interactiva y segura al Chroot
# ==============================================================================
# Propósito:
#   Prepara automáticamente las monturas (/dev, /proc, /sys, /run, DNS),
#   abre una terminal bash interactiva dentro del sistema DefokOS para que
#   puedas probar comandos o instalar paquetes manualmente, y al salir
#   (escribiendo 'exit') desmonta todo automáticamente y de forma limpia.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Se requieren privilegios de superusuario."
    echo -e "Ejecútalo con: ${CYAN}sudo $0${NC}"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT_DIR="${PROJECT_DIR}/work/squashfs_root"

if [[ ! -d "${CHROOT_DIR}" ]]; then
    echo -e "${RED}[ERROR]${NC} No se encontró el árbol chroot en: ${CHROOT_DIR}"
    exit 1
fi

cleanup() {
    echo ""
    echo -e "${CYAN}[CHROOT] Saliendo y desmontando recursos de forma segura...${NC}"
    for mp in \
        "${CHROOT_DIR}/run" \
        "${CHROOT_DIR}/sys" \
        "${CHROOT_DIR}/proc" \
        "${CHROOT_DIR}/dev/pts" \
        "${CHROOT_DIR}/dev" \
        "${CHROOT_DIR}"; do
        if mountpoint -q "$mp" 2>/dev/null; then
            umount -lf "$mp" 2>/dev/null || true
        fi
    done
    rm -f "${CHROOT_DIR}/usr/sbin/policy-rc.d" 2>/dev/null || true
    echo -e "${GREEN}[CHROOT] Desmontaje completado.${NC}"
}
trap cleanup EXIT INT TERM

echo -e "${CYAN}[CHROOT] Configurando monturas del sistema (/dev, /proc, /sys, /run)...${NC}"
mount --bind "${CHROOT_DIR}" "${CHROOT_DIR}"
mount --make-rslave "${CHROOT_DIR}"
mount --bind /dev "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sysfs "${CHROOT_DIR}/sys"
mount -t tmpfs tmpfs "${CHROOT_DIR}/run"

cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf" 2>/dev/null || true

echo -e "${GREEN}[CHROOT] Sesión interactiva iniciada.${NC}"
echo -e "Escribe ${CYAN}exit${NC} o presiona ${CYAN}Ctrl+D${NC} cuando termines para salir y desmontar todo."
echo ""

chroot "${CHROOT_DIR}" /bin/bash --login +h || true
