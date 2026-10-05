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
