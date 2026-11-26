#!/usr/bin/env python3
"""Package an arm64 iOS non-jailbreak .dylib into a standard Debian .deb for ESign + TrollStore."""

from __future__ import annotations

import argparse
import io
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import tarfile
import tempfile
import time


FORBIDDEN_LINK_TOKENS = (
    "CydiaSubstrate",
    "libsubstrate",
    "ellekit",
    "libhooker",
    "Substitute",
    "/var/jb/",
)


def make_ar_member(name: str, payload: bytes, mtime: int) -> bytes:
    """Format a standard 60-byte POSIX/Debian ar member header + even-padded payload."""
    name_bytes = name.encode("ascii")
    if len(name_bytes) > 15:
        raise ValueError(f"ar member name exceeds 15 bytes: {name}")
    header = (
        f"{name:<16}"
        f"{mtime:<12d}"
        f"{0:<6d}"
        f"{0:<6d}"
        f"{'100644':<8}"
        f"{len(payload):<10d}"
        f"`\n"
    ).encode("ascii")
    assert len(header) == 60
    pad = b"\n" if (len(payload) % 2 == 1) else b""
    return header + payload + pad


def make_tar_gz(entries: list[tuple[str, bytes, int, bool]], mtime: int) -> bytes:
    """Create a reproducible tar.gz buffer containing directories and regular files."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.USTAR_FORMAT) as tf:
        for arcname, content, mode, is_dir in entries:
            ti = tarfile.TarInfo(name=arcname)
            ti.mtime = mtime
            ti.uid = 0
            ti.gid = 0
            ti.uname = "root"
            ti.gname = "wheel"
            ti.mode = mode
            if is_dir:
                ti.type = tarfile.DIRTYPE
                ti.size = 0
                tf.addfile(ti)
            else:
                ti.type = tarfile.REGTYPE
                ti.size = len(content)
                tf.addfile(ti, io.BytesIO(content))
    return buf.getvalue()


def verify_ios_dylib(dylib_path: pathlib.Path) -> None:
    """Verify the input .dylib is an arm64 iOS device Mach-O without jailbreak dependencies."""
    if not dylib_path.is_file():
        raise FileNotFoundError(f"Missing dylib: {dylib_path}")

    lipo_out = subprocess.check_output(["lipo", "-info", str(dylib_path)], text=True)
    if "arm64" not in lipo_out or "x86_64" in lipo_out:
        raise ValueError(f"Expected arm64-only Mach-O, got: {lipo_out.strip()}")

    otool_deps = subprocess.check_output(["otool", "-L", str(dylib_path)], text=True)
    for bad in FORBIDDEN_LINK_TOKENS:
        if bad.lower() in otool_deps.lower():
            raise ValueError(f"Forbidden jailbreak linkage '{bad}' in {dylib_path}:\n{otool_deps}")

    otool_load = subprocess.check_output(["otool", "-l", str(dylib_path)], text=True)
    if "IOSSIMULATOR" in otool_load or re.search(r"\bplatform\s+7\b", otool_load):
        raise ValueError("Mach-O targets iOS Simulator (platform 7) instead of iPhoneOS")
    if not (re.search(r"\bplatform\s+(?:2|IOS)\b", otool_load) or "LC_VERSION_MIN_IPHONEOS" in otool_load):
        raise ValueError("Mach-O missing iPhoneOS platform (LC_BUILD_VERSION platform IOS)")


def build_deb(
    dylib_path: pathlib.Path,
    out_deb_path: pathlib.Path,
    version: str,
    package_id: str,
    name: str,
    skip_macho_check: bool = False,
) -> pathlib.Path:
    """Build a standard Debian .deb containing Library/MobileSubstrate/DynamicLibraries/<dylib>."""
    if not skip_macho_check:
        verify_ios_dylib(dylib_path)

    dylib_bytes = dylib_path.read_bytes()
    dylib_filename = dylib_path.name
    stem = dylib_path.stem
    plist_bytes = plistlib.dumps({"Filter": {"Bundles": []}}, fmt=plistlib.FMT_XML)
    mtime = int(time.time())

    installed_kb = max(1, (len(dylib_bytes) + len(plist_bytes) + 1023) // 1024)
    control_text = (
        f"Package: {package_id}\n"
        f"Name: {name}\n"
        f"Version: {version}\n"
        f"Architecture: iphoneos-arm\n"
        f"Description: Standalone non-jailbreak UIKit QA touch & swipe recorder overlay (iOS 16.0+)\n"
        f"Maintainer: Local QA\n"
        f"Author: Local QA\n"
        f"Section: Tweaks\n"
        f"Installed-Size: {installed_kb}\n"
    ).encode("utf-8")

    control_tar = make_tar_gz(
        [("./control", control_text, 0o644, False)],
        mtime=mtime,
    )
    data_tar = make_tar_gz(
        [
            ("./Library", b"", 0o755, True),
            ("./Library/MobileSubstrate", b"", 0o755, True),
            ("./Library/MobileSubstrate/DynamicLibraries", b"", 0o755, True),
            (f"./Library/MobileSubstrate/DynamicLibraries/{dylib_filename}", dylib_bytes, 0o755, False),
            (f"./Library/MobileSubstrate/DynamicLibraries/{stem}.plist", plist_bytes, 0o644, False),
        ],
        mtime=mtime,
    )

    deb_bytes = (
        b"!<arch>\n"
        + make_ar_member("debian-binary", b"2.0\n", mtime)
        + make_ar_member("control.tar.gz", control_tar, mtime)
        + make_ar_member("data.tar.gz", data_tar, mtime)
    )

    out_deb_path.parent.mkdir(parents=True, exist_ok=True)
    out_deb_path.write_bytes(deb_bytes)
    return out_deb_path


def run_self_test() -> None:
    """Verify .deb generation structure with standard ar and tar tools."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = pathlib.Path(tmp)
        dummy_dylib = tmp_dir / "QATouchRecorder.dylib"
        dummy_dylib.write_bytes(b"DUMMY_PAYLOAD_FOR_ARCHIVE_TEST")
        deb_path = tmp_dir / "test.deb"

        build_deb(
            dylib_path=dummy_dylib,
            out_deb_path=deb_path,
            version="0.1.0",
            package_id="com.local.qa-touch-recorder",
            name="QA Touch Recorder",
            skip_macho_check=True,
        )

        members = subprocess.check_output(["ar", "-t", str(deb_path)], text=True).splitlines()
        assert members == ["debian-binary", "control.tar.gz", "data.tar.gz"], members

        ctrl_tar = subprocess.check_output(["ar", "-p", str(deb_path), "control.tar.gz"])
        with tarfile.open(fileobj=io.BytesIO(ctrl_tar), mode="r:gz") as tf:
            ctrl_txt = tf.extractfile("./control").read().decode("utf-8")
        assert "Package: com.local.qa-touch-recorder" in ctrl_txt
        assert "Architecture: iphoneos-arm" in ctrl_txt
        assert "mobilesubstrate" not in ctrl_txt.lower()

        data_tar = subprocess.check_output(["ar", "-p", str(deb_path), "data.tar.gz"])
        with tarfile.open(fileobj=io.BytesIO(data_tar), mode="r:gz") as tf:
            names = tf.getnames()
            assert "./Library/MobileSubstrate/DynamicLibraries/QATouchRecorder.dylib" in names, names
            assert "./Library/MobileSubstrate/DynamicLibraries/QATouchRecorder.plist" in names, names
            extracted = tf.extractfile("./Library/MobileSubstrate/DynamicLibraries/QATouchRecorder.dylib").read()
            assert extracted == b"DUMMY_PAYLOAD_FOR_ARCHIVE_TEST"

    print("PASS: package-deb.py self-test passed.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Package QATouchRecorder.dylib into a .deb archive")
    parser.add_argument("--dylib", type=pathlib.Path, help="Path to compiled arm64 iOS QATouchRecorder.dylib")
    parser.add_argument("--out", type=pathlib.Path, help="Output .deb path")
    parser.add_argument("--version", default="0.1.0", help="Debian package version")
    parser.add_argument("--package-id", default="com.local.qa-touch-recorder")
    parser.add_argument("--name", default="QA Touch Recorder")
    parser.add_argument("--self-test", action="store_true", help="Run archive format self-test")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return 0

    if not args.dylib or not args.out:
        parser.error("--dylib and --out are required unless --self-test is set")

    out_path = build_deb(
        dylib_path=args.dylib,
        out_deb_path=args.out,
        version=args.version,
        package_id=args.package_id,
        name=args.name,
    )
    print(f"Packaged .deb: {out_path} ({out_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
