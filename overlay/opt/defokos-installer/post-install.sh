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

# Habilitar soporte multilib por compatibilidad (Steam)
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
