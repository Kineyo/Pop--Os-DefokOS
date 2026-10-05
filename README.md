# DefokOS // Utane Uta Edition

> **Distribución Linux personalizada basada en Pop!_OS 24.04 LTS (COSMIC Desktop)** con temática inspirada en **Defoko / Utane Uta** (Utaloid Project 01). Diseñada para fans del personaje.

---
 
## 🎨 Identidad Visual y Estética

- **Color Primario (Acento):** `#b49fcc` (Lavanda Defoko)
- **Color de Fondo / Base:** `#24272e` (Carbón Industrial Oscuro)
- **Acentos Secundarios:** `#6f737e` (Gris Pizarra), `#88c0d0` (Cian de Señal Synth), `#ded8e6` (Seda Clara)
- **Entorno de Escritorio:** **COSMIC Desktop** (Pop!_OS) en modo oscuro nativo.
- **Tipografía Predeterminada:** Pixelify Sans (alias de sans-serif / system-ui vía fontconfig).

---

## 🚀 Características Principales

1. **Gestión Universal de Paquetes:**
   - **APT (.deb):** Repositorios Universe, Multiverse y Restricted activados.
   - **Flatpak:** Repositorio Flathub habilitado a nivel global del sistema.
   - **AppImage:** Soporte directo con bibliotecas de compatibilidad FUSE (`libfuse2` / `libfuse2t64` y `fuse3`), permitiendo doble clic o ejecución directa sin errores de runtime.
   - **Binarios ELF 32/64-bit:** Arquitectura `i386` habilitada para Steam y emulación Wine.
2. **Herramientas para Creadores & Devs:**
   - Terminal predeterminada **Kitty** con tema lavanda/carbón y soporte GPU.
   - **VSCodium** integrado desde su repositorio oficial sin telemetría de Microsoft.
   - **Steam** preconfigurado para gaming y proton.
   - Suite de audio con **PipeWire**, **Audacity**, **pavucontrol**, **sox** y librerías DSP.
   - **Fastfetch** personalizado con arte ASCII de Utane Uta y métricas de audio.

---

## 📂 Estructura del Repositorio

```text
DefokOS/
├── build.sh                       # Script principal de compilación (requiere sudo)
├── scripts/
│   ├── chroot-setup.sh            # Aprovisionamiento de paquetes y repositorios en chroot
│   └── apply-theme.sh             # Compilación de schemas, wallpapers y branding
├── overlay/                       # Capa de archivos inyectada directamente al rootfs
│   ├── etc/
│   │   ├── os-release             # Metadatos del sistema operativo (DefokOS)
│   │   ├── lsb-release            # Información de distribución para scripts de sistema
│   │   ├── issue / issue.net      # Banners de terminal TTY
│   │   └── skel/                  # Plantilla para usuarios nuevos (dotfiles)
│   │       ├── .bashrc            # Prompt temático con acentos lavanda
│   │       ├── .bash_aliases      # Comandos rápidos y mantenimiento
│   │       └── .config/
│   │           ├── kitty/         # kitty.conf con paleta Utane Uta
│   │           ├── fastfetch/     # Perfil con ASCII art de Defoko
│   │           └── cosmic/        # Configuraciones de acentos y wallpapers para COSMIC
│   └── usr/share/
│       ├── backgrounds/defokos/   # Wallpapers 4K en formato SVG
│       ├── glib-2.0/schemas/      # Overrides de dconf/gsettings (tema oscuro, fondo)
│       └── sounds/defokos/        # Esquema de sonidos del sistema
└── .github/workflows/
    └── build-iso.yml              # Pipeline de CI en GitHub Actions con limpieza de VM
```

---

## 🛠️ Requisitos de Compilación Local

Para generar la ISO en un sistema Linux local (Debian, Ubuntu, Pop!_OS, etc.):

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    debootstrap \
    xorriso \
    squashfs-tools \
    curl \
    rsync \
    dosfstools \
    mtools \
    isolinux \
    syslinux-utils \
    zstd \
    coreutils
```

> [!IMPORTANTE]
> Se recomienda disponer de al menos **30 GB de espacio libre en disco** y **8 GB de memoria RAM** para el desempaquetado y compresión de SquashFS.

---

## 🔨 Instrucciones de Construcción

### Compilación completa (desde cero con debootstrap)

```bash
chmod +x build.sh
sudo ./build.sh
```

`build.sh` **ya no usa una ISO base** de Pop!_OS: construye el sistema raíz con `debootstrap` (Ubuntu noble), configura los repositorios oficiales de Pop!_OS/System76, instala COSMIC desde los repositorios oficiales de [System76](https://github.com/pop-os) en github dentro de un chroot aislado y empaqueta la ISO híbrida (UEFI + BIOS) en `./out/`. Las dependencias del host se instalan automáticamente.

### Reconstrucciones rápidas

```bash
sudo ./build.sh --repack      # Reaplica overlay y aprovisionamiento sobre el chroot existente y recompone la ISO
sudo ./build.sh --pack-only   # Solo recompone la ISO a partir del chroot existente
```

### Variables de Entorno

```bash
# Cambiar algoritmo de compresión (zstd por defecto, o xz / gzip):
sudo COMPRESSION="xz" ./build.sh
```

Al terminar, encontrarás la imagen booteable y su hash criptográfico en la carpeta `out/`:
- `out/DefokOS-24.04-amd64-YYYYMMDD.iso`
- `out/DefokOS-24.04-amd64-YYYYMMDD.iso.sha256`

---

## ⚙️​ Requerimientos de instalacion.

Al estar basado en **Pop!_OS 24.04 LTS**, sus requerimientos son los mismos que los de la iso original que son

- **Ram Recomendada:** 4 GB RAM, 

- **Almacenamiento Recomendado:** 16 GB storage, 

- **Procesador:** Compatible de 64-bit

- **Clases:** Computadoras con Intel o graficos AMD o Nvidia de la serie 10 o mas antigua (ej. GTX 1060 and previous).

- **Deshabilitar Secure Boot para hacer la instalacion**

**Sitio Oficial de System76 para descargar la iso _Pop! OS_ oficial:** [https://system76.com/download-pop/](https://system76.com/download-pop/)

## 🌐 Compilación Automatizada en GitHub Actions

El repositorio incluye el flujo de trabajo [build-iso.yml](.github/workflows/build-iso.yml) optimizado para GitHub Actions:

1. **Liberación proactiva de espacio:** Desinstala SDKs pesados de la VM de runner (Android, .NET, Haskell, Docker) para garantizar más de 45 GB de disco disponible.
2. **Ejecución de build.sh:** Descarga la base oficial, aplica los dotfiles y reempaqueta la ISO con soporte UEFI y BIOS.
3. **Generación de Release:** Puedes disparar la compilación manualmente desde la pestaña **Actions** con la opción de publicar automáticamente en **Releases**, o simplemente empujando un tag Git (`git tag v1.0.0 && git push origin v1.0.0`).

---

## 🎨 Personalización Adicional

- **Añadir o remover paquetes:** Edita el array `APT_PACKAGES` en [scripts/chroot-setup.sh](scripts/chroot-setup.sh).
- **Modificar dotfiles:** Cualquier archivo que coloques dentro de [overlay/etc/skel/](overlay/etc/skel/) se copiará automáticamente al directorio de inicio de cada nuevo usuario creado en el sistema.
- **Cambiar el fondo de pantalla:** Reemplaza o añade archivos en [overlay/usr/share/backgrounds/defokos/](overlay/usr/share/backgrounds/defokos/).
- **Añadir sonidos del sistema:** Coloca archivos `.ogg` en [overlay/usr/share/sounds/defokos/stereo/](overlay/usr/share/sounds/defokos/stereo/).

---

## 📄 Licencia

Este proyecto y sus scripts de automatización se distribuyen bajo la licencia MIT. Pop!_OS y COSMIC son marcas y creaciones de [System76](https://github.com/pop-os). Utane Uta / Defoko es un personaje de dominio público originario de la comunidad UTAU (Ameya/Ayame).
Este es un proyecto tributo hacia **Defoko / Uta Utane** y usa los repositorios publicos de [System76](https://github.com/pop-os) para el entorno cosmic, el gestor de archivos y la interfaz grafica, las imagenes no son mias sino descargadas de internet/Pinterest; Creditos a sus respectivos autores.