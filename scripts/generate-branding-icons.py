#!/usr/bin/env python3
import os
import sys
import subprocess
import base64

def generate_icons(source_path, overlay_dir):
    if not os.path.exists(source_path):
        print(f"Icon source not found: {source_path}")
        return False

    sizes = [16, 22, 24, 32, 48, 64, 128, 256, 512]
    cache = {}

    print(f"Generating icons from {source_path}...")
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

    # 1. Pop Icon Theme places
    for s in sizes:
        dim = f"{s}x{s}"
        places_dir = os.path.join(overlay_dir, "usr/share/icons/Pop", dim, "places")
        os.makedirs(places_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.svg", "distributor-logo.svg", "start-here-pop-os.svg", "pop-os-logo-icon.svg", "pop-os.svg"]:
            with open(os.path.join(places_dir, name), "w") as f:
                f.write(cache[s][1])

    # 2. Hicolor Icon Theme apps
    for s in sizes:
        dim = f"{s}x{s}"
        apps_dir = os.path.join(overlay_dir, "usr/share/icons/hicolor", dim, "apps")
        os.makedirs(apps_dir, exist_ok=True)
        for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
            with open(os.path.join(apps_dir, name), "wb") as f:
                f.write(cache[s][0])

    # 3. pop-os-branding
    branding_dir = os.path.join(overlay_dir, "usr/share/icons/pop-os-branding")
    os.makedirs(branding_dir, exist_ok=True)
    with open(os.path.join(branding_dir, "pop_icon.svg"), "w") as f:
        f.write(cache[512][1])

    for s in [16, 22, 24, 32, 48, 64]:
        round_dir = os.path.join(branding_dir, f"round-logos/{s}")
        os.makedirs(round_dir, exist_ok=True)
        with open(os.path.join(round_dir, "distributor-logo.svg"), "w") as f:
            f.write(cache[s][1])
        if s == 16:
            with open(os.path.join(round_dir, "ubuntu-logo-icon.svg"), "w") as f:
                f.write(cache[16][1])

    apps_256 = os.path.join(branding_dir, "256x256/apps")
    os.makedirs(apps_256, exist_ok=True)
    with open(os.path.join(apps_256, "ubuntu-logo-icon.png"), "wb") as f:
        f.write(cache[256][0])

    # 4. Pixmaps
    pixmaps_dir = os.path.join(overlay_dir, "usr/share/pixmaps")
    os.makedirs(pixmaps_dir, exist_ok=True)
    for name in ["distributor-logo-pop-os.png", "distributor-logo.png", "pop-os.png"]:
        with open(os.path.join(pixmaps_dir, name), "wb") as f:
            f.write(cache[256][0])
    subprocess.run(["cp", "-f", source_path, os.path.join(pixmaps_dir, "Pop!_OS_Icon.png")], check=True)

    # 5. Plymouth theme logos
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

    watermark_path = os.path.join(spinner, "watermark.png")
    subprocess.run(["convert", source_path, "-background", "none", "-resize", "x87", watermark_path], check=True)

    # 6. GRUB Theme logo
    grub_theme_dir = os.path.join(overlay_dir, "boot/grub/themes/pop")
    os.makedirs(grub_theme_dir, exist_ok=True)
    with open(os.path.join(grub_theme_dir, "logo.png"), "wb") as f:
        f.write(cache[128][0])

    # 7. Calamares branding logo
    calamares_dir = os.path.join(overlay_dir, "etc/calamares/branding/defokos")
    os.makedirs(calamares_dir, exist_ok=True)
    with open(os.path.join(calamares_dir, "logo.png"), "wb") as f:
        f.write(cache[128][0])

    print("Icons successfully generated and deployed to overlay.")
    return True

if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "/home/alex/Documentos/DefokOS/assets/Pop!_OS_Icon.png"
    target = sys.argv[2] if len(sys.argv) > 2 else "/home/alex/Documentos/DefokOS/overlay"
    generate_icons(src, target)
