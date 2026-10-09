"""Package the native WeChat module with public configuration only."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "miniprogram"


def https_origin(value):
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.path not in ("", "/")
            or parsed.query or parsed.fragment or parsed.port not in (None, 443)):
        raise ValueError("Backend must be an HTTPS origin without credentials or a path")
    return value.rstrip("/")


def public_key(value):
    if value.startswith("sb_publishable_") and "YOUR" not in value:
        return value
    raise ValueError("A Supabase Publishable Key is required; Secret Key and service_role are forbidden")


def build(args):
    source_config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    origin = https_origin(source_config["SUPABASE_URL"])
    key = public_key(source_config["SUPABASE_PUBLISHABLE_KEY"])
    api_origin = https_origin(args.api_origin) if args.api_origin else origin
    source_project = json.loads((SOURCE / "project.config.json").read_text(encoding="utf-8"))
    appid = args.appid or source_project.get("appid", "touristappid")
    appid_configured = bool(re.fullmatch(r"wx[0-9a-fA-F]{16}", appid))
    if not args.appid and not appid_configured:
        appid = "touristappid"
    if args.appid and not re.fullmatch(r"wx[0-9a-fA-F]{16}", appid):
        raise ValueError("AppID must have the form wx followed by 16 hexadecimal characters")
    files = []
    for directory in ("lib", "pages"):
        for path in sorted((SOURCE / directory).rglob("*")):
            if path.is_symlink():
                raise ValueError("Package sources must not be symlinks")
            if path.is_file() and path.suffix in (".js", ".json", ".wxml", ".wxss"):
                files.append(path)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SOURCE / "app.json").read_text(encoding="utf-8"))
    for kind in ("standalone", "subpackage"):
        filename = output / ("dearshelf-" + kind + ".zip")
        prefix = "dearshelf/" if kind == "subpackage" else ""
        with ZipFile(filename, "w", ZIP_DEFLATED) as archive:
            for path in files + [SOURCE / "app.wxss"]:
                archive.writestr(prefix + path.relative_to(SOURCE).as_posix(), path.read_bytes())
            config = dict(supabaseUrl=api_origin, publishableKey=key,
                          storageOrigin=origin if api_origin != origin else "",
                          allowRegistration=False,
                          routePrefix="/dearshelf" if prefix else "")
            archive.writestr(prefix + "config.js", "// Public frontend configuration only.\nmodule.exports = "
                             + json.dumps(config, ensure_ascii=False, indent=2) + ";\n")
            if kind == "standalone":
                archive.writestr("app.js", (SOURCE / "app.js").read_bytes())
                archive.writestr("app.json", json.dumps(manifest, ensure_ascii=False, indent=2))
                project = dict(source_project)
                project["appid"] = appid
                archive.writestr("project.config.json", json.dumps(project, ensure_ascii=False, indent=2))
        print(filename)
    subpackage = dict(root="dearshelf", name="dearshelf", pages=manifest["pages"])
    (output / "subpackage-entry.json").write_text(
        json.dumps(subpackage, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    readiness = dict(appidConfigured=appid_configured, backendOrigin=api_origin,
                     registrationEnabled=False, pages=len(manifest["pages"]),
                     remaining=["Merge into existing mini program", "Apply access-control migration and administrator allowlist",
                                "Verify legal domains and platform requirements", "Compile and test in WeChat Developer Tools"])
    if not appid_configured:
        readiness["remaining"].insert(0, "Provide Geek Mia AppID")
    (output / "readiness.json").write_text(
        json.dumps(readiness, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Public configuration packaged; source project and existing app were not modified.")
    if not appid_configured:
        print("AppID is pending: standalone package uses touristappid and cannot be uploaded.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="Flutter public config JSON")
    parser.add_argument("--appid", help="Geek Mia AppID; omitted for local preparation")
    parser.add_argument("--api-origin", help="Optional HTTPS relay origin")
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "wechat-package")
    args = parser.parse_args()
    try:
        build(args)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")
