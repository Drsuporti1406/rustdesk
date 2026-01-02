#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import json
import os
import platform
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Sequence
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_HTTP_URL = "https://app2.drsuporti.com.br/glpi/json_store.php"
ENABLE_HTTP_UPLOAD = True


@dataclass(frozen=True)
class PstEntry:
    path: str
    size_bytes: int


def _human_bytes(num: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    value = float(num)
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024.0
    return f"{num} B"


def _iter_fixed_drives() -> list[Path]:
    # DRIVE_FIXED = 3
    DRIVE_FIXED = 3
    GetLogicalDrives = ctypes.windll.kernel32.GetLogicalDrives
    GetDriveTypeW = ctypes.windll.kernel32.GetDriveTypeW

    mask = int(GetLogicalDrives())
    drives: list[Path] = []
    for i in range(26):
        if not (mask & (1 << i)):
            continue
        letter = chr(ord("A") + i)
        root = f"{letter}:\\"
        if int(GetDriveTypeW(ctypes.c_wchar_p(root))) == DRIVE_FIXED:
            drives.append(Path(root))
    return drives


def _get_documents_dir() -> Path | None:
    if os.name != "nt":
        return None

    # Prefer Windows Known Folder API to handle localized folder names.
    # FOLDERID_Documents = {FDD39AD0-238F-46AF-ADB4-6C85480369C7}
    try:
        from ctypes import wintypes

        FOLDERID_Documents = ctypes.c_byte * 16
        folder_id = FOLDERID_Documents(
            0xD0,
            0x9A,
            0xD3,
            0xFD,
            0x8F,
            0x23,
            0xAF,
            0x46,
            0xAD,
            0xB4,
            0x6C,
            0x85,
            0x48,
            0x03,
            0x69,
            0xC7,
        )
        SHGetKnownFolderPath = ctypes.windll.shell32.SHGetKnownFolderPath
        SHGetKnownFolderPath.argtypes = [
            ctypes.POINTER(FOLDERID_Documents),
            wintypes.DWORD,
            wintypes.HANDLE,
            ctypes.POINTER(ctypes.c_wchar_p),
        ]
        SHGetKnownFolderPath.restype = wintypes.HRESULT

        path_ptr = ctypes.c_wchar_p()
        hr = int(SHGetKnownFolderPath(ctypes.byref(folder_id), 0, 0, ctypes.byref(path_ptr)))
        if hr == 0 and path_ptr.value:
            return Path(path_ptr.value)
    except Exception:
        pass

    userprofile = os.environ.get("USERPROFILE")
    if not userprofile:
        return None
    return Path(userprofile) / "Documents"


def _iter_users_documents_dirs(users_root: Path) -> list[Path]:
    docs_dirs: list[Path] = []
    try:
        for entry in users_root.iterdir():
            if not entry.is_dir():
                continue
            name = entry.name.lower()
            if name in {"all users", "default", "default user", "public"}:
                continue
            docs = entry / "Documents"
            if docs.exists() and docs.is_dir():
                docs_dirs.append(docs)
    except OSError:
        return []

    public_docs = users_root / "Public" / "Documents"
    if public_docs.exists() and public_docs.is_dir():
        docs_dirs.append(public_docs)

    return docs_dirs


def _walk_files(roots: Sequence[Path]) -> Iterator[Path]:
    for root in roots:
        root = root.resolve()
        if not root.exists():
            continue
        if root.is_file():
            yield root
            continue
        for dirpath, _dirnames, filenames in os.walk(root, topdown=True):
            base = Path(dirpath)
            for name in filenames:
                yield base / name


def find_pst_entries(roots: Sequence[Path], min_size_bytes: int) -> list[PstEntry]:
    entries: list[PstEntry] = []
    for file_path in _walk_files(roots):
        if file_path.suffix.lower() != ".pst":
            continue
        try:
            size = file_path.stat().st_size
        except OSError:
            continue
        if size < min_size_bytes:
            continue
        entries.append(PstEntry(path=str(file_path), size_bytes=int(size)))
    entries.sort(key=lambda e: e.size_bytes, reverse=True)
    return entries


def _print_table(entries: Iterable[PstEntry]) -> None:
    computer = os.environ.get("COMPUTERNAME") or platform.node() or "unknown"
    print(f"computador: {computer}")
    for e in entries:
        print(f"{e.size_bytes}\t{_human_bytes(e.size_bytes)}\t{e.path}")


def _format_table(entries: Iterable[PstEntry]) -> str:
    computer = os.environ.get("COMPUTERNAME") or platform.node() or "unknown"
    lines = [f"computador: {computer}"]
    for e in entries:
        lines.append(f"{e.size_bytes}\t{_human_bytes(e.size_bytes)}\t{e.path}")
    return "\n".join(lines) + "\n"


def _format_jsonl(entries: Iterable[PstEntry]) -> str:
    computer = os.environ.get("COMPUTERNAME") or platform.node() or "unknown"
    ts = datetime.now(timezone.utc).isoformat()
    lines: list[str] = []
    for e in entries:
        lines.append(
            json.dumps(
                {"computer": computer, "timestamp_utc": ts, "path": e.path, "size_bytes": e.size_bytes},
                ensure_ascii=False,
            )
        )
    return "\n".join(lines) + ("\n" if lines else "")


def _build_http_payload(entries: Sequence[PstEntry]) -> dict:
    computer = os.environ.get("COMPUTERNAME") or platform.node() or "unknown"
    ts = datetime.now(timezone.utc).isoformat()
    def to_gb(size_bytes: int) -> float:
        return round(size_bytes / (1024**3), 3)

    return {
        "computador": computer,
        "timestamp_utc": ts,
        "pst_count": len(entries),
        "pst_total_bytes": sum(e.size_bytes for e in entries),
        "pst_total_gb": to_gb(sum(e.size_bytes for e in entries)),
        "pst_files": [
            {"path": e.path, "size_bytes": e.size_bytes, "size_gb": to_gb(e.size_bytes)} for e in entries
        ],
    }


def _http_put_json(url: str, payload: dict) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(url=url, method="PUT", data=body)
    req.add_header("Content-Type", "application/json; charset=utf-8")
    req.add_header("Accept", "application/json, text/plain, */*")
    with urlopen(req, timeout=30) as resp:
        # Read to completion to ensure request finishes on some servers.
        resp.read()

def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Busca arquivos .pst (Documentos de C:\\Users) e envia o resultado para um endpoint HTTP (Windows)."
    )
    parser.add_argument(
        "roots",
        nargs="*",
        help="Pastas/arquivos raiz para varrer. Se omitido, varre Documentos de todos os usuários em C:\\Users.",
    )
    parser.add_argument(
        "--users-root",
        default=r"C:\Users",
        help="Raiz onde ficam os perfis de usuário (padrão: C:\\Users).",
    )
    parser.add_argument(
        "--min-size-mb",
        type=float,
        default=0.0,
        help="Ignora .pst menores que esse tamanho (em MB). Padrão: 0.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = _parse_args(argv)

    roots: list[Path]
    if args.roots:
        roots = [Path(r) for r in args.roots]
    else:
        if os.name != "nt":
            print("Erro: varredura automática de perfis só funciona no Windows.", file=sys.stderr)
            return 2
        users_root = Path(args.users_root)
        docs_dirs = _iter_users_documents_dirs(users_root)
        if not docs_dirs:
            print(
                f"Erro: não encontrei pastas Documentos em: {users_root}",
                file=sys.stderr,
            )
            return 2
        roots = docs_dirs

    min_size_bytes = int(max(0.0, float(args.min_size_mb)) * 1024 * 1024)
    entries = find_pst_entries(roots=roots, min_size_bytes=min_size_bytes)

    if not ENABLE_HTTP_UPLOAD:
        print("Erro: upload HTTP desabilitado (ENABLE_HTTP_UPLOAD=False).", file=sys.stderr)
        return 4

    try:
        _http_put_json(DEFAULT_HTTP_URL, _build_http_payload(entries))
    except (HTTPError, URLError, TimeoutError, OSError) as e:
        print(f"Erro ao enviar para URL: {DEFAULT_HTTP_URL} ({e})", file=sys.stderr)
        return 4

    # Output local (console) apenas para debug/visibilidade.
    print(_format_table(entries), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
