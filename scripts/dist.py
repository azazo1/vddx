#!/usr/bin/env python3
"""生成当前平台的 macOS 安装版产物 (dmg).

版本号来源:
- 设置了 PROJECT_BUILD_VERSION 时直接使用 (CI 注入)
- 否则调用 scripts/build-version.py; 仓库还没有版本 tag 时用 PACKAGE_VERSION 兜底
- VDDX_FAKE=1 时强制 v0.0.0, 产物名追加 -fake, 用于验证更新流程
"""

import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "VDDX"
PROJECT = "vddx"
PACKAGE_VERSION = "0.1.0"
ARCH = platform.machine()


def run(cmd, **kwargs):
    subprocess.run(cmd, check=True, **kwargs)


def build_version(with_prefix: bool) -> str:
    command = [sys.executable, str(ROOT / "scripts" / "build-version.py")]
    if with_prefix:
        command.append("--with-prefix")
    env = dict(os.environ)
    env.setdefault("PROJECT_PACKAGE_VERSION", PACKAGE_VERSION)
    output = subprocess.check_output(command, cwd=ROOT, text=True, env=env)
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        sys.exit("build-version.py 没有输出版本号")
    return lines[-1]


def resolve_versions(fake: bool):
    if fake:
        return "v0.0.0", "0.0.0", "fake"
    injected = os.environ.get("PROJECT_BUILD_VERSION", "").strip()
    if injected:
        display = injected if injected.startswith("v") else f"v{injected}"
    else:
        display = build_version(with_prefix=True)
    artifact = display[1:] if display.startswith("v") else display
    return display, artifact, "release"


def verify_app(app: Path) -> None:
    required = [
        app / "Contents" / "MacOS" / "VDDX",
        app / "Contents" / "Info.plist",
        app / "Contents" / "Resources" / "AppIcon.icns",
    ]
    for path in required:
        if not path.exists():
            sys.exit(f"应用包缺少文件: {path}")
    magic = required[0].read_bytes()[:4]
    if magic not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        sys.exit(f"主程序不是 Mach-O 文件: {magic!r}")


def verify_dmg(dmg: Path) -> None:
    mount = tempfile.mkdtemp(prefix="vddx-verify-")
    try:
        run(["hdiutil", "attach", str(dmg), "-nobrowse", "-quiet", "-mountpoint", mount])
        names = set(os.listdir(mount))
        if "VDDX.app" not in names:
            sys.exit("dmg 中缺少 VDDX.app")
        if "Applications" not in names:
            sys.exit("dmg 中缺少 /Applications 符号链接")
    finally:
        subprocess.run(["hdiutil", "detach", mount, "-quiet"], check=False)


def main() -> None:
    fake = os.environ.get("VDDX_FAKE") == "1"
    display_version, artifact_version, channel = resolve_versions(fake)

    dist_dir = ROOT / "dist"
    dist_dir.mkdir(exist_ok=True)
    app_path = dist_dir / f"{APP_NAME}.app"

    run([
        sys.executable,
        str(ROOT / "scripts" / "package.py"),
        "--configuration", "release",
        "--output", str(app_path),
        "--version-display", display_version,
        "--version-short", artifact_version,
        "--channel", channel,
        "--form", "installer",
    ])
    verify_app(app_path)

    suffix = "-fake" if fake else ""
    dmg_name = f"{PROJECT}-{artifact_version}-macos-{ARCH}{suffix}.dmg"
    dmg_path = dist_dir / dmg_name
    if dmg_path.exists():
        dmg_path.unlink()

    with tempfile.TemporaryDirectory(prefix="vddx-dmg-") as temporary:
        staging = Path(temporary)
        shutil.copytree(app_path, staging / f"{APP_NAME}.app", symlinks=True)
        (staging / "Applications").symlink_to("/Applications")
        run([
            "hdiutil", "create",
            "-volname", APP_NAME,
            "-srcfolder", str(staging),
            "-ov", "-format", "UDZO",
            str(dmg_path),
        ])

    verify_dmg(dmg_path)
    print(f"版本: {display_version} ({channel})")
    print(f"产物: {dmg_path}")


if __name__ == "__main__":
    main()
