#!/usr/bin/env python3
"""组装 macOS 应用包 (.app).

由 just dist / CI 调用, 不直接给终端用户使用.
"""

import argparse
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "VDDX"
EXECUTABLE = "VDDX"
BUNDLE_ID = "com.azazo1.vddx"

ICON_SOURCE = ROOT / "assets" / "AppIcon.icns"


def build_binary(configuration: str) -> Path:
    subprocess.run(
        ["swift", "build", "--disable-sandbox", "-c", configuration],
        cwd=ROOT,
        check=True,
    )
    bin_dir = subprocess.check_output(
        ["swift", "build", "--disable-sandbox", "-c", configuration, "--show-bin-path"],
        cwd=ROOT,
        text=True,
    ).strip()
    binary = Path(bin_dir) / EXECUTABLE
    if not binary.exists():
        sys.exit(f"未找到构建产物: {binary}")
    return binary


def write_info_plist(app: Path, args: argparse.Namespace) -> None:
    info = {
        "CFBundleName": APP_NAME,
        "CFBundleDisplayName": APP_NAME,
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": EXECUTABLE,
        "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": args.version_short,
        "CFBundleVersion": args.version_short,
        "CFBundleIconFile": "AppIcon",
        "LSMinimumSystemVersion": "15.0",
        "LSApplicationCategoryType": "public.app-category.utilities",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "Copyright © 2026 azazo1",
        "VDDXVersionDisplay": args.version_display,
        "VDDXChannel": args.channel,
        "VDDXDistributionForm": args.form,
    }
    with (app / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)


def build_app(binary: Path, output: Path, args: argparse.Namespace) -> None:
    if output.exists():
        shutil.rmtree(output)
    macos_dir = output / "Contents" / "MacOS"
    resources_dir = output / "Contents" / "Resources"
    macos_dir.mkdir(parents=True)
    resources_dir.mkdir(parents=True)

    shutil.copy2(binary, macos_dir / EXECUTABLE)
    (macos_dir / EXECUTABLE).chmod(0o755)
    write_info_plist(output, args)
    (output / "Contents" / "PkgInfo").write_text("APPL????", encoding="ascii")

    if ICON_SOURCE.exists():
        shutil.copy2(ICON_SOURCE, resources_dir / "AppIcon.icns")
    else:
        print(f"警告: 缺少图标 {ICON_SOURCE}", file=sys.stderr)

    if not args.no_sign:
        subprocess.run(
            ["codesign", "--force", "--sign", "-", "--timestamp=none", str(output)],
            check=True,
        )
        subprocess.run(
            ["codesign", "--verify", "--strict", str(output)],
            check=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="组装 macOS 应用包")
    parser.add_argument("--configuration", choices=["debug", "release"], default="release")
    parser.add_argument("--output", required=True)
    parser.add_argument("--version-display", default="dev-build")
    parser.add_argument("--version-short", default="0.0.0")
    parser.add_argument("--channel", default="release")
    parser.add_argument("--form", default="installer")
    parser.add_argument("--no-sign", action="store_true")
    args = parser.parse_args()

    binary = build_binary(args.configuration)
    output = Path(args.output).resolve()
    build_app(binary, output, args)
    print(output)


if __name__ == "__main__":
    main()
