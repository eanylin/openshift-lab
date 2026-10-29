#!/usr/bin/env python3
"""Repack a wheel so Version becomes <upstream>+rhlw-<build> (Lightwell-style mock).

Red Hat Lightwell docs often show a dotted suffix (.rhlw-0000X). That string is not
valid PEP 440, so pip rejects pins like flask==2.2.2.rhlw-00001. This lab mock uses
the PEP 440 local-version form that pip accepts: 2.2.2+rhlw-0001 — same customer
story (same upstream version + Lightwell build id = backport in place), installable
on the lab. Do not repack newer TL versions (e.g. 3.1.3); that looks like an upgrade.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import re
import tempfile
import zipfile
from pathlib import Path


def pep427_version_for_filename(version: str) -> str:
    """Wheel / .dist-info use '_' where the version has '-'."""
    return version.replace("-", "_")


def find_dist_info(root: Path) -> Path:
    matches = list(root.glob("*.dist-info"))
    if len(matches) != 1:
        raise SystemExit(f"expected one .dist-info, found {matches}")
    return matches[0]


def metadata_field(meta_text: str, field: str) -> str:
    m = re.search(rf"(?m)^{re.escape(field)}:\s*(.+)$", meta_text)
    if not m:
        raise SystemExit(f"no {field}: in METADATA")
    return m.group(1).strip()


def rewrite_metadata(meta_path: Path, new_version: str) -> None:
    text = meta_path.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {new_version}", text, count=1)
    meta_path.write_text(text, encoding="utf-8")


def rebuild_record(root: Path, dist_info: Path) -> None:
    lines: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel == f"{dist_info.name}/RECORD":
            continue
        data = path.read_bytes()
        digest = hashlib.sha256(data).digest()
        b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
        lines.append(f"{rel},sha256={b64},{len(data)}")
    lines.append(f"{dist_info.name}/RECORD,,")
    (dist_info / "RECORD").write_text("\n".join(lines) + "\n", encoding="utf-8")


def wheel_tags_suffix(wheel_name: str) -> str:
    """Return 'py3-none-any' or 'cp312-cp312-manylinux…' from a wheel filename.

    Wheel filenames are '{name}-{version}(-{build})?-{py}-{abi}-{plat}.whl'.
    Always take the last three '-' segments (python, abi, platform).
    """
    if not wheel_name.endswith(".whl"):
        raise SystemExit(f"not a wheel: {wheel_name}")
    stem = wheel_name[: -len(".whl")]
    parts = stem.split("-")
    if len(parts) < 5:
        raise SystemExit(f"cannot parse wheel tags (need ≥5 parts): {wheel_name}")
    return "-".join(parts[-3:])


def normalize_dist_name(name: str) -> str:
    # PEP 503 / wheel: replace runs of [-_.] with -, then for filename use _
    # dist-info uses the name from METADATA with - preferred; wheel file uses _
    return re.sub(r"[-_.]+", "_", name)


def repack(src_wheel: Path, out_dir: Path, rhlw_build: str) -> Path:
    with tempfile.TemporaryDirectory(prefix="rhlw-wheel-") as tmp:
        root = Path(tmp)
        with zipfile.ZipFile(src_wheel, "r") as zf:
            zf.extractall(root)

        dist_info = find_dist_info(root)
        meta = dist_info / "METADATA"
        meta_text = meta.read_text(encoding="utf-8")
        upstream = metadata_field(meta_text, "Version")
        dist_name = metadata_field(meta_text, "Name")
        if "+rhlw" in upstream or ".rhlw-" in upstream:
            raise SystemExit(f"already lightwell-versioned: {upstream}")

        # PEP 440 local version (pip-installable). Docs' ".rhlw-0000X" is not PEP 440.
        new_version = f"{upstream}+rhlw-{rhlw_build}"
        file_ver = pep427_version_for_filename(new_version)
        file_name = normalize_dist_name(dist_name)

        rewrite_metadata(meta, new_version)

        new_dist_info = root / f"{file_name}-{file_ver}.dist-info"
        if dist_info.resolve() != new_dist_info.resolve():
            dist_info.rename(new_dist_info)
            dist_info = new_dist_info

        # Keep data/ directories consistent if present (rare for these pkgs)
        for data_dir in list(root.glob("*.data")):
            # usually Name-Version.data
            suffix = data_dir.name.split(".data", 1)[0]
            # rename to new
            new_data = root / f"{file_name}-{file_ver}.data"
            if data_dir != new_data:
                data_dir.rename(new_data)

        rebuild_record(root, dist_info)

        tags = wheel_tags_suffix(src_wheel.name)
        out_name = f"{file_name}-{file_ver}-{tags}.whl"
        out_path = out_dir / out_name
        out_dir.mkdir(parents=True, exist_ok=True)
        if out_path.exists():
            out_path.unlink()
        with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(root).as_posix())
        return out_path


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("wheel", type=Path)
    p.add_argument("-o", "--out-dir", type=Path, required=True)
    p.add_argument("--rhlw-build", default="0001", help="Lightwell build counter (default 0001)")
    args = p.parse_args()
    out = repack(args.wheel.resolve(), args.out_dir.resolve(), args.rhlw_build)
    print(out)


if __name__ == "__main__":
    main()
