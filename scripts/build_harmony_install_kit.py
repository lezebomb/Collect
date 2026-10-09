"""Package only our remote-install scripts and public guides, never Huawei SDKs."""
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "harmony/output"
FILES = [
    "harmony/hdc-tools.ps1",
    "harmony/install.ps1",
    "harmony/get-device-info.ps1",
    "harmony/set-tools.ps1",
    "harmony/获取手机信息.cmd",
    "harmony/设置工具路径.cmd",
    "harmony/安装收到的HAP.cmd",
    "harmony/快速安装.cmd",
    "harmony/TOOLCHAIN.md",
    "docs/harmonyos-install.md",
    "docs/harmonyos-recipient-guide.md",
    "docs/harmonyos-developer-guide.md",
    "docs/harmonyos-verification.md",
    "SECURITY.md",
    "supabase/admin/email-members.example.sql",
]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    archive_path = OUTPUT / "Dearshelf-Harmony-Install-Kit.zip"
    with ZipFile(archive_path, "w", ZIP_DEFLATED) as archive:
        for relative in FILES:
            source = ROOT / relative
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Missing or unsafe package source: {relative}")
            content = source.read_bytes()
            if source.suffix == ".ps1" and not content.startswith(b"\xef\xbb\xbf"):
                raise ValueError(f"Windows PowerShell requires UTF-8 BOM: {relative}")
            if source.suffix == ".cmd":
                text = content.decode("utf-8-sig").replace("\r\n", "\n")
                content = text.replace("\n", "\r\n").encode("utf-8")
            archive.writestr(relative, content)
        archive.writestr("README.txt", """Dearshelf 鸿蒙安装工具

完整教程：docs/harmonyos-recipient-guide.md
在线教程：https://github.com/lezebomb/Collect/blob/main/docs/harmonyos-recipient-guide.md

1. 完整解压本 ZIP。
2. 安装华为官方 DevEco Studio 及 SDK，手机开启开发者模式/USB 调试。
3. 双击 harmony/获取手机信息.cmd，将生成的 device-info.txt 私下交给开发者。
4. 收到针对该手机签名的 HAP 后，将其拖到 harmony/安装收到的HAP.cmd。

本工具不包含华为 SDK、开发者凭据、成员名单或已签名 HAP。
公开的 unsigned.hap 不能安装到华为真机。
仅需安装现成 HAP 的手机持有人不需要 Flutter/Git/Node.js。
开发者进行源码构建时应下载完整 GitHub 源码，按开发者教程操作。
""".encode("utf-8-sig"))
        archive.writestr("harmony/output/README.txt",
                         "把开发者发来的 signed.hap 放在这里，然后双击上一级的快速安装.cmd。\r\n"
                         .encode("utf-8-sig"))
    assets = [archive_path]
    assets.extend(sorted(OUTPUT.glob("*.hap")))
    checksums = []
    for asset in assets:
        digest = hashlib.sha256(asset.read_bytes()).hexdigest().upper()
        line = f"{digest}  {asset.name}\n"
        Path(str(asset) + ".sha256.txt").write_text(line, encoding="utf-8")
        checksums.append(line)
    (OUTPUT / "SHA256SUMS.txt").write_text("".join(checksums), encoding="utf-8")
    with ZipFile(archive_path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Install kit checksum failed")
        assert len(archive.namelist()) == len(FILES) + 2
    print(f"Packaged {len(FILES)} public files: {archive_path}")
    print("No SDK redistribution, runtime configuration, device report or signing material included.")


if __name__ == "__main__":
    main()
