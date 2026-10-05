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

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    for theme in hicolor Pop pop-os-branding; do
        if [ -d "/usr/share/icons/${theme}" ]; then
            gtk-update-icon-cache -f -t "/usr/share/icons/${theme}" 2>/dev/null || true
        fi
    done
fi

echo "[THEME] Tema y fuentes aplicados correctamente."
