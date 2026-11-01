#!/usr/bin/env python3
"""生成应用图标 AppIcon.icns.

这是开发期一次性脚本, 依赖 Pillow 与 numpy, 不参与常规打包流程.
图标源图保持满幅方图, 由本脚本按 macOS 习惯在打包前缩进约 86% 并居中.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "AppIcon.iconset"

SCALE = 4
BASE = 1024
CANVAS = BASE * SCALE
CONTENT_RATIO = 0.86
GRADIENT_TOP = (37, 99, 235)
GRADIENT_BOTTOM = (109, 40, 217)

ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def s(value: float) -> int:
    return int(round(value * SCALE))


def gradient_image(size: int) -> Image.Image:
    rows = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    array = np.empty((size, size, 4), dtype=np.uint8)
    for channel in range(3):
        start = GRADIENT_TOP[channel]
        end = GRADIENT_BOTTOM[channel]
        column = (start + (end - start) * rows).astype(np.uint8)
        array[:, :, channel] = np.repeat(column, size, axis=1)
    array[:, :, 3] = 255
    return Image.fromarray(array, "RGBA")


def build_content() -> Image.Image:
    image = gradient_image(CANVAS)
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, CANVAS - 1, CANVAS - 1],
        radius=int(CANVAS * 0.2239),
        fill=255,
    )
    image.putalpha(mask)

    draw = ImageDraw.Draw(image)
    white = (255, 255, 255, 255)
    muted = (255, 255, 255, 165)
    stroke = s(38)

    # 主显示器
    draw.rounded_rectangle(
        [s(132), s(268), s(620), s(596)],
        radius=s(34),
        outline=white,
        width=stroke,
    )
    draw.line([s(376), s(596), s(376), s(668)], fill=white, width=s(34))
    draw.line([s(292), s(668), s(460), s(668)], fill=white, width=s(34))

    # 副显示器
    draw.rounded_rectangle(
        [s(650), s(376), s(888), s(596)],
        radius=s(28),
        outline=muted,
        width=s(30),
    )
    draw.line([s(770), s(596), s(770), s(654)], fill=muted, width=s(26))
    draw.line([s(706), s(654), s(834), s(654)], fill=muted, width=s(26))

    return image


def main() -> None:
    content = build_content()
    side = int(CANVAS * CONTENT_RATIO)
    content = content.resize((side, side), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - side) // 2
    canvas.alpha_composite(content, (offset, offset))
    canvas = canvas.resize((BASE, BASE), Image.LANCZOS)

    ASSETS.mkdir(exist_ok=True)
    canvas.save(ASSETS / "AppIcon-1024.png")

    if ICONSET.exists():
        for child in ICONSET.iterdir():
            child.unlink()
    else:
        ICONSET.mkdir()
    for name, px in ICON_SIZES:
        canvas.resize((px, px), Image.LANCZOS).save(ICONSET / name)

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(ASSETS / "AppIcon.icns")],
        check=True,
    )
    print(ASSETS / "AppIcon.icns")


if __name__ == "__main__":
    sys.exit(main())
