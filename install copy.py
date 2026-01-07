import ctypes
import os
import secrets
import string
import subprocess
import tempfile
import urllib.request
from pathlib import Path

MSI_URL = "https://github.com/Drsuporti1406/rustdesk/raw/refs/heads/master/DrSuportiRemote.msi"


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def run(cmd, check: bool = True):
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def try_taskkill(image_name: str) -> None:
    run(["taskkill", "/IM", image_name, "/F"], check=False)


def summarize_msi_log(log_path: str, max_lines: int = 120) -> str:
    try:
        text = Path(log_path).read_text(errors="replace").splitlines()
    except Exception as e:
        return f"(falha ao ler log do MSI: {e})"

    hits = [i for i, line in enumerate(text) if "Return value 3" in line]
    if hits:
        start = max(0, hits[-1] - 60)
        end = min(len(text), hits[-1] + 20)
        snippet = text[start:end]
        return "\n".join(snippet[-max_lines:])

    return "\n".join(text[-max_lines:])


def find_rustdesk_exe() -> str:
    candidates = [
        os.path.join(
            os.environ.get("ProgramFiles", r"C:\Program Files"),
            "DrSuporti Remote",
            "rustdesk.exe",
        ),
        os.path.join(
            os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
            "DrSuporti Remote",
            "rustdesk.exe",
        ),
        os.path.join(
            os.environ.get("ProgramFiles", r"C:\Program Files"), "RustDesk", "rustdesk.exe"
        ),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    raise FileNotFoundError(
        "rustdesk.exe não encontrado nas pastas padrão (Program Files)."
    )


def gen_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def main():
    if not is_admin():
        raise SystemExit("Execute este script como Administrador.")

    tmpdir = tempfile.mkdtemp(prefix="drsuporti_")
    msi_path = os.path.join(tmpdir, "DrSuportiRemote.msi")
    log_path = os.path.join(tmpdir, "msi-install.log")

    urllib.request.urlretrieve(MSI_URL, msi_path)

    try_taskkill("rustdesk.exe")
    res = run(["msiexec", "/i", msi_path, "/qn", "/norestart", "/L*V", log_path], check=False)
    if res.returncode != 0:
        details = summarize_msi_log(log_path)
        raise SystemExit(
            "Falha ao instalar MSI (msiexec).\n"
            f"- Exit code: {res.returncode} (1603 é erro genérico)\n"
            f"- Log: {log_path}\n\n"
            "Trecho relevante do log:\n"
            f"{details}\n\n"
            "Dicas comuns:\n"
            "- Desinstale versões antigas do DrSuporti Remote/RustDesk e tente novamente\n"
            "- Feche processos/serviço do RustDesk antes de instalar\n"
            "- Verifique se você tem permissão de instalação (per-machine)\n"
        )

    rustdesk_exe = find_rustdesk_exe()
    rustdesk_id = run([rustdesk_exe, "--get-id"]).stdout.strip()

    rustdesk_pwd = gen_password()
    run([rustdesk_exe, "--password", rustdesk_pwd])

    print("RUSTDESK_ID=", rustdesk_id)
    print("RUSTDESK_PWD=", rustdesk_pwd)
    return rustdesk_id, rustdesk_pwd


if __name__ == "__main__":
    main()
