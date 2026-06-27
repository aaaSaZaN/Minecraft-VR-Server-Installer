#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import socket
import platform
import subprocess
import urllib.request
import urllib.parse
import time

# --- ANSI Colors for Premium CLI Look ---
if platform.system() == 'Windows':
    # Enable ANSI escape sequences on Windows CMD/PowerShell if supported
    os.system('')

COLOR_TITLE = '\033[95m'   # Purple
COLOR_INFO = '\033[94m'    # Blue
COLOR_SUCCESS = '\033[92m' # Green
COLOR_WARN = '\033[93m'    # Yellow
COLOR_FAIL = '\033[91m'    # Red
COLOR_BOLD = '\033[1m'
COLOR_RESET = '\033[0m'

def print_banner():
    banner = f"""
{COLOR_TITLE}{COLOR_BOLD}=============================================================
    __  ___ _                                 __ _      ____ 
   /  |/  /(_)____   ___   _____  _____ ____ _/ //_/     / __ \\\\
  / /|_/ // // __ \\\\ / _ \\\\ / ___/ / ___// __ `/ __/ /| /| / /_/ /
 / /  / // // / / //  __// /__  / /   / /_/ / /_  / |/ |/ /_, _/ 
/_/  /_//_//_/ /_/ \\___/ \\___/ /_/    \\__,_/\\__/  /__/|__/_/ |_|  
                                                             
               VR SERVER & CLIENT AUTO-INSTALLER
============================================================={COLOR_RESET}
"""
    print(banner)

def get_input(prompt, default_val=None):
    prompt_str = f"{COLOR_BOLD}{prompt}{COLOR_RESET}"
    if default_val is not None:
        prompt_str += f" [{COLOR_INFO}{default_val}{COLOR_RESET}]: "
    else:
        prompt_str += ": "
    
    val = input(prompt_str).strip()
    if not val and default_val is not None:
        return default_val
    return val

def check_docker():
    print(f"\n{COLOR_INFO}[*] Проверка Docker...{COLOR_RESET}")
    
    # 1. Check docker command
    try:
        res = subprocess.run(['docker', '--version'], capture_output=True, text=True, check=False)
        if res.returncode != 0:
            return False, "Docker не запущен или не установлен."
        docker_ver = res.stdout.strip()
        print(f"{COLOR_SUCCESS}[✓] Найден Docker: {docker_ver}{COLOR_RESET}")
    except FileNotFoundError:
        return False, "Команда 'docker' не найдена."

    # 2. Check docker compose support
    compose_cmd = None
    try:
        res = subprocess.run(['docker', 'compose', 'version'], capture_output=True, text=True, check=False)
        if res.returncode == 0:
            compose_cmd = ['docker', 'compose']
            print(f"{COLOR_SUCCESS}[✓] Найден встроенный Docker Compose: {res.stdout.strip()}{COLOR_RESET}")
    except Exception:
        pass
        
    if not compose_cmd:
        try:
            res = subprocess.run(['docker-compose', '--version'], capture_output=True, text=True, check=False)
            if res.returncode == 0:
                compose_cmd = ['docker-compose']
                print(f"{COLOR_SUCCESS}[✓] Найден классический docker-compose: {res.stdout.strip()}{COLOR_RESET}")
        except FileNotFoundError:
            pass
            
    if not compose_cmd:
        return False, "Docker установлен, но Docker Compose не найден. Пожалуйста, установите Docker Compose."
        
    return compose_cmd, None

def install_docker():
    system = platform.system()
    print(f"\n{COLOR_WARN}[!] Docker не найден в вашей системе!{COLOR_RESET}")
    
    if system == "Windows":
        print(f"{COLOR_INFO}Мы можем попробовать установить Docker Desktop через Windows Winget (требуются права администратора).{COLOR_RESET}")
        ans = get_input("Запустить установку Docker Desktop? (y/n)", "y").lower()
        if ans == 'y':
            print(f"{COLOR_INFO}[*] Запуск winget install Docker.DockerDesktop...{COLOR_RESET}")
            try:
                res = subprocess.run(['winget', 'install', 'Docker.DockerDesktop', '--accept-source-agreements', '--accept-package-agreements'], check=False)
                if res.returncode == 0:
                    print(f"{COLOR_SUCCESS}[✓] Установка завершена! Возможно, потребуется ПЕРЕЗАГРУЗИТЬ компьютер, чтобы Docker заработал.{COLOR_RESET}")
                    return True
                else:
                    print(f"{COLOR_FAIL}[✕] Ошибка при установке через Winget. Пожалуйста, скачайте Docker Desktop вручную:{COLOR_RESET}")
                    print(f"{COLOR_BOLD}https://www.docker.com/products/docker-desktop/{COLOR_RESET}")
            except FileNotFoundError:
                print(f"{COLOR_FAIL}[✕] Утилита 'winget' не найдена. Пожалуйста, установите Docker Desktop вручную с:{COLOR_RESET}")
                print(f"{COLOR_BOLD}https://www.docker.com/products/docker-desktop/{COLOR_RESET}")
        else:
            print(f"{COLOR_INFO}Пожалуйста, установите Docker Desktop вручную перед продолжением.{COLOR_RESET}")
            
    elif system == "Linux":
        print(f"{COLOR_INFO}Мы можем запустить официальный скрипт установки Docker (потребуются права root/sudo).{COLOR_RESET}")
        ans = get_input("Установить Docker автоматически через curl? (y/n)", "y").lower()
        if ans == 'y':
            print(f"{COLOR_INFO}[*] Скачивание и запуск скрипта установки Docker...{COLOR_RESET}")
            try:
                script_path = "/tmp/get-docker.sh"
                urllib.request.urlretrieve("https://get.docker.com", script_path)
                res = subprocess.run(['sudo', 'sh', script_path], check=False)
                if res.returncode == 0:
                    print(f"{COLOR_SUCCESS}[✓] Docker успешно установлен!{COLOR_RESET}")
                    print(f"{COLOR_INFO}[*] Добавляем текущего пользователя в группу docker (чтобы запускать без sudo)...{COLOR_RESET}")
                    user = os.getlogin() if hasattr(os, 'getlogin') else os.getenv('USER', 'root')
                    subprocess.run(['sudo', 'usermod', '-aG', 'docker', user], check=False)
                    print(f"{COLOR_WARN}[!] Пожалуйста, перезайдите в систему (выполните logout/login), чтобы изменения группы вступили в силу.{COLOR_RESET}")
                    return True
                else:
                    print(f"{COLOR_FAIL}[✕] Не удалось автоматически установить Docker.{COLOR_RESET}")
            except Exception as e:
                print(f"{COLOR_FAIL}[✕] Ошибка установки: {e}{COLOR_RESET}")
        else:
            print(f"{COLOR_INFO}Установите Docker вручную с помощью вашего пакетного менеджера (например, apt, yum, pacman).{COLOR_RESET}")
    else:
        print(f"{COLOR_FAIL}[✕] Автоматическая установка не поддерживается для ОС: {system}. Пожалуйста, установите Docker вручную.{COLOR_RESET}")
        
    return False

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 1))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def fetch_modrinth_version(slug, mc_version, loader):
    url = f"https://api.modrinth.com/v2/project/{slug}/version"
    headers = {
        'User-Agent': 'antigravity/minecraft-vr-installer/1.0 (antigravity@gemini.ai)'
    }
    
    loader_search = loader.lower()
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            versions = json.loads(response.read().decode('utf-8'))
            
            matching = []
            for v in versions:
                if mc_version not in v.get('game_versions', []):
                    continue
                loaders = v.get('loaders', [])
                if loader_search not in loaders and 'minecraft' not in loaders:
                    continue
                matching.append(v)
                
            if not matching:
                return None
                
            for v in matching:
                if v.get('version_type') == 'release':
                    return v
            return matching[0]
    except Exception as e:
        print(f"  {COLOR_FAIL}[✕] Ошибка запроса к Modrinth для {slug}: {e}{COLOR_RESET}")
        return None

def download_file(url, dest_path):
    headers = {
        'User-Agent': 'antigravity/minecraft-vr-installer/1.0 (antigravity@gemini.ai)'
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            total_size = int(response.headers.get('content-length', 0))
            bytes_downloaded = 0
            block_size = 8192
            
            with open(dest_path, 'wb') as f:
                while True:
                    buffer = response.read(block_size)
                    if not buffer:
                        break
                    f.write(buffer)
                    bytes_downloaded += len(buffer)
                    if total_size > 0:
                        percent = int(bytes_downloaded * 100 / total_size)
                        sys.stdout.write(f"\r  Прогресс: {percent}% ({bytes_downloaded // 1024} KB / {total_size // 1024} KB)")
                        sys.stdout.flush()
            print()
            return True
    except Exception as e:
        print(f"\n  {COLOR_FAIL}[✕] Ошибка скачивания {url}: {e}{COLOR_RESET}")
        return False

def handle_mods(mc_version, loader, voice_enabled):
    print(f"\n{COLOR_INFO}[*] Поиск и скачивание модов с Modrinth для версии {mc_version} ({loader})...{COLOR_RESET}")
    
    base_dir = os.path.dirname(os.path.abspath(__file__))
    server_mods_dir = os.path.join(base_dir, "server", "data", "mods")
    client_mods_dir = os.path.join(base_dir, "client_mods")
    
    os.makedirs(server_mods_dir, exist_ok=True)
    os.makedirs(client_mods_dir, exist_ok=True)
    
    mod_list = [
        ("vivecraft", "Vivecraft (VR мод)", True, True)
    ]
    
    if loader.lower() == 'fabric':
        mod_list.append(("fabric-api", "Fabric API (Библиотека)", True, True))
        mod_list.append(("sodium", "Sodium (Оптимизация рендера)", False, True))
        mod_list.append(("iris", "Iris Shaders (Поддержка шейдеров)", False, True))
    elif loader.lower() in ('forge', 'neoforge'):
        mod_list.append(("embeddium", "Embeddium (Sodium для Forge)", False, True))
        mod_list.append(("oculus", "Oculus (Iris для Forge)", False, True))
        
    if voice_enabled:
        mod_list.append(("simple-voice-chat", "Simple Voice Chat (Голосовой чат)", True, True))

    for slug, name, on_server, on_client in mod_list:
        print(f"\n{COLOR_BOLD}Обработка {name}...{COLOR_RESET}")
        
        mod_info = fetch_modrinth_version(slug, mc_version, loader)
        if not mod_info:
            print(f"  {COLOR_WARN}[!] Подходящая версия для {slug} на Modrinth не найдена. Пропустите или скачайте вручную.{COLOR_RESET}")
            continue
            
        files = mod_info.get("files", [])
        if not files:
            print(f"  {COLOR_WARN}[!] В релизе {slug} отсутствуют файлы.{COLOR_RESET}")
            continue
            
        file_obj = None
        for f in files:
            if f.get("primary"):
                file_obj = f
                break
        if not file_obj:
            file_obj = files[0]
            
        download_url = file_obj.get("url")
        filename = file_obj.get("filename")
        
        dests = []
        if on_server:
            dests.append((os.path.join(server_mods_dir, filename), "на сервер"))
        if on_client:
            dests.append((os.path.join(client_mods_dir, filename), "на клиент"))
            
        for path, target in dests:
            if os.path.exists(path):
                print(f"  [✓] Файл {filename} уже скачан ({target}). Пропуск.")
                continue
                
            print(f"  Скачивание {filename} ({target})...")
            success = download_file(download_url, path)
            if success:
                print(f"  {COLOR_SUCCESS}[✓] Скачано успешно ({target}){COLOR_RESET}")

def handle_existing_install(compose_cmd, server_dir):
    compose_path = os.path.join(server_dir, "docker-compose.yml")
    if not os.path.exists(compose_path):
        return False
        
    print(f"\n{COLOR_WARN}[!] Обнаружена существующая установка сервера в папке {server_dir}{COLOR_RESET}")
    print("Выберите действие:")
    print(f"1) {COLOR_SUCCESS}Запустить сервер{COLOR_RESET}")
    print(f"2) {COLOR_FAIL}Остановить сервер{COLOR_RESET}")
    print(f"3) {COLOR_INFO}Посмотреть логи сервера{COLOR_RESET}")
    print(f"4) {COLOR_TITLE}Перенастроить сервер (свежая установка){COLOR_RESET}")
    
    choice = get_input("Введите вариант (1-4)", "1")
    if choice == "1":
        print(f"\n{COLOR_INFO}[*] Запуск сервера...{COLOR_RESET}")
        res = subprocess.run(compose_cmd + ["up", "-d"], cwd=server_dir)
        if res.returncode == 0:
            print(f"{COLOR_SUCCESS}[✓] Сервер успешно запущен в фоновом режиме.{COLOR_RESET}")
            local_ip = get_local_ip()
            # Try to extract the port from docker-compose.yml
            port = "25565"
            try:
                with open(compose_path, "r", encoding="utf-8") as f:
                    content = f.read()
                    import re
                    # Look for port mapping like "25565:25565"
                    match = re.search(r'"(\d+):25565"', content)
                    if match:
                        port = match.group(1)
                    else:
                        match_env = re.search(r'SERVER_PORT:\s*"(\d+)"', content)
                        if match_env:
                            port = match_env.group(1)
            except Exception:
                pass
            print(f"\n📍 IP-адрес для подключения игроков в локальной сети:")
            print(f"   {COLOR_SUCCESS}{COLOR_BOLD}{local_ip}:{port}{COLOR_RESET}")
        else:
            print(f"{COLOR_FAIL}[✕] Не удалось запустить сервер.{COLOR_RESET}")
        return True
    elif choice == "2":
        print(f"\n{COLOR_INFO}[*] Остановка сервера...{COLOR_RESET}")
        res = subprocess.run(compose_cmd + ["down"], cwd=server_dir)
        if res.returncode == 0:
            print(f"{COLOR_SUCCESS}[✓] Сервер успешно остановлен.{COLOR_RESET}")
        else:
            print(f"{COLOR_FAIL}[✕] Не удалось остановить сервер.{COLOR_RESET}")
        return True
    elif choice == "3":
        print(f"\n{COLOR_INFO}[*] Загрузка логов (нажмите Ctrl+C для выхода)...{COLOR_RESET}")
        try:
            subprocess.run(compose_cmd + ["logs", "-f", "minecraft-server"], cwd=server_dir)
        except KeyboardInterrupt:
            print("\n Выход из просмотра логов.")
        return True
    elif choice == "4":
        print(f"\n{COLOR_INFO}[*] Начинаем перенастройку...{COLOR_RESET}")
        return False # Continue main setup flow
    return False

def create_desktop_shortcuts(compose_cmd, server_dir):
    system = platform.system()
    desktop_path = None
    
    if system == "Windows":
        profile = os.environ.get('USERPROFILE', '')
        desktop_options = [
            os.path.join(profile, 'Desktop'),
            os.path.join(profile, 'OneDrive', 'Рабочий стол'),
            os.path.join(profile, 'OneDrive', 'Desktop'),
            os.path.join(profile, 'Desktop')
        ]
        for path in desktop_options:
            if os.path.exists(path):
                desktop_path = path
                break
    else:
        desktop_path = os.path.join(os.path.expanduser('~'), 'Desktop')
        
    if not desktop_path or not os.path.exists(desktop_path):
        desktop_path = os.path.expanduser('~')
        
    print(f"\n{COLOR_INFO}[*] Создание ярлыков для удобного управления на Рабочем столе...{COLOR_RESET}")
    
    cmd_prefix = " ".join(compose_cmd)
    
    if system == "Windows":
        start_bat = os.path.join(desktop_path, "Minecraft_VR_Server_START.bat")
        stop_bat = os.path.join(desktop_path, "Minecraft_VR_Server_STOP.bat")
        
        with open(start_bat, "w", encoding="utf-8") as f:
            f.write(f'@echo off\nchcp 65001 > nul\ncd /d "{server_dir}"\n{cmd_prefix} up -d\necho [✓] Minecraft VR Server started!\npause\n')
        
        with open(stop_bat, "w", encoding="utf-8") as f:
            f.write(f'@echo off\nchcp 65001 > nul\ncd /d "{server_dir}"\n{cmd_prefix} down\necho [✓] Minecraft VR Server stopped!\npause\n')
            
        print(f"{COLOR_SUCCESS}[✓] Созданы файлы управления на Рабочем столе:{COLOR_RESET}")
        print(f"    - Запуск: {start_bat}")
        print(f"    - Остановка: {stop_bat}")
        
    else: # Linux/macOS
        start_sh = os.path.join(desktop_path, "Minecraft_VR_Server_START.sh")
        stop_sh = os.path.join(desktop_path, "Minecraft_VR_Server_STOP.sh")
        
        with open(start_sh, "w", encoding="utf-8") as f:
            f.write(f'#!/bin/bash\ncd "{server_dir}"\n{cmd_prefix} up -d\necho "[✓] Minecraft VR Server started!"\nread -p "Press enter to exit..."\n')
        os.chmod(start_sh, 0o755)
        
        with open(stop_sh, "w", encoding="utf-8") as f:
            f.write(f'#!/bin/bash\ncd "{server_dir}"\n{cmd_prefix} down\necho "[✓] Minecraft VR Server stopped!"\nread -p "Press enter to exit..."\n')
        os.chmod(stop_sh, 0o755)
        
        print(f"{COLOR_SUCCESS}[✓] Созданы скрипты управления на Рабочем столе:{COLOR_RESET}")
        print(f"    - Запуск: {start_sh}")
        print(f"    - Остановка: {stop_sh}")

def main():
    print_banner()
    
    compose_cmd, err = check_docker()
    if not compose_cmd:
        print(f"{COLOR_FAIL}[✕] Проверка Docker провалена: {err}{COLOR_RESET}")
        if not install_docker():
            print(f"\n{COLOR_FAIL}Пожалуйста, настройте Docker и запустите скрипт заново.{COLOR_RESET}")
            sys.exit(1)
        compose_cmd, err = check_docker()
        if not compose_cmd:
            print(f"{COLOR_FAIL}Docker был установлен, но всё ещё не обнаруживается в текущей сессии консоли.{COLOR_RESET}")
            print(f"{COLOR_WARN}Перезапустите консоль/компьютер и запустите скрипт заново.{COLOR_RESET}")
            sys.exit(1)

    base_dir = os.path.dirname(os.path.abspath(__file__))
    server_dir = os.path.join(base_dir, "server")

    if handle_existing_install(compose_cmd, server_dir):
        return

    print(f"\n{COLOR_BOLD}=== НАСТРОЙКА MINECRAFT СЕРВЕРА ==={COLOR_RESET}\n")
    
    mc_version = get_input("Введите версию Minecraft", "1.20.1")
    
    print("\nВыберите ядро (мод-лоадер):")
    print(f"1) {COLOR_INFO}Fabric{COLOR_RESET} (Рекомендуется для VR - лучшая совместимость и FPS)")
    print(f"2) {COLOR_INFO}Forge{COLOR_RESET}")
    print(f"3) {COLOR_INFO}NeoForge{COLOR_RESET}")
    loader_choice = get_input("Выберите вариант (1-3)", "1")
    
    loader_map = {"1": "fabric", "2": "forge", "3": "neoforge"}
    loader_type = loader_map.get(loader_choice, "fabric")
    
    ram_gb = get_input("Сколько ГБ оперативной памяти выделить серверу", "4")
    if not ram_gb.endswith('G') and not ram_gb.endswith('M'):
        ram_gb = f"{ram_gb}G"
        
    online_input = get_input("Разрешить вход без лицензии (пиратский режим)? (y/n)", "y").lower()
    online_mode = "FALSE" if online_input == 'y' else "TRUE"
    
    server_port = get_input("Основной порт сервера", "25565")
    
    voice_chat_input = get_input("Установить 3D Голосовой чат (Simple Voice Chat)? (y/n)", "y").lower()
    voice_enabled = voice_chat_input == 'y'
    
    vr_mods_input = get_input("Скачать VR моды (Vivecraft, Iris, Sodium и др.)? (y/n)", "y").lower()
    vr_enabled = vr_mods_input == 'y'

    print(f"\n{COLOR_INFO}[*] Генерация docker-compose.yml...{COLOR_RESET}")
    
    os.makedirs(server_dir, exist_ok=True)
    compose_path = os.path.join(server_dir, "docker-compose.yml")
    
    is_windows = platform.system() == "Windows"
    voice_port = "24454"
    
    compose_lines = [
        "services:",
        "  minecraft-server:",
        "    image: itzg/minecraft-server:latest",
        "    container_name: mc-vr-server",
    ]
    
    if is_windows:
        compose_lines.extend([
            "    ports:",
            f"      - \"{server_port}:25565\"",
        ])
        if voice_enabled:
            compose_lines.append(f"      - \"{voice_port}:{voice_port}/udp\"")
    else:
        compose_lines.append("    network_mode: host")
        
    compose_lines.extend([
        "    environment:",
        "      EULA: \"TRUE\"",
        f"      VERSION: \"{mc_version}\"",
        f"      TYPE: \"{loader_type.upper()}\"",
        f"      MEMORY: \"{ram_gb}\"",
        f"      ONLINE_MODE: \"{online_mode}\"",
        "      ENABLE_RCON: \"true\"",
        "      RCON_PASSWORD: \"minecraft_rcon_pass\"",
    ])
    
    if not is_windows:
        compose_lines.append(f"      SERVER_PORT: \"{server_port}\"")
        
    compose_lines.extend([
        "    volumes:",
        "      - ./data:/data",
        "    restart: unless-stopped"
    ])
    
    compose_content = "\n".join(compose_lines)
    
    with open(compose_path, "w", encoding='utf-8') as f:
        f.write(compose_content)
        
    print(f"{COLOR_SUCCESS}[✓] docker-compose.yml создан в {compose_path}{COLOR_RESET}")

    if vr_enabled:
        handle_mods(mc_version, loader_type, voice_enabled)
        
    print(f"\n{COLOR_INFO}[*] Запуск Docker контейнера с сервером Майнкрафт...{COLOR_RESET}")
    print(f"{COLOR_INFO}    (Это может занять некоторое время при первом запуске, скачивается образ){COLOR_RESET}")
    
    try:
        run_args = compose_cmd + ["up", "-d"]
        res = subprocess.run(run_args, cwd=server_dir, check=False)
        if res.returncode == 0:
            print(f"\n{COLOR_SUCCESS}[✓] Сервер Майнкрафт успешно запущен в фоновом режиме Docker!{COLOR_RESET}")
        else:
            print(f"\n{COLOR_FAIL}[✕] Не удалось запустить сервер через Docker Compose.{COLOR_RESET}")
            print(f"{COLOR_WARN}Вы можете попробовать запустить его вручную, перейдя в папку 'server' и выполнив: {COLOR_BOLD}{' '.join(compose_cmd)} up{COLOR_RESET}")
    except Exception as e:
        print(f"\n{COLOR_FAIL}[✕] Ошибка при запуске команды Docker: {e}{COLOR_RESET}")

    # Create desktop shortcuts for starting and stopping in the future
    try:
        create_desktop_shortcuts(compose_cmd, server_dir)
    except Exception as e:
        print(f"{COLOR_WARN}[!] Ошибка создания ярлыков на Рабочем столе: {e}{COLOR_RESET}")

    local_ip = get_local_ip()
    
    print(f"\n{COLOR_TITLE}{COLOR_BOLD}=============================================================")
    print(f"                 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                ")
    print(f"============================================================={COLOR_RESET}")
    print(f"\n{COLOR_BOLD}📍 IP-адрес для подключения игроков в локальной сети:{COLOR_RESET}")
    print(f"   {COLOR_SUCCESS}{COLOR_BOLD}{local_ip}:{server_port}{COLOR_RESET}")
    
    if vr_enabled:
        client_mods_abs = os.path.join(base_dir, "client_mods")
        print(f"\n{COLOR_BOLD}🎮 Инструкция для VR-игроков (клиент):{COLOR_RESET}")
        print(f"   1. Скачанные моды для вашего клиента находятся в папке:")
        print(f"      {COLOR_INFO}{client_mods_abs}{COLOR_RESET}")
        print(f"   2. Скопируйте ВСЕ файлы из этой папки в ваш каталог {COLOR_BOLD}.minecraft/mods{COLOR_RESET}")
        print(f"      (на ПК в Prism Launcher, CurseForge или официальном лаунчере с установленным {loader_type.capitalize()})")
        print(f"   3. Для игры в VR убедитесь, что вы запускаете игру через VR-шлем (SteamVR / Link / Virtual Desktop)!")
        if voice_enabled:
            print(f"   4. Голосовой чат (Simple Voice Chat) автоматически настроен. В игре нажмите клавишу {COLOR_BOLD}'V'{COLOR_RESET} для настроек микрофона.")
            
    print(f"\n{COLOR_BOLD}🔧 Управление сервером:{COLOR_RESET}")
    print(f"   - Остановить сервер: перейти в папку {COLOR_INFO}server/{COLOR_RESET} и ввести: {COLOR_BOLD}{' '.join(compose_cmd)} down{COLOR_RESET}")
    print(f"   - Посмотреть логи сервера: {COLOR_BOLD}{' '.join(compose_cmd)} logs -f minecraft-server{COLOR_RESET}")
    print(f"\n{COLOR_SUCCESS}Приятной игры в виртуальной реальности! 🚀{COLOR_RESET}\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{COLOR_FAIL}Установка прервана пользователем.{COLOR_RESET}")
        sys.exit(1)
