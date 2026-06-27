import os
import json
import urllib.request
import urllib.parse

# Setup directories
BASE_DIR = "/mnt/Lyes/vibecode/Minecraft"
CLIENT_MODS_DIR = os.path.join(BASE_DIR, "mods")
CLIENT_RP_DIR = os.path.join(BASE_DIR, "resourcepacks")
SERVER_MODS_DIR = os.path.join(BASE_DIR, "Server/data/mods")

os.makedirs(CLIENT_MODS_DIR, exist_ok=True)
os.makedirs(CLIENT_RP_DIR, exist_ok=True)
os.makedirs(SERVER_MODS_DIR, exist_ok=True)

HEADERS = {
    'User-Agent': 'sazan/minecraft-modpack-downloader/1.0 (sazan@sazanuwu.vip)'
}

COMMON_MODS = [
    "ad-astra",
    "resourceful-lib",
    "botarium",
    "resourceful-config",
    "blue-skies",
    "structure-gel-api",
    "the-twilight-forest",
    "aether",
    "cumulus",
    "biomes-o-plenty",
    "glitchcore",
    "stellarity",
    "deeperdarker",
    "geckolib",
    "cloth-config",
    "ct-overhaul-village",
    "towns-and-towers",
    "explorify",
    "yungs-api",
    "yungs-better-nether-fortresses",
    "yungs-better-ocean-monuments",
    "yungs-better-dungeons",
    "yungs-better-jungle-temples",
    "yungs-better-mineshafts",
    "yungs-better-end-island",
    "yungs-better-strongholds",
    "yungs-better-witch-huts",
    "yungs-better-desert-temples",
    "fallingtree",
    "ore-creeper",
    "alexs-mobs",
    "citadel",
    "mythic-mounts",
    "patchouli",
    "terrablender",
    "lithostitched",
    "cristel-lib",
    "journeymap",
    "waystones",
    "balm",
    "gravestone-mod",
    "simple-voice-chat"
]

CLIENT_ONLY_MODS = [
    "jei",
    "appleskin",
    "embeddium",
    "oculus",
    "journeymap-integration",
    "not-enough-animations",
    "3dskinlayers",
    "eating-animations",
    "first-person-model",
    "ryoamiclights",
    "gml",
    "obsidianui"
]

def fetch_version_info(slug, is_resourcepack=False):
    loader = "minecraft" if is_resourcepack else "forge"
    params = {
        'loaders': json.dumps([loader]),
        'game_versions': json.dumps(['1.20.1'])
    }
    query = urllib.parse.urlencode(params)
    url = f"https://api.modrinth.com/v2/project/{slug}/version?{query}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            if not data:
                # Try search without loader restriction if none found
                params_any = {
                    'game_versions': json.dumps(['1.20.1'])
                }
                query_any = urllib.parse.urlencode(params_any)
                url_any = f"https://api.modrinth.com/v2/project/{slug}/version?{query_any}"
                req_any = urllib.request.Request(url_any, headers=HEADERS)
                with urllib.request.urlopen(req_any) as resp_any:
                    data = json.loads(resp_any.read().decode())
            return data
    except Exception as e:
        print(f"Error fetching version for {slug}: {e}")
        return None

def download_file(url, dest_paths):
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as response:
            content = response.read()
            for dest_path in dest_paths:
                with open(dest_path, "wb") as f:
                    f.write(content)
        return True
    except Exception as e:
        print(f"Error downloading {url}: {e}")
        return False

def process_mod(slug, is_client_only):
    print(f"Processing mod: {slug}...")
    if slug == "the-twilight-forest":
        download_url = "https://minecraft-inside.ru/uploads/files/2024-06/twilightforest-1.20.1-4.3.2508-universal.jar"
        filename = "twilightforest-1.20.1-4.3.2508-universal.jar"
        destinations = [os.path.join(CLIENT_MODS_DIR, filename)]
        if not is_client_only:
            destinations.append(os.path.join(SERVER_MODS_DIR, filename))
        if all(os.path.exists(d) for d in destinations):
            print(f"Mod {slug} ({filename}) already exists. Skipping download.")
            return True
        print(f"Downloading {filename} directly...")
        success = download_file(download_url, destinations)
        if success:
            print(f"Successfully saved {slug} to {[os.path.basename(d) for d in destinations]}")
        return success

    versions = fetch_version_info(slug)
    if not versions:
        print(f"Failed to find versions for {slug}")
        return False
    
    # Try to find a release
    selected_ver = None
    for ver in versions:
        if ver.get("version_type") == "release":
            selected_ver = ver
            break
    if not selected_ver:
        if versions:
            selected_ver = versions[0]
        else:
            print(f"No versions found at all for {slug}")
            return False
        
    files = selected_ver.get("files", [])
    if not files:
        print(f"No files found for {slug} in version {selected_ver.get('version_number')}")
        return False
        
    primary_file = None
    for f in files:
        if f.get("primary"):
            primary_file = f
            break
    if not primary_file:
        primary_file = files[0]
        
    download_url = primary_file.get("url")
    filename = primary_file.get("filename")
    
    # Target destinations
    destinations = []
    client_dest = os.path.join(CLIENT_MODS_DIR, filename)
    destinations.append(client_dest)
    
    if not is_client_only:
        server_dest = os.path.join(SERVER_MODS_DIR, filename)
        destinations.append(server_dest)
        
    if all(os.path.exists(d) for d in destinations):
        print(f"Mod {slug} ({filename}) already exists. Skipping download.")
        return True
        
    print(f"Downloading {filename}...")
    success = download_file(download_url, destinations)
    if success:
        print(f"Successfully saved {slug} to {[os.path.basename(d) for d in destinations]}")
    return success

def process_resourcepack():
    slug = "faithful-64x"
    print(f"Processing resourcepack: {slug}...")
    versions = fetch_version_info(slug, is_resourcepack=True)
    if not versions:
        print(f"Failed to find versions for {slug}")
        return False
        
    selected_ver = None
    for ver in versions:
        if ver.get("version_type") == "release":
            selected_ver = ver
            break
    if not selected_ver:
        if versions:
            selected_ver = versions[0]
        else:
            print(f"No versions found for {slug}")
            return False
        
    files = selected_ver.get("files", [])
    if not files:
        print(f"No files found for {slug}")
        return False
        
    primary_file = None
    for f in files:
        if f.get("primary"):
            primary_file = f
            break
    if not primary_file:
        primary_file = files[0]
        
    download_url = primary_file.get("url")
    filename = primary_file.get("filename")
    
    dest_path = os.path.join(CLIENT_RP_DIR, filename)
    if os.path.exists(dest_path):
        print(f"Resourcepack {slug} ({filename}) already exists. Skipping download.")
        return True
    print(f"Downloading {filename}...")
    success = download_file(download_url, [dest_path])
    if success:
        print(f"Successfully saved resourcepack to {filename}")
    return success

if __name__ == "__main__":
    print("Starting download of all mods for client and server...")
    failed = []
    
    for slug in COMMON_MODS:
        if not process_mod(slug, is_client_only=False):
            failed.append((slug, "common"))
            
    for slug in CLIENT_ONLY_MODS:
        if not process_mod(slug, is_client_only=True):
            failed.append((slug, "client-only"))
            
    if not process_resourcepack():
        failed.append(("faithful-64x", "resourcepack"))
        
    print("\n--- Summary ---")
    if failed:
        print("Failed to download:")
        for item, category in failed:
            print(f"- {item} ({category})")
    else:
        print("All downloads completed successfully!")
