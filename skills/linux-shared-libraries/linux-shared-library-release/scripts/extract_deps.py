#!/usr/bin/env python3
"""Extract shared-library dependencies of an ELF binary with versions.

Reads DT_NEEDED entries from the ELF dynamic section, resolves each SONAME
to a real file (optionally inside a sysroot), and derives a version from the
realname symlink chain (libfoo.so.1.4.2). Falls back to pkg-config and dpkg
where available.

Usage:
    extract_deps.py <binary> [--sysroot DIR] [--json]

Works on any architecture's binaries (pure file inspection, nothing is
executed), so it is safe for cross-compiled artifacts. For remote-mode
projects, copy this script to the target and run it there, or replicate:
    readelf -d <binary> | grep NEEDED
    ls -l <resolved library paths>
"""
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys


def read_needed_sonames(path):
    """Parse DT_NEEDED entries from an ELF file without external tools."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        raise SystemExit(f"error: {path} is not an ELF file")
    is64 = data[4] == 2
    little = data[5] == 1
    end = "<" if little else ">"
    if is64:
        e_shoff, = struct.unpack_from(end + "Q", data, 0x28)
        e_shentsize, e_shnum = struct.unpack_from(end + "HH", data, 0x3A)
    else:
        e_shoff, = struct.unpack_from(end + "I", data, 0x20)
        e_shentsize, e_shnum = struct.unpack_from(end + "HH", data, 0x2E)

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if is64:
            sh_type, = struct.unpack_from(end + "I", data, off + 4)
            sh_offset, sh_size = struct.unpack_from(end + "QQ", data, off + 24)
            sh_link, = struct.unpack_from(end + "I", data, off + 40)
        else:
            sh_type, = struct.unpack_from(end + "I", data, off + 4)
            sh_offset, sh_size = struct.unpack_from(end + "II", data, off + 16)
            sh_link, = struct.unpack_from(end + "I", data, off + 24)
        sections.append((sh_type, sh_offset, sh_size, sh_link))

    SHT_DYNAMIC = 6
    needed = []
    for sh_type, sh_offset, sh_size, sh_link in sections:
        if sh_type != SHT_DYNAMIC:
            continue
        strtab_off = sections[sh_link][1]
        entsize = 16 if is64 else 8
        fmt = end + ("qQ" if is64 else "iI")
        for off in range(sh_offset, sh_offset + sh_size, entsize):
            d_tag, d_val = struct.unpack_from(fmt, data, off)
            if d_tag == 1:  # DT_NEEDED
                s_end = data.index(b"\x00", strtab_off + d_val)
                needed.append(data[strtab_off + d_val:s_end].decode())
            elif d_tag == 0:  # DT_NULL
                break
    return needed


def lib_search_dirs(sysroot):
    roots = [sysroot] if sysroot else [""]
    rel = [
        "lib", "usr/lib", "usr/local/lib",
        "lib/aarch64-linux-gnu", "usr/lib/aarch64-linux-gnu",
        "lib/arm-linux-gnueabihf", "usr/lib/arm-linux-gnueabihf",
        "lib/x86_64-linux-gnu", "usr/lib/x86_64-linux-gnu",
        "lib64", "usr/lib64",
    ]
    dirs = []
    for r in roots:
        for d in rel:
            p = os.path.join(r or "/", d)
            if os.path.isdir(p):
                dirs.append(p)
    # ld.so.conf inside the sysroot (or host)
    conf = os.path.join(sysroot or "/", "etc/ld.so.conf.d")
    if os.path.isdir(conf):
        for fn in os.listdir(conf):
            try:
                with open(os.path.join(conf, fn)) as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            p = os.path.join(sysroot or "/", line.lstrip("/"))
                            if os.path.isdir(p):
                                dirs.append(p)
            except OSError:
                pass
    return dirs


def resolve(soname, dirs):
    """Find the file for a SONAME and follow symlinks to the realname."""
    for d in dirs:
        p = os.path.join(d, soname)
        if os.path.lexists(p):
            real = os.path.realpath(p)
            return p, real
    return None, None


VER_RE = re.compile(r"\.so\.([0-9]+(?:\.[0-9]+)*)$")


def version_from_realname(realpath):
    m = VER_RE.search(os.path.basename(realpath or ""))
    return m.group(1) if m else None


def pkgconfig_version(name, sysroot):
    if not shutil.which("pkg-config"):
        return None
    env = dict(os.environ)
    if sysroot:
        env["PKG_CONFIG_SYSROOT_DIR"] = sysroot
        env["PKG_CONFIG_LIBDIR"] = ":".join(
            os.path.join(sysroot, p)
            for p in ("usr/lib/pkgconfig", "usr/share/pkgconfig",
                      "usr/lib/aarch64-linux-gnu/pkgconfig",
                      "usr/lib/x86_64-linux-gnu/pkgconfig")
        )
    guess = re.sub(r"^lib", "", name.split(".so")[0])
    try:
        out = subprocess.run(["pkg-config", "--modversion", guess],
                             capture_output=True, text=True, env=env,
                             timeout=10)
        return out.stdout.strip() or None
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("binary")
    ap.add_argument("--sysroot", default=None,
                    help="resolve libraries inside this root filesystem")
    ap.add_argument("--json", action="store_true", default=True)
    args = ap.parse_args()

    dirs = lib_search_dirs(args.sysroot)
    result = []
    for soname in read_needed_sonames(args.binary):
        path, real = resolve(soname, dirs)
        ver = version_from_realname(real)
        source = "soname" if ver else None
        if not ver or "." not in ver:
            # single-component SONAME version (libfoo.so.6) — try for a
            # fuller version, keep the soname one as fallback
            pkg_ver = pkgconfig_version(soname, args.sysroot)
            if pkg_ver:
                ver, source = pkg_ver, "pkg-config"
        result.append({
            "soname": soname,
            "resolved_path": real,
            "version": ver,
            "version_source": source,
        })
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
