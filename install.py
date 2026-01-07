import ctypes
import os
import secrets
import socket
import string
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import requests

MSI_URL = "https://github.com/Drsuporti1406/rustdesk/raw/refs/heads/master/DrSuportiRemote.msi"

# GLPI settings (copied from add_or_update_computers.py; prefer env overrides in production)
BASE_URL_GLPI = os.environ.get("GLPI_BASE_URL", "https://app2.drsuporti.com.br/glpi/apirest.php")
APP_TOKEN = os.environ.get("GLPI_APP_TOKEN", "4sOSHph3toitmF8yVMkvlPesqkMMZnUpJo5nIOhy")
USER_TOKEN = os.environ.get("GLPI_USER_TOKEN", "zPCbzukA0Wzsjz1QeDVPBT70UsDLgxQaSV2BrOA2")
URL_PLUGIN = os.environ.get(
    "GLPI_PLUGIN_URL", "https://app2.drsuporti.com.br/glpi/plugins/drsuportiapi/front/api.php"
)


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

def glpi_init_session() -> str:
    r = requests.get(
        f"{BASE_URL_GLPI}/initSession",
        headers={"App-Token": APP_TOKEN, "Authorization": f"user_token {USER_TOKEN}"},
        timeout=15,
    )
    r.raise_for_status()
    data = r.json()
    token = data.get("session_token")
    if not token:
        raise RuntimeError("GLPI initSession não retornou session_token.")
    return token


def glpi_find_computer_id_by_hostname(session_token: str, hostname: str) -> int | None:
    # Prefer the local plugin, fallback to GLPI search API.
    try:
        r = requests.post(
            URL_PLUGIN,
            headers={"Content-Type": "application/json", "App-Token": APP_TOKEN},
            json={"action": "get_computer_by_hostname", "hostname": hostname},
            timeout=15,
        )
        if r.ok:
            data = r.json()
            if isinstance(data, list) and data and isinstance(data[0], dict) and data[0].get("id"):
                return int(data[0]["id"])
    except Exception:
        pass

    r = requests.get(
        f"{BASE_URL_GLPI}/search/Computer",
        headers={"App-Token": APP_TOKEN, "Session-Token": session_token},
        params={
            "criteria[0][field]": 1,  # name
            "criteria[0][searchtype]": "contains",
            "criteria[0][value]": hostname,
            "forcedisplay[0]": 2,  # id
        },
        timeout=15,
    )
    r.raise_for_status()
    data = r.json()
    if data.get("totalcount", 0) <= 0:
        return None
    first = data.get("data", [])[0]
    comp_id = first.get("2")
    return int(comp_id) if comp_id else None


def glpi_set_remote_id(session_token: str, computer_id: int, rustdesk_id: str) -> None:
    r = requests.post(
        f"{BASE_URL_GLPI}/Item_RemoteManagement/",
        headers={
            "App-Token": APP_TOKEN,
            "Session-Token": session_token,
            "Content-Type": "application/json",
        },
        json={
            "input": {
                "itemtype": "Computer",
                "items_id": computer_id,
                "remoteid": rustdesk_id,
                "type": "rustdesk",
            }
        },
        timeout=15,
    )
    # If the plugin/table rejects "rustdesk" type or duplicates, surface the body to debug.
    if not r.ok:
        raise RuntimeError(f"Falha ao gravar remote id no GLPI: {r.status_code} {r.text}")


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

    hostname = socket.gethostname()
    session_token = glpi_init_session()
    computer_id = glpi_find_computer_id_by_hostname(session_token, hostname)
    if computer_id is None:
        raise SystemExit(f"Computador '{hostname}' não encontrado no GLPI.")
    glpi_set_remote_id(session_token, computer_id, rustdesk_id)

    print("RUSTDESK_ID=", rustdesk_id)
    print("RUSTDESK_PWD=", rustdesk_pwd)
    print("HOSTNAME=", hostname)
    print("GLPI_COMPUTER_ID=", computer_id)
    return rustdesk_id, rustdesk_pwd


if __name__ == "__main__":
    main()
