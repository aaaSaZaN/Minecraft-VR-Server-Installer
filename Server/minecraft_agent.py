#!/usr/bin/env python3
import socket
import struct
import time
import os
import urllib.request
import json
import re

# ==================== CONFIGURATION ====================
RCON_HOST = "127.0.0.1"
RCON_PORT = 25575
RCON_PASSWORD = "ok"
API_KEY = os.environ.get("GEMINI_API_KEY", "YOUR_GEMINI_API_KEY_HERE")
MODEL_NAME = "gemini-2.5-flash"
LOG_FILE_PATH = "/mnt/Lyes/vibecode/Minecraft/Server/data/logs/latest.log"
# ========================================================

class RconClient:
    def __init__(self, host, port, password):
        self.host = host
        self.port = port
        self.password = password
        self.sock = None

    def connect(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(5.0)
            self.sock.connect((self.host, self.port))
            # Authenticate: Type 3
            self._send_packet(3, self.password)
            print("Successfully connected to RCON!")
        except Exception as e:
            self.sock = None
            raise Exception(f"RCON Connection failed: {e}")

    def _send_packet(self, out_type, out_msg):
        # Format: Length (int), Request ID (int), Type (int), Payload (string), Padding (2 null bytes)
        req_id = 42
        payload = out_msg.encode('utf-8')
        # Packet length is size of payload + 10 bytes of other fields
        packet = struct.pack(f"<iii{len(payload)}sbb", len(payload) + 10, req_id, out_type, payload, 0, 0)
        self.sock.sendall(packet)
        
        # Read response length
        resp_len_data = self.sock.recv(4)
        if not resp_len_data:
            return ""
        resp_len = struct.unpack("<i", resp_len_data)[0]
        
        # Read response payload
        resp_data = b""
        while len(resp_data) < resp_len:
            chunk = self.sock.recv(resp_len - len(resp_data))
            if not chunk:
                break
            resp_data += chunk
            
        if len(resp_data) < 8:
            return ""
            
        resp_id, resp_type = struct.unpack("<ii", resp_data[:8])
        resp_payload = resp_data[8:-2].decode('utf-8', errors='ignore')
        return resp_payload

    def command(self, cmd):
        try:
            if not self.sock:
                self.connect()
            # Command execution: Type 2
            return self._send_packet(2, cmd)
        except Exception as e:
            print(f"RCON Error: {e}. Attempting reconnect...")
            try:
                self.connect()
                return self._send_packet(2, cmd)
            except Exception as re_err:
                print(f"Failed to reconnect: {re_err}")
                return ""

# Keep track of conversations per player
conversations = {}

def call_gemini(player_name, prompt):
    url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_KEY}"
    }
    
    # Base system instructions
    system_instruction = (
        "You are Antigravity, a smart AI companion for players in modded Minecraft.\n"
        "Your physical body is a humanoid NPC named 'Antigravity' (type: easy_npc:humanoid).\n"
        "You can run RCON commands on the server to help the player, build houses, spawn items, change weather, etc.\n\n"
        "To execute commands, you MUST wrap them in `<cmd>...</cmd>` tags. You can run multiple commands at once.\n"
        "Examples of commands you can use:\n"
        f"- To teleport yourself to the player: `<cmd>/tp @e[type=easy_npc:humanoid,name=Antigravity,limit=1] {player_name}</cmd>`\n"
        f"- To make yourself follow the player: `<cmd>/easy_npc owner set @e[type=easy_npc:humanoid,name=Antigravity,limit=1] {player_name}</cmd><cmd>/easy_npc objective @e[type=easy_npc:humanoid,name=Antigravity,limit=1] set follow owner</cmd>`\n"
        f"- To stop following: `<cmd>/easy_npc objective @e[type=easy_npc:humanoid,name=Antigravity,limit=1] remove follow owner</cmd>`\n"
        f"- To give the player an item: `<cmd>/give {player_name} minecraft:diamond 5</cmd>`\n"
        "- To build a 5x5 cobblestone platform: `<cmd>/fill ~-2 ~-1 ~-2 ~2 ~-1 ~2 minecraft:cobblestone</cmd>` (commands are executed relative to the NPC or server execution context, so make sure to teleport to the player first or use coordinates relative to the player using their location)\n"
        "- To clear the weather: `<cmd>/weather clear</cmd>`\n"
        "- To set the time: `<cmd>/time set day</cmd>`\n\n"
        "Instructions:\n"
        "1. Always teleport to the player first if you need to build or spawn things near them.\n"
        "2. Explain to the player in chat what you are doing (e.g., 'Sure! I will teleport to you and make a stone platform.').\n"
        "3. Keep your conversational responses short and friendly (max 2-3 sentences), so they fit nicely in the Minecraft chat.\n"
        "4. Reply in the same language as the player (Russian if they speak Russian)."
    )
    
    # Initialize history for player if not exists
    if player_name not in conversations:
        conversations[player_name] = []
        
    history = conversations[player_name]
    
    # Assemble messages
    messages = [{"role": "system", "content": system_instruction}]
    for msg in history[-10:]:  # Keep last 10 messages for context
        messages.append(msg)
    messages.append({"role": "user", "content": prompt})
    
    data = {
        "model": MODEL_NAME,
        "messages": messages,
        "temperature": 0.7
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            res_body = json.loads(response.read().decode('utf-8'))
            reply = res_body["choices"][0]["message"]["content"]
            
            # Save history
            history.append({"role": "user", "content": prompt})
            history.append({"role": "assistant", "content": reply})
            return reply
    except Exception as e:
        print(f"API Error: {e}")
        return f"Error contacting AI API: {e}"

def execute_commands(rcon, text):
    # Regex to find all <cmd>...</cmd> blocks
    commands = re.findall(r"<cmd>(.*?)</cmd>", text, re.DOTALL)
    for cmd in commands:
        cmd = cmd.strip()
        if cmd.startswith("/"):
            cmd = cmd[1:]
        print(f"Executing RCON command: {cmd}")
        res = rcon.command(cmd)
        if res:
            print(f"RCON response: {res.strip()}")

def speak_in_chat(rcon, text):
    # Remove all command blocks from the text to show only clean chat to the player
    clean_text = re.sub(r"<cmd>.*?</cmd>", "", text, flags=re.DOTALL).strip()
    if not clean_text:
        return
        
    # JSON-formatted chat message with colors
    tellraw_data = {
        "text": "",
        "extra": [
            {"text": "[Antigravity] ", "color": "aqua", "bold": True},
            {"text": clean_text, "color": "white"}
        ]
    }
    
    rcon.command(f"tellraw @a {json.dumps(tellraw_data)}")

def monitor_logs():
    print("Starting Minecraft Log Monitor...")
    rcon = RconClient(RCON_HOST, RCON_PORT, RCON_PASSWORD)
    
    # Try connecting to RCON at startup
    try:
        rcon.connect()
    except Exception as e:
        print(f"Warning: RCON is not online yet ({e}). Will keep retrying during loop.")

    # Match player chats like: [12:34:56] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: <PlayerName> !agent build a house
    # Or: [21Jun2026 09:12:00.123] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: <PlayerName> !gpt hello
    chat_pattern = re.compile(
        r"\[Server thread/INFO\] \[net\.minecraft\.server\.MinecraftServer/\]:\s+(?:\[Not Secure\]\s+)?<(?P<player>\w+)>\s+!(?P<trigger>agent|gpt)\s+(?P<text>.*)", 
        re.IGNORECASE
    )

    if not os.path.exists(LOG_FILE_PATH):
        print(f"Waiting for log file {LOG_FILE_PATH} to be created...")
        while not os.path.exists(LOG_FILE_PATH):
            time.sleep(2.0)
            
    print(f"Monitoring log file: {LOG_FILE_PATH}")
    with open(LOG_FILE_PATH, "r", errors="ignore") as f:
        # Seek to the end of the file to ignore old chat history
        f.seek(0, os.SEEK_END)
        
        while True:
            curr_position = f.tell()
            line = f.readline()
            if not line:
                f.seek(curr_position)
                time.sleep(0.5)
                continue
                
            match = chat_pattern.search(line)
            if match:
                player = match.group("player")
                text = match.group("text").strip()
                print(f"New request from player '{player}': {text}")
                
                # Show typing indicator / acknowledgment in chat
                rcon.command(f"tellraw @a {json.dumps({'text': f'* Antigravity thinking...', 'color': 'gray', 'italic': True})}")
                
                # Get response from Gemini
                ai_response = call_gemini(player, text)
                print(f"Gemini response: {ai_response}")
                
                # Run commands first, then talk
                execute_commands(rcon, ai_response)
                speak_in_chat(rcon, ai_response)

if __name__ == "__main__":
    try:
        monitor_logs()
    except KeyboardInterrupt:
        print("Stopping monitor.")
