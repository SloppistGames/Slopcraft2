#!/usr/bin/env python3
"""Verified Godot exports, native smoke tests and immutable release preparation.

Only the publish subcommand uses GitHub write access. Build/smoke never publish.
Python 3.11+ standard library; see tools/README.md for local and CI commands.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from datetime import date
from pathlib import Path, PurePosixPath

GODOT_VERSION = "4.7.stable"
REPOSITORY = "SloppistGames/Slopcraft2"
DOWNLOAD_BASE = "https://github.com/godotengine/godot/releases/download/4.7-stable/"
DOWNLOADS = {
    "macos": ("Godot_v4.7-stable_macos.universal.zip", "a6708c336f690e0dd8abd3d587d661707f4f33ed436946a3ec000d2fb497fd6c"),
    "windows": ("Godot_v4.7-stable_win64.exe.zip", "02a5312236f4e0209c78bcb2f52135b1963e6b8888c873c9cee81459e60bcd71"),
    "templates": ("Godot_v4.7-stable_export_templates.tpz", "9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec"),
}
FATAL_LOG = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|USER ERROR|ERROR|FATAL|CRASH):|Parse Error:|Segmentation fault|has crashed")
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"Expected an object in {path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def native_platform() -> str:
    value = {"Darwin": "macos", "Windows": "windows"}.get(platform.system())
    require(value is not None, "Native smoke tests require macOS or Windows")
    return value


def run(command: list[str | Path], log: Path, *, timeout: int = 180, required: str | None = None,
        engine_log: Path | None = None, cwd: Path | None = None) -> str:
    """Exit code alone misses GDScript parse/runtime errors; inspect both log streams."""
    log.parent.mkdir(parents=True, exist_ok=True)
    args = [str(item) for item in command]
    print("RUN", subprocess.list2cmdline(args), flush=True)
    try:
        completed = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding="utf-8", errors="replace", timeout=timeout, cwd=cwd)
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        log.write_text(partial + f"\nTIMEOUT after {timeout}s\n", encoding="utf-8")
        raise RuntimeError(f"Process exceeded {timeout}s; see {log}") from error
    output = completed.stdout
    if engine_log and engine_log.exists():
        # GUI Windows executables do not reliably inherit console stdout.
        output += "\n--- Godot log file ---\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    log.write_text(output, encoding="utf-8")
    require(completed.returncode == 0, f"Exit {completed.returncode}; see {log}\n{output[-2500:]}")
    require(not FATAL_LOG.search(output), f"Engine/runtime error; see {log}\n{output[-2500:]}")
    if required:
        require(required in output, f"Missing success marker {required!r}; see {log}")
    return output


def engine_run(engine: Path, arguments: list[str | Path], log: Path, **options) -> str:
    engine_log = log.with_suffix(".engine.log")
    engine_log.parent.mkdir(parents=True, exist_ok=True)
    engine_log.unlink(missing_ok=True)
    return run([engine, "--headless", "--log-file", engine_log, *arguments], log,
               engine_log=engine_log, **options)


def checked_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    members = archive.infolist()
    for member in members:
        path = PurePosixPath(member.filename)
        require(not path.is_absolute() and ".." not in path.parts and "\\" not in member.filename
                and not re.match(r"^[A-Za-z]:", member.filename), f"Unsafe ZIP member: {member.filename}")
        mode = member.external_attr >> 16
        require(not stat.S_ISLNK(mode), f"Symlinks are not supported in install packages: {member.filename}")
    return members


def extract_zip(path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path) as archive:
        for member in checked_members(archive):
            archive.extract(member, destination)
            target = destination / member.filename
            mode = (member.external_attr >> 16) & 0o777
            if mode and not member.is_dir():
                target.chmod(mode)


def fetch_checked(kind: str, cache: Path) -> Path:
    filename, checksum = DOWNLOADS[kind]
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / filename
    if destination.exists() and sha256(destination) == checksum:
        return destination
    destination.unlink(missing_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".partial")
    for attempt in range(3):
        try:
            request = urllib.request.Request(DOWNLOAD_BASE + filename, headers={"User-Agent": "Slopcraft2-build"})
            with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output, length=1024 * 1024)
            require(sha256(temporary) == checksum, f"SHA256 mismatch for official Godot download {filename}")
            temporary.replace(destination)
            return destination
        except Exception:
            temporary.unlink(missing_ok=True)
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def bootstrap(cache: Path, with_templates: bool) -> Path:
    system = native_platform()
    package = fetch_checked(system, cache)
    engine_dir = cache / ("engine-" + system)
    if engine_dir.exists():
        shutil.rmtree(engine_dir)
    extract_zip(package, engine_dir)
    if system == "macos":
        candidates = list(engine_dir.glob("*.app/Contents/MacOS/Godot"))
    else:
        candidates = list(engine_dir.glob("*_console.exe")) or list(engine_dir.glob("*.exe"))
    require(len(candidates) == 1, f"Cannot identify the downloaded Godot executable: {candidates}")
    if with_templates:
        template_zip = fetch_checked("templates", cache)
        base = Path(os.environ["APPDATA"]) / "Godot" if system == "windows" else Path.home() / "Library/Application Support/Godot"
        target = base / "export_templates" / GODOT_VERSION
        with tempfile.TemporaryDirectory(prefix="slop-templates-", dir=cache) as temp:
            extract_zip(template_zip, Path(temp))
            templates = Path(temp) / "templates"
            require(templates.is_dir(), "Godot templates archive has an unexpected layout")
            require((templates / "version.txt").read_text().strip() == GODOT_VERSION, "Template version mismatch")
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(templates, target, dirs_exist_ok=True)
    return candidates[0].resolve()


def check_engine(engine: Path, logs: Path) -> None:
    output = run([engine, "--version"], logs / "engine-version.log")
    require(output.strip().startswith(GODOT_VERSION), f"Expected Godot {GODOT_VERSION}, got {output.strip()}")


def discover_executable(archive_path: Path, system: str, product: str) -> str:
    with zipfile.ZipFile(archive_path) as archive:
        checked_members(archive)
        names = archive.namelist()
        if system == "macos":
            plists = [name for name in names if name.endswith(".app/Contents/Info.plist")]
            require(len(plists) == 1, f"Expected exactly one app bundle in {archive_path}")
            info = plistlib.loads(archive.read(plists[0]))
            name = str(info.get("CFBundleExecutable", ""))
            require(name and "/" not in name and "\\" not in name, "Unsafe CFBundleExecutable")
            executable = str(PurePosixPath(plists[0]).parent / "MacOS" / name)
        else:
            expected = "Slopcraft2.exe" if product == "game" else "Slopcraft2Launcher.exe"
            candidates = [name for name in names if PurePosixPath(name).name == expected]
            require(len(candidates) == 1, f"Expected one {expected} in {archive_path}")
            executable = candidates[0]
            binary = archive.read(executable)
            require(binary[:2] == b"MZ" and len(binary) > 64, "Windows export is not a PE executable")
            pe = struct.unpack_from("<I", binary, 0x3C)[0]
            require(len(binary) > pe + 6 and binary[pe:pe+4] == b"PE\0\0"
                    and struct.unpack_from("<H", binary, pe + 4)[0] == 0x8664, "Windows export must be x86_64")
        require(executable in names, f"Missing bundle executable {executable}")
        return executable


def package_record(path: Path, system: str, product: str, tag: str, repository: str) -> dict:
    executable = discover_executable(path, system, product)
    return {"file": path.name, "sha256": sha256(path), "size": path.stat().st_size,
            "executable": executable, "url": f"https://github.com/{repository}/releases/download/{tag}/{path.name}"}


def merge_catalog(base: dict, entry: dict) -> dict:
    """Replace only this version; keep every unrelated version and catalog field."""
    require(isinstance(base.get("versions", []), list), "Catalog versions must be an array")
    require(bool(entry.get("id")), "Version is missing id")
    result = json.loads(json.dumps(base))
    versions = result.setdefault("versions", [])
    matches = [index for index, value in enumerate(versions) if value.get("id") == entry["id"]]
    require(len(matches) <= 1, f"Duplicate catalog version {entry['id']}")
    if matches:
        versions[matches[0]] = {**versions[matches[0]], **entry}
    else:
        versions.insert(0, entry)
    result.setdefault("schema", 1)
    result.setdefault("repository", REPOSITORY)
    return result


def run_source_tests(engine: Path, project: Path, logs: Path) -> list[str]:
    engine_run(engine, ["--path", project, "--editor", "--import"], logs / "import.log", timeout=300)
    tests = sorted(project.glob("tests/test_*.gd"))
    completed = []
    for script in tests:
        if script.name == "test_packaged_game.gd":
            continue  # Requires a real --package; invoked explicitly after native export.
        engine_run(engine, ["--path", project, "--script", "res://tests/" + script.name],
                   logs / (script.stem + ".log"), timeout=300)
        completed.append(script.name)
    return completed


def export_product(engine: Path, project: Path, product: str, system: str, version: str, dist: Path,
                   logs: Path, staging: Path) -> Path:
    name = "Slopcraft2" if product == "game" else "Slopcraft2Launcher"
    output = dist / f"{name}-{version}-{system}.zip"
    output.unlink(missing_ok=True)
    if system == "macos":
        engine_run(engine, ["--path", project, "--export-release", "macOS", output],
                   logs / f"export-{product}-{system}.log", timeout=600)
    else:
        folder = staging / (product + "-windows")
        folder.mkdir(parents=True)
        engine_run(engine, ["--path", project, "--export-release", "Windows Desktop", folder / (name + ".exe")],
                   logs / f"export-{product}-{system}.log", timeout=600)
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(folder.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(folder).as_posix())
    require(output.exists() and output.stat().st_size > 1024, f"Empty or missing export {output}")
    return output


def verify_packages(dist: Path, metadata: dict) -> None:
    for product in ("game", "launcher"):
        require(set(metadata["packages"][product]) == {"macos", "windows"}, f"Both platforms required for {product}")
        for system, package in metadata["packages"][product].items():
            name = package["file"]
            require(PurePosixPath(name).name == name and "\\" not in name, "Invalid artifact filename")
            path = dist / name
            require(path.is_file() and sha256(path) == package["sha256"], f"Artifact SHA256 mismatch: {name}")
            require(discover_executable(path, system, product) == package["executable"], f"Executable changed in {name}")


def smoke(engine: Path | None, root: Path, dist: Path, system: str) -> None:
    require(native_platform() == system, f"{system} smoke must run on its native operating system")
    metadata = read_json(dist / "build.json")
    verify_packages(dist, metadata)
    logs = dist / "logs" / system
    receipt = {"platform": system, "source_sha": metadata["source_sha"], "version": metadata["version"], "packages": {}, "checks": []}
    with tempfile.TemporaryDirectory(prefix="slop-native-") as directory:
        temp = Path(directory)
        for product in ("game", "launcher"):
            package = metadata["packages"][product][system]
            target = temp / product
            extract_zip(dist / package["file"], target)
            executable = target / package["executable"]
            if system == "macos":
                architectures = run(["lipo", "-archs", executable], logs / f"{product}-architecture.log")
                require({"arm64", "x86_64"}.issubset(set(architectures.split())), f"{product} must be a universal macOS binary")
                bundle = next(parent for parent in executable.parents if parent.suffix == ".app")
                run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", bundle], logs / f"{product}-codesign.log")
            engine_run(executable, ["--quit-after", "120"], logs / f"{product}-title.log", timeout=90, required="Godot Engine")
            receipt["checks"].append(product + "-title")
            if product == "game" and metadata["game_smoke_mode"] in ("world", "legacy"):
                engine_run(executable, ["--", "--smoke-game", "--data-dir", temp / "game-data"],
                           logs / "game-world.log", timeout=120, required="GAME_SMOKE_OK")
                receipt["checks"].append("game-world")
            receipt["packages"][product] = package["sha256"]
        if metadata["game_smoke_mode"] == "world":
            require(engine is not None, "The native editor is required for launcher installation/profile smoke")
            launcher = root / metadata["launcher_path"]
            engine_run(engine, ["--path", launcher, "--editor", "--import"], logs / "launcher-import.log", timeout=300)
            # Legacy fixture writes optional evidence here; ensure the parent exists in CI.
            (launcher / "../../work/snapshot050").resolve().mkdir(parents=True, exist_ok=True)
            engine_run(engine, ["--path", launcher, "--script", "res://tests/test_packaged_game.gd", "--", "--package",
                                dist / metadata["packages"]["game"][system]["file"]],
                       logs / "launcher-install-profile.log", timeout=180, required="PACKAGED GAME:")
            receipt["checks"].append("launcher-install-profile")
    write_json(dist / f"verified-{system}.json", receipt)


def build(args: argparse.Namespace) -> None:
    require(native_platform() == "macos", "The cross-export build currently runs on macOS (Windows verifies natively)")
    root = args.root.resolve()
    dist = args.output.resolve()
    dist.mkdir(parents=True, exist_ok=True)
    engine = args.godot.resolve()
    logs = dist / "logs" / "build"
    check_engine(engine, logs)
    game = (root / args.game_path).resolve()
    launcher = (root / args.launcher_path).resolve()
    base_catalog = read_json(launcher / "manifest.json")
    version = args.version or str(base_catalog["versions"][0]["id"])
    require(bool(IDENTIFIER.fullmatch(version)), "Version may contain only letters, digits, dots, underscores and hyphens")
    existing = next((item for item in base_catalog.get("versions", []) if item.get("id") == version), {})
    category = args.category or existing.get("category", "snapshot")
    require(category in ("stable", "snapshot", "archive"), "Unsupported version category")
    tag = args.tag or f"{category}-{version}"
    require(bool(IDENTIFIER.fullmatch(tag)), "Invalid release tag")
    source_sha = args.source_sha or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    require(bool(re.fullmatch(r"[0-9a-f]{40}", source_sha)), "Source commit must be a full Git SHA")
    tests = {"game": run_source_tests(engine, game, logs / "game"), "launcher": run_source_tests(engine, launcher, logs / "launcher")}
    require(bool(tests["launcher"]), "Launcher has no tests")
    if args.game_smoke_mode == "world":
        require(bool(tests["game"]), "Current game has no tests")
    metadata = {"schema": 1, "godot": GODOT_VERSION, "repository": REPOSITORY, "source_sha": source_sha,
                "version": version, "tag": tag, "category": category, "game_smoke_mode": args.game_smoke_mode,
                "game_path": args.game_path, "launcher_path": args.launcher_path, "tests": tests, "packages": {"game": {}, "launcher": {}}}
    with tempfile.TemporaryDirectory(prefix="slop-export-") as directory:
        stage = Path(directory)
        for system in ("macos", "windows"):
            package = export_product(engine, game, "game", system, version, dist, logs, stage)
            metadata["packages"]["game"][system] = package_record(package, system, "game", tag, REPOSITORY)
        entry = {**existing, "id": version, "category": category, "date": existing.get("date", date.today().isoformat()),
                 "title": args.title or existing.get("title", "Slopcraft 2 " + version), "status": "published",
                 "packages": {system: {key: value for key, value in package.items() if key in ("url", "sha256", "executable", "size")}
                              for system, package in metadata["packages"]["game"].items()}}
        if args.game_smoke_mode in ("title", "legacy"):
            entry["verification"] = ("Native title and world smoke on macOS and Windows; original gameplay and saves retained. Launcher name/skin handoff was added in later versions." if args.game_smoke_mode == "legacy" else "Native title smoke on macOS and Windows; original historical gameplay and saves retained.")
        metadata["catalog_entry"] = entry
        candidate = merge_catalog(base_catalog, entry)
        write_json(dist / "manifest.json", candidate)
        # Bundle the newly verified package URLs without mutating checked-out source.
        staged_launcher = stage / "launcher"
        shutil.copytree(launcher, staged_launcher, ignore=shutil.ignore_patterns(".godot", "*.zip", "*.dmg", "*.exe", "*.pck", ".DS_Store"))
        write_json(staged_launcher / "manifest.json", candidate)
        engine_run(engine, ["--path", staged_launcher, "--editor", "--import"], logs / "launcher-staged-import.log", timeout=300)
        for system in ("macos", "windows"):
            package = export_product(engine, staged_launcher, "launcher", system, version, dist, logs, stage)
            metadata["packages"]["launcher"][system] = package_record(package, system, "launcher", tag, REPOSITORY)
    write_json(dist / "build.json", metadata)
    smoke(engine, root, dist, "macos")
    print(f"Built {version}; macOS verified. Windows verification is still required before publication.")


def verify_release(dist: Path) -> dict:
    metadata = read_json(dist / "build.json")
    verify_packages(dist, metadata)
    required = {"game-title", "launcher-title"}
    if metadata["game_smoke_mode"] in ("world", "legacy"):
        required.add("game-world")
    if metadata["game_smoke_mode"] == "world":
        required.add("launcher-install-profile")
    for system in ("macos", "windows"):
        proof = read_json(dist / f"verified-{system}.json")
        require(proof.get("source_sha") == metadata["source_sha"] and proof.get("version") == metadata["version"], "Verification belongs to another build")
        require(proof.get("platform") == system and required.issubset(set(proof.get("checks", []))), f"Incomplete {system} verification")
        for product in ("game", "launcher"):
            require(proof.get("packages", {}).get(product) == metadata["packages"][product][system]["sha256"], "Verification hash does not match artifact")
    return metadata


def publish(dist: Path) -> None:
    """Intentionally separate from build: requires both native receipts and GH_TOKEN."""
    metadata = verify_release(dist)
    require(bool(os.environ.get("GH_TOKEN")), "Publication requires GH_TOKEN")
    require(metadata["repository"] == REPOSITORY, "Unexpected release repository")
    tag = metadata["tag"]
    probe = subprocess.run(["gh", "release", "view", tag, "--repo", REPOSITORY], capture_output=True, text=True)
    require(probe.returncode != 0, f"Release {tag} already exists; choose a new version rather than replacing binaries")
    notes = dist / "release-notes.md"
    lines = [f"Slopcraft 2 {metadata['version']}", "", f"Source: `{metadata['source_sha']}`. Godot {GODOT_VERSION}.",
             "", "Game and standalone launcher packages passed native macOS and Windows verification.", "",
             "macOS packages are universal (Apple silicon and Intel); Windows packages are x86_64.",
             "macOS builds are ad-hoc signed, not notarized. Windows builds are unsigned.", "", "SHA256:", ""]
    for product in ("game", "launcher"):
        for package in metadata["packages"][product].values():
            lines.append(f"- `{package['file']}`: `{package['sha256']}`")
    notes.write_text("\n".join(lines) + "\n", encoding="utf-8")
    command = ["gh", "release", "create", tag, "--repo", REPOSITORY, "--draft", "--target", metadata["source_sha"],
               "--title", f"Slopcraft 2 {metadata['version']}", "--notes-file", str(notes)]
    if metadata["category"] != "stable": command.append("--prerelease")
    run(command, dist / "logs/publish-create.log")
    artifacts = [dist / package["file"] for product in metadata["packages"].values() for package in product.values()]
    artifacts += [dist / name for name in ("manifest.json", "build.json", "verified-macos.json", "verified-windows.json")]
    run(["gh", "release", "upload", tag, "--repo", REPOSITORY, *artifacts], dist / "logs/publish-upload.log", timeout=600)
    run(["gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false"], dist / "logs/publish-visible.log")
    print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    setup = sub.add_parser("bootstrap")
    setup.add_argument("--cache", type=Path, default=Path(".godot-build-cache"))
    setup.add_argument("--templates", action="store_true")
    builder = sub.add_parser("build")
    builder.add_argument("--root", type=Path, default=Path.cwd())
    builder.add_argument("--godot", type=Path, required=True)
    builder.add_argument("--output", type=Path, default=Path("dist"))
    builder.add_argument("--game-path", default="game")
    builder.add_argument("--launcher-path", default="launcher")
    builder.add_argument("--version", default="")
    builder.add_argument("--category", choices=("stable", "snapshot", "archive"))
    builder.add_argument("--tag", default="")
    builder.add_argument("--title", default="")
    builder.add_argument("--source-sha", default="")
    builder.add_argument("--game-smoke-mode", choices=("world", "legacy", "title"), default="world")
    checker = sub.add_parser("smoke")
    checker.add_argument("--root", type=Path, default=Path.cwd())
    checker.add_argument("--dist", type=Path, default=Path("dist"))
    checker.add_argument("--godot", type=Path)
    checker.add_argument("--platform", choices=("macos", "windows"), required=True)
    for name in ("verify", "publish"):
        command = sub.add_parser(name); command.add_argument("--dist", type=Path, default=Path("dist"))
    catalog = sub.add_parser("catalog")
    catalog.add_argument("--base", type=Path, required=True)
    catalog.add_argument("--dist", type=Path, default=Path("dist"))
    catalog.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "bootstrap":
        engine = bootstrap(args.cache.resolve(), args.templates)
        print(engine)
        if os.environ.get("GITHUB_OUTPUT"):
            with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output: output.write(f"engine={engine}\n")
    elif args.command == "build": build(args)
    elif args.command == "smoke": smoke(args.godot.resolve() if args.godot else None, args.root.resolve(), args.dist.resolve(), args.platform)
    elif args.command == "verify": verify_release(args.dist.resolve()); print("Both platforms and all artifact hashes verified.")
    elif args.command == "publish": publish(args.dist.resolve())
    elif args.command == "catalog":
        metadata = verify_release(args.dist.resolve())
        write_json(args.output, merge_catalog(read_json(args.base), metadata["catalog_entry"]))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f"BUILD FAILED: {error}", file=sys.stderr)
        sys.exit(1)
