import requests
import unicodedata
import json
import os
import sys

# --- Configuração de Segurança ---
BASE_URL_GLPI = "http://192.168.1.250/glpi/apirest.php"
APP_TOKEN = "4sOSHph3toitmF8yVMkvlPesqkMMZnUpJo5nIOhy"
USER_TOKEN = "zPCbzukA0Wzsjz1QeDVPBT70UsDLgxQaSV2BrOA2"
URL_PLUGIN = "http://192.168.1.250/glpi/plugins/drsuportiapi/front/api.php"
API_DRSUPORTI = "https://api1.drsuporti.com.br"
API_KEY_DRSUPORTI = "EHP0PSZP1UN11LZ1PSBQB3JHAC10PNQU"

if not all([BASE_URL_GLPI, APP_TOKEN, USER_TOKEN, URL_PLUGIN, API_DRSUPORTI, API_KEY_DRSUPORTI]):
    print("Erro Crítico: Variáveis de ambiente faltando.")
    sys.exit(1)

# --- Variáveis para Relatório Final ---
report_computers_created = []
report_users_created = []
report_associations_made = []
report_already_associated = []
report_errors = []

# --- Funções Auxiliares ---
def make_request(method, url, headers, params=None, json_payload=None, timeout=10):
    try:
        response = requests.request(method=method, url=url, headers=headers, params=params, json=json_payload, timeout=timeout)
        if response.ok:
            try: return response.json()
            except json.JSONDecodeError: return response.text
        else:
            print(f"Erro API: {response.status_code} - {url}")
            return None
    except Exception as e:
        print(f"Erro requisição: {e}")
        return None

def normalizar(texto: str) -> str:
    if not texto: return ""
    return ''.join(c for c in unicodedata.normalize('NFD', texto) if unicodedata.category(c) != 'Mn').lower()

# --- Início do Script ---
print("Iniciando sessão no GLPI...")
session_data = make_request("GET", f"{BASE_URL_GLPI}/initSession", headers={"App-Token": APP_TOKEN, "Authorization": f"user_token {USER_TOKEN}"})
if not session_data or "session_token" not in session_data:
    sys.exit("Falha crítica ao iniciar sessão.")

session_token = session_data["session_token"]
HEADERS_GLPI = {"App-Token": APP_TOKEN, "Session-Token": session_token, "Content-Type": "application/json"}
HEADERS_DRSUPORTI = {"Content-Type": "application/json", "X-API-KEY": API_KEY_DRSUPORTI}
HEADERS_PLUGIN = {"Content-Type": "application/json", "App-Token": APP_TOKEN}

print("Buscando agentes...")
agents_data = make_request("GET", f"{API_DRSUPORTI}/agents/", headers=HEADERS_DRSUPORTI)
if not isinstance(agents_data, list): sys.exit("Falha ao obter agentes.")

print(f"Processando {len(agents_data)} agentes...")

for agent in agents_data:
    hostname, logged_user, client, site, agent_id = agent.get('hostname'), agent.get('logged_username'), agent.get('client_name'), agent.get('site_name'), agent.get('agent_id')
    if not all([hostname, logged_user, client]): continue

    print(f"\n--- Processando: {hostname} ({logged_user}) ---")
    comp_id, entity_id, user_id = None, None, None

    # 1. Busca Computador
    comp_list = make_request("POST", URL_PLUGIN, headers=HEADERS_PLUGIN, json_payload={"action": "get_computer_by_hostname", "hostname": hostname})
    if comp_list and isinstance(comp_list, list) and len(comp_list) > 0:
        comp_data = comp_list[0]
        comp_id, entity_id, assoc_user_id = comp_data.get('id'), comp_data.get('entities_id'), comp_data.get('users_id')
        print(f"Computador encontrado (ID: {comp_id}).")
    else:
        # 2. Cria Computador se não achou
        print(f"Computador não encontrado. Buscando entidade '{client}'...")
        entity_data = make_request("GET", f"{BASE_URL_GLPI}/search/Entity", headers=HEADERS_GLPI, params={"criteria[0][field]": "1", "criteria[0][searchtype]": "contains", "criteria[0][value]": client, "forcedisplay[0]": "2"})
        
        target_ent_id = None
        if entity_data and entity_data.get("totalcount", 0) > 0:
            entities = entity_data.get('data', [])
            if entity_data.get('totalcount') == 1: target_ent_id = entities[0].get('2')
            else:
                norm_site = normalizar(site)
                for ent in entities:
                    if norm_site and norm_site in normalizar(ent.get('1')): target_ent_id = ent.get('2'); break
                if not target_ent_id: target_ent_id = entities[0].get('2') # Fallback
        
        if target_ent_id:
            print(f"Criando computador na entidade ID {target_ent_id}...")
            new_comp = make_request("POST", f"{BASE_URL_GLPI}/Computer", headers=HEADERS_GLPI, json_payload={"input": {"name": hostname, "entities_id": target_ent_id}})
            if new_comp and 'id' in new_comp:
                comp_id, entity_id = new_comp['id'], target_ent_id
                report_computers_created.append(f"{hostname} (ID: {comp_id}, Entidade: {entity_id})")
                if agent_id: make_request("POST", f"{BASE_URL_GLPI}/Item_RemoteManagement/", headers=HEADERS_GLPI, json_payload={"input": {"itemtype": "Computer", "items_id": comp_id, "remoteid": agent_id, "type": "meshcentral"}})
            else:
                report_errors.append(f"Falha ao criar computador {hostname}")
                continue
        else:
            report_errors.append(f"Entidade não encontrada para {client} ({hostname})")
            continue

    # 3. Associa Usuário
    try: is_assoc = int(assoc_user_id) > 0 if 'assoc_user_id' in locals() and assoc_user_id else False
    except: is_assoc = False

    if is_assoc:
        print("Computador já associado.")
        report_already_associated.append(f"{hostname} -> Usuário ID {assoc_user_id}")
        continue

    print(f"Buscando usuário '{logged_user}'...")
    user_search = make_request("GET", f"{BASE_URL_GLPI}/search/User", headers=HEADERS_GLPI, params={"criteria[0][field]": 2, "criteria[0][value]": logged_user, "criteria[1][field]": 80, "criteria[1][value]": entity_id, "forcedisplay[0]": 2})
    
    if user_search and user_search.get("totalcount", 0) > 0:
        user_id = user_search["data"][0].get("2")
        print(f"Usuário encontrado (ID: {user_id}).")
    else:
        print("Usuário não encontrado. Criando...")
        new_user = make_request("POST", f"{BASE_URL_GLPI}/User/", headers=HEADERS_GLPI, json_payload={"input": {"name": logged_user, "entities_id": entity_id, "is_active": 1}})
        if new_user and "id" in new_user:
            user_id = new_user["id"]
            report_users_created.append(f"{logged_user} (ID: {user_id}, Entidade: {entity_id})")
            make_request("POST", f"{BASE_URL_GLPI}/Profile_User/", headers=HEADERS_GLPI, json_payload={"input": {"users_id": user_id, "entities_id": entity_id, "profiles_id": 8}})
        else:
             report_errors.append(f"Falha ao criar usuário {logged_user} para {hostname}")

    if user_id and comp_id:
        if make_request("PUT", f"{BASE_URL_GLPI}/Computer/{comp_id}", headers=HEADERS_GLPI, json_payload={"input": {"users_id": user_id}}):
            print("Associação realizada com sucesso.")
            report_associations_made.append(f"{hostname} -> {logged_user} (ID: {user_id})")
        else:
            report_errors.append(f"Falha na associação: {hostname} -> {logged_user}")

# --- Relatório Final ---
print("\n" + "="*30)
print("RESUMO DO PROCESSAMENTO")
print("="*30)

print(f"\n[+] Computadores Criados: {len(report_computers_created)}")
for item in report_computers_created: print(f" - {item}")

print(f"\n[+] Usuários Criados: {len(report_users_created)}")
for item in report_users_created: print(f" - {item}")

print(f"\n[+] Novas Associações: {len(report_associations_made)}")
for item in report_associations_made: print(f" - {item}")

print(f"\n[i] Já estavam associados: {len(report_already_associated)}")
# Opcional: descomente para ver a lista completa de quem já estava associado
# for item in report_already_associated: print(f" - {item}")

print(f"\n[!] Erros/Falhas: {len(report_errors)}")
for item in report_errors: print(f" - {item}")
print("="*30)

make_request("GET", f"{BASE_URL_GLPI}/killSession", headers=HEADERS_GLPI)