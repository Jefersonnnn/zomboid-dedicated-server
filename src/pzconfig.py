#
#  Project Zomboid Dedicated Server using SteamCMD Docker Image.
#  Copyright (C) 2021-2022 Renegade-Master; rewritten 2026. GPL-3.0 (see LICENSE).
#
"""Small, safe editors for the Project Zomboid server configuration.

Subcommands:
    ini-set  <ini_file> <key> <value>   Replace an existing ``key=value`` line.
    jvm-heap <json_file> <size>         Set ``-Xmx`` in ProjectZomboid64.json.

Design rules:
    * Files are edited in place, preserving every other line untouched
      (the original tool rewrote the whole .ini through configparser and
      injected a fake ``[ServerConfig]`` header).
    * Unknown ini keys are NOT added. Build 42 may rename keys; adding a key
      the game ignores would fail silently, so we report it instead.
    * Writes are atomic (temp file + rename).

Exit codes: 0 = changed or already correct, 1 = usage/IO error,
2 = key not found in the ini file.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_KEY_NOT_FOUND = 2

HEAP_SIZE_PATTERN = re.compile(r"^[1-9][0-9]*[mMgG]$")
XMX_PREFIX = "-Xmx"


class KeyNotFoundError(LookupError):
    """Raised when an ini key does not exist in the file."""


def atomic_write(path: Path, content: str) -> None:
    """Write ``content`` to ``path`` atomically, keeping its permissions."""
    mode = path.stat().st_mode if path.exists() else None
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as tmp:
            tmp.write(content)
        if mode is not None:
            os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except BaseException:
        Path(tmp_name).unlink(missing_ok=True)
        raise


def set_ini_value(text: str, key: str, value: str) -> tuple[str, bool]:
    """Return ``text`` with ``key``'s value replaced and whether it changed.

    Only the first ``key=`` line is edited; line endings are preserved.
    """
    if "\n" in value or "\r" in value:
        raise ValueError("Value must be a single line.")

    lines = text.splitlines(keepends=True)
    prefix = f"{key}="
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            body = line.rstrip("\r\n")
            ending = line[len(body):]
            new_line = f"{prefix}{value}{ending}"
            lines[index] = new_line
            return "".join(lines), new_line != line
    raise KeyNotFoundError(key)


def set_jvm_heap(config: dict, size: str) -> bool:
    """Set the ``-Xmx`` entry in ``config["vmArgs"]``; return whether it changed."""
    if not HEAP_SIZE_PATTERN.match(size):
        raise ValueError(f"Invalid heap size '{size}' (expected e.g. 4g or 4096m).")

    vm_args = config.get("vmArgs")
    if not isinstance(vm_args, list):
        raise ValueError("'vmArgs' list not found in JVM config.")

    wanted = f"{XMX_PREFIX}{size}"
    others = [arg for arg in vm_args if not str(arg).startswith(XMX_PREFIX)]
    current = [arg for arg in vm_args if str(arg).startswith(XMX_PREFIX)]
    if current == [wanted]:
        return False

    config["vmArgs"] = [wanted, *others]
    return True


def cmd_ini_set(args: argparse.Namespace) -> int:
    path = Path(args.file)
    text = path.read_text(encoding="utf-8")
    try:
        new_text, changed = set_ini_value(text, args.key, args.value)
    except KeyNotFoundError:
        print(f"Key '{args.key}' not found in {path}; not added.", file=sys.stderr)
        return EXIT_KEY_NOT_FOUND
    if changed:
        atomic_write(path, new_text)
    print(f"{args.key}: {'updated' if changed else 'unchanged'}")
    return EXIT_OK


def cmd_jvm_heap(args: argparse.Namespace) -> int:
    path = Path(args.file)
    config = json.loads(path.read_text(encoding="utf-8"))
    changed = set_jvm_heap(config, args.size)
    if changed:
        atomic_write(path, json.dumps(config, indent=4) + "\n")
    print(f"JVM heap {args.size}: {'updated' if changed else 'unchanged'}")
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    ini = sub.add_parser("ini-set", help="replace an existing key in the server .ini")
    ini.add_argument("file")
    ini.add_argument("key")
    ini.add_argument("value")
    ini.set_defaults(handler=cmd_ini_set)

    heap = sub.add_parser("jvm-heap", help="set -Xmx in ProjectZomboid64.json")
    heap.add_argument("file")
    heap.add_argument("size")
    heap.set_defaults(handler=cmd_jvm_heap)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.handler(args)
    except (OSError, ValueError) as error:  # includes JSONDecodeError
        print(f"Error: {error}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
