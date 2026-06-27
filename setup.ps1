# --- Enable ANSI/VT100 on Windows (PowerShell 5.1 compatibility) ---
try {
    Add-Type -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
"@ -Name 'Kernel32' -Namespace 'Win32' -ErrorAction SilentlyContinue
    $stdOut = [Win32.Kernel32]::GetStdHandle(-11)
    $mode   = 0
    [Win32.Kernel32]::GetConsoleMode($stdOut, [ref]$mode) | Out-Null
    [Win32.Kernel32]::SetConsoleMode($stdOut, $mode -bor 4) | Out-Null
} catch {}

# --- ANSI Colors for Premium CLI Look ---
$ESC           = [char]27
$COLOR_TITLE   = "$ESC[95m"  # Purple
$COLOR_INFO    = "$ESC[94m"  # Blue
$COLOR_SUCCESS = "$ESC[92m"  # Green
$COLOR_WARN    = "$ESC[93m"  # Yellow
$COLOR_FAIL    = "$ESC[91m"  # Red
$COLOR_BOLD    = "$ESC[1m"
$COLOR_RESET   = "$ESC[0m"

# Ensure output encoding is UTF-8 for Russian text support
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Banner {
    $banner = @"
$COLOR_TITLE$COLOR_BOLD=============================================================
    __  ___ _                                 __ _      ____ 
   /  |/  /(_)____   ___   _____  _____ ____ _/ //_/     / __ \
  / /|_/ // // __ \ / _ \ / ___/ / ___// __ ``/ __/ /| /| / /_/ /
 / /  / // // / / //  __// /__  / /   / /_/ / /_  / |/ |/ /_, _/ 
/_/  /_//_//_/ /_/ \___/ \___/ /_/    \__,_/\__/  /__/|__/_/ |_|  
                                                             
               VR SERVER & CLIENT AUTO-INSTALLER (PowerShell)
=============================================================$COLOR_RESET
"@
    Write-Host $banner
}

function Get-Input ($prompt, $defaultValue) {
    $promptStr = "$COLOR_BOLD$prompt$COLOR_RESET"
    if ($null -ne $defaultValue) {
        $promptStr += " [$COLOR_INFO$defaultValue$COLOR_RESET]: "
    } else {
        $promptStr += ": "
    }
    Write-Host -NoNewline $promptStr
    $val = Read-Host
    if ([string]::IsNullOrWhiteSpace($val)) {
        return $defaultValue
    }
    return $val.Trim()
}

function Check-Docker {
    Write-Host "`n$COLOR_INFO[*] Проверка Docker...$COLOR_RESET"

    # Check docker command
    try {
        $res = Get-Command docker -ErrorAction SilentlyContinue
        if ($null -eq $res) {
            return [PSCustomObject]@{ Cmd = $null; Err = "Docker не установлен." }
        }
        $dockerVer = & docker --version
        Write-Host "$COLOR_SUCCESS[✓] Найден Docker: $($dockerVer.Trim())$COLOR_RESET"
    } catch {
        return [PSCustomObject]@{ Cmd = $null; Err = "Ошибка при вызове Docker." }
    }

    # Check docker compose support
    $composeCmd = $null
    try {
        & docker compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $composeCmd = @("docker", "compose")
            Write-Host "$COLOR_SUCCESS[✓] Найден встроенный Docker Compose$COLOR_RESET"
        }
    } catch {}

    if ($null -eq $composeCmd) {
        try {
            & docker-compose --version 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $composeCmd = @("docker-compose")
                Write-Host "$COLOR_SUCCESS[✓] Найден классический docker-compose$COLOR_RESET"
            }
        } catch {}
    }

    if ($null -eq $composeCmd) {
        return [PSCustomObject]@{ Cmd = $null; Err = "Docker Compose не найден. Пожалуйста, установите Docker Compose." }
    }

    return [PSCustomObject]@{ Cmd = $composeCmd; Err = $null }
}

# Helper: надёжный запуск docker / docker-compose с любым числом аргументов
function Invoke-Compose ($composeCmd, $arguments, $workingDir) {
    $extraArgs = if ($composeCmd.Count -gt 1) { $composeCmd[1..($composeCmd.Count - 1)] } else { @() }
    $allArgs   = (@($extraArgs) + @($arguments)) | Where-Object { $null -ne $_ }
    Push-Location $workingDir
    try {
        & $composeCmd[0] @allArgs
    } finally {
        Pop-Location
    }
}

function Install-Docker {
    Write-Host "`n$COLOR_WARN[!] Docker не найден в вашей системе!$COLOR_RESET"
    Write-Host "${COLOR_INFO}Мы можем попробовать установить Docker Desktop через Windows Winget (требуются права администратора).$COLOR_RESET"
    
    $ans = Get-Input "Запустить установку Docker Desktop? (y/n)" "y"
    if ($ans.ToLower() -eq 'y') {
        Write-Host "$COLOR_INFO[*] Запуск winget install Docker.DockerDesktop...$COLOR_RESET"
        try {
            Start-Process winget -ArgumentList "install", "Docker.DockerDesktop", "--accept-source-agreements", "--accept-package-agreements" -NoNewWindow -Wait
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$COLOR_SUCCESS[✓] Установка завершена! Требуется ПЕРЕЗАГРУЗИТЬ компьютер, чтобы Docker заработал.$COLOR_RESET"
                return $true
            } else {
                Write-Host "$COLOR_FAIL[✕] Ошибка при установке через Winget.$COLOR_RESET"
            }
        } catch {
            Write-Host "$COLOR_FAIL[✕] Утилита 'winget' не найдена в системе.$COLOR_RESET"
        }
    }
    Write-Host "${COLOR_WARN}Пожалуйста, установите Docker Desktop вручную с официального сайта:$COLOR_RESET"
    Write-Host "${COLOR_BOLD}https://www.docker.com/products/docker-desktop/$COLOR_RESET"
    return $false
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
            $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" 
        } | Select-Object -First 1).IPAddress
        if ($null -eq $ip) { $ip = "127.0.0.1" }
        return $ip
    } catch {
        return "127.0.0.1"
    }
}

function Fetch-ModrinthVersion ($slug, $mcVersion, $loader) {
    $url = "https://api.modrinth.com/v2/project/$slug/version"
    $headers = @{ "User-Agent" = "antigravity/minecraft-vr-installer/1.0" }
    
    try {
        $versions = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        $matching = @()
        
        foreach ($v in $versions) {
            # Check game version
            if ($v.game_versions -notcontains $mcVersion) { continue }
            
            # Check loader
            $loaders = $v.loaders
            if ($loaders -notcontains $loader -and $loaders -notcontains "minecraft") { continue }
            
            $matching += $v
        }
        
        if ($matching.Count -eq 0) { return $null }
        
        # Prefer release
        foreach ($v in $matching) {
            if ($v.version_type -eq "release") { return $v }
        }
        return $matching[0]
    } catch {
        Write-Host "  $COLOR_FAIL[✕] Ошибка запроса к Modrinth для ${slug}: $_$COLOR_RESET"
        return $null
    }
}

function Download-File ($url, $destPath) {
    try {
        # Using .NET WebClient for clean download
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "antigravity/minecraft-vr-installer/1.0")
        
        Write-Host -NoNewline "  Скачивание файла... "
        $webClient.DownloadFile($url, $destPath)
        Write-Host "$COLOR_SUCCESS готово.$COLOR_RESET"
        return $true
    } catch {
        Write-Host "`n  $COLOR_FAIL[✕] Ошибка скачивания ${url}: $_$COLOR_RESET"
        return $false
    }
}

function Handle-Mods ($mcVersion, $loader, $voiceEnabled, $serverModsDir, $clientModsDir) {
    Write-Host "`n$COLOR_INFO[*] Поиск и скачивание модов с Modrinth для версии $mcVersion ($loader)...$COLOR_RESET"
    
    $modList = @(
        [PSCustomObject]@{ Slug = "vivecraft"; Name = "Vivecraft (VR мод)"; Server = $true; Client = $true }
    )
    
    if ($loader.ToLower() -eq 'fabric') {
        $modList += [PSCustomObject]@{ Slug = "fabric-api"; Name = "Fabric API (Библиотека)"; Server = $true; Client = $true }
        $modList += [PSCustomObject]@{ Slug = "sodium"; Name = "Sodium (Оптимизация рендера)"; Server = $false; Client = $true }
        $modList += [PSCustomObject]@{ Slug = "iris"; Name = "Iris Shaders (Поддержка шейдеров)"; Server = $false; Client = $true }
    } else {
        $modList += [PSCustomObject]@{ Slug = "embeddium"; Name = "Embeddium (Sodium для Forge)"; Server = $false; Client = $true }
        $modList += [PSCustomObject]@{ Slug = "oculus"; Name = "Oculus (Iris для Forge)"; Server = $false; Client = $true }
    }
    
    if ($voiceEnabled) {
        $modList += [PSCustomObject]@{ Slug = "simple-voice-chat"; Name = "Simple Voice Chat (Голосовой чат)"; Server = $true; Client = $true }
    }

    foreach ($m in $modList) {
        Write-Host "`n${COLOR_BOLD}Обработка $($m.Name)...$COLOR_RESET"
        
        $vInfo = Fetch-ModrinthVersion $m.Slug $mcVersion $loader
        if ($null -eq $vInfo) {
            Write-Host "  $COLOR_WARN[!] Подходящая версия для $($m.Slug) не найдена. Пропустите или скачайте вручную.$COLOR_RESET"
            continue
        }
        
        $fileObj = $null
        foreach ($f in $vInfo.files) {
            if ($f.primary) {
                $fileObj = $f
                break
            }
        }
        if ($null -eq $fileObj) { $fileObj = $vInfo.files[0] }
        
        $downloadUrl = $fileObj.url
        $filename = $fileObj.filename
        
        $dests = @()
        if ($m.Server) { $dests += @([PSCustomObject]@{ Path = Join-Path $serverModsDir $filename; Label = "на сервер" }) }
        if ($m.Client) { $dests += @([PSCustomObject]@{ Path = Join-Path $clientModsDir $filename; Label = "на клиент" }) }
        
        foreach ($d in $dests) {
            if (Test-Path $d.Path) {
                Write-Host "  [✓] Файл $filename уже скачан ($($d.Label)). Пропуск."
                continue
            }
            Write-Host "  Скачивание $filename ($($d.Label))..."
            $success = Download-File $downloadUrl $d.Path
            if ($success) {
                Write-Host "  $COLOR_SUCCESS[✓] Скачано успешно ($($d.Label))$COLOR_RESET"
            }
        }
    }
}

function Handle-ExistingInstall ($composeCmd, $serverDir) {
    $composePath = Join-Path $serverDir "docker-compose.yml"
    if (-not (Test-Path $composePath)) { return $false }
    
    Write-Host "`n$COLOR_WARN[!] Обнаружена существующая установка сервера в папке $serverDir$COLOR_RESET"
    Write-Host "Выберите действие:"
    Write-Host "1) ${COLOR_SUCCESS}Запустить сервер$COLOR_RESET"
    Write-Host "2) ${COLOR_FAIL}Остановить сервер$COLOR_RESET"
    Write-Host "3) ${COLOR_INFO}Посмотреть логи сервера$COLOR_RESET"
    Write-Host "4) ${COLOR_TITLE}Перенастроить сервер (свежая установка)$COLOR_RESET"
    
    $choice = Get-Input "Введите вариант (1-4)" "1"
    if ($choice -eq "1") {
        Write-Host "`n$COLOR_INFO[*] Запуск сервера...$COLOR_RESET"
        Invoke-Compose $composeCmd @("up", "-d") $serverDir
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$COLOR_SUCCESS[✓] Сервер успешно запущен в фоновом режиме.$COLOR_RESET"
            $localIp = Get-LocalIP
            
            # Find port in docker-compose.yml
            $port = "25565"
            try {
                $content = Get-Content $composePath -Raw
                if ($content -match '"(\d+):25565"') {
                    $port = $Matches[1]
                }
            } catch {}
            
            Write-Host "`n📍 IP-адрес для подключения игроков в локальной сети:"
            Write-Host "   $COLOR_SUCCESS$COLOR_BOLD${localIp}:$port$COLOR_RESET"
        } else {
            Write-Host "$COLOR_FAIL[✕] Не удалось запустить сервер.$COLOR_RESET"
        }
        return $true
    } elseif ($choice -eq "2") {
        Write-Host "`n$COLOR_INFO[*] Остановка сервера...$COLOR_RESET"
        Invoke-Compose $composeCmd @("down") $serverDir
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$COLOR_SUCCESS[✓] Сервер успешно остановлен.$COLOR_RESET"
        } else {
            Write-Host "$COLOR_FAIL[✕] Не удалось остановить сервер.$COLOR_RESET"
        }
        return $true
    } elseif ($choice -eq "3") {
        Write-Host "`n$COLOR_INFO[*] Загрузка логов (нажмите Ctrl+C для выхода)...$COLOR_RESET"
        try {
            Invoke-Compose $composeCmd @("logs", "-f", "minecraft-server") $serverDir
        } catch {
            Write-Host "`n Выход из просмотра логов."
        }
        return $true
    } elseif ($choice -eq "4") {
        Write-Host "`n$COLOR_INFO[*] Начинаем перенастройку...$COLOR_RESET"
        return $false
    }
    return $false
}

function Create-DesktopShortcuts ($composeCmd, $serverDir) {
    $desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop))
    if (-not (Test-Path $desktopPath)) {
        $desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    }
    
    Write-Host "`n$COLOR_INFO[*] Создание ярлыков для удобного управления на Рабочем столе...$COLOR_RESET"
    
    $startBat = Join-Path $desktopPath "Minecraft_VR_Server_START.bat"
    $stopBat = Join-Path $desktopPath "Minecraft_VR_Server_STOP.bat"
    
    $cmdPrefix = $composeCmd -join " "
    
    # Write files with UTF-8
    $startContent = "@echo off`r`nchcp 65001 > nul`r`ncd /d `"$serverDir`"`r`n$cmdPrefix up -d`r`necho [✓] Minecraft VR Server started!`r`npause`r`n"
    $stopContent = "@echo off`r`nchcp 65001 > nul`r`ncd /d `"$serverDir`"`r`n$cmdPrefix down`r`necho [✓] Minecraft VR Server stopped!`r`npause`r`n"
    
    [System.IO.File]::WriteAllText($startBat, $startContent, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($stopBat, $stopContent, [System.Text.Encoding]::UTF8)
    
    Write-Host "$COLOR_SUCCESS[✓] Созданы файлы управления на Рабочем столе:$COLOR_RESET"
    Write-Host "    - Запуск: $startBat"
    Write-Host "    - Остановка: $stopBat"
}

# --- MAIN FLOW ---
Show-Banner

$res = Check-Docker
$composeCmd = $res.Cmd
$err = $res.Err

if ($null -eq $composeCmd) {
    Write-Host "$COLOR_FAIL[✕] Проверка Docker провалена: $err$COLOR_RESET"
    $success = Install-Docker
    if (-not $success) {
        Write-Host "`n${COLOR_FAIL}Пожалуйста, настройте Docker и запустите скрипт заново.$COLOR_RESET"
        Exit 1
    }
    # Check again
    $res = Check-Docker
    $composeCmd = $res.Cmd
    if ($null -eq $composeCmd) {
        Write-Host "$COLOR_FAILDocker был установлен, но всё ещё не обнаруживается в текущей сессии консоли.$COLOR_RESET"
        Write-Host "$COLOR_WARNПерезапустите консоль/компьютер и запустите скрипт заново.$COLOR_RESET"
        Exit 1
    }
}

$defaultInstallDir = Get-Location
if ($defaultInstallDir.Path -like "*\System32*" -or $defaultInstallDir.Path -like "*\system32*" -or $defaultInstallDir.Path -eq "C:\Windows" -or $defaultInstallDir.Path -eq "C:\WINDOWS") {
    $defaultInstallDir = "C:\Minecraft-VR-Server"
} else {
    $defaultInstallDir = Join-Path $defaultInstallDir.Path "Minecraft-VR-Server"
}

Write-Host "`n${COLOR_BOLD}=== ВЫБОР ПАПКИ УСТАНОВКИ ===$COLOR_RESET"
$targetDirInput = Get-Input "Введите путь для установки сервера" $defaultInstallDir

# Create and set target directory
$baseDir = [System.IO.Path]::GetFullPath($targetDirInput)
$null = New-Item -ItemType Directory -Force -Path $baseDir
Set-Location $baseDir
Write-Host "${COLOR_SUCCESS}[✓] Папка установки установлена в: $baseDir$COLOR_RESET"

$serverDir = Join-Path $baseDir "server"

if (Handle-ExistingInstall $composeCmd $serverDir) {
    Exit 0
}

Write-Host "`n$COLOR_BOLD=== НАСТРОЙКА MINECRAFT СЕРВЕРА ===$COLOR_RESET`n"

$mcVersion = Get-Input "Введите версию Minecraft" "1.20.1"

Write-Host "`nВыберите ядро (мод-лоадер):"
Write-Host "1) ${COLOR_INFO}Forge$COLOR_RESET (Стандартное ядро для QuestCraft)"
Write-Host "2) ${COLOR_INFO}Fabric$COLOR_RESET"
Write-Host "3) ${COLOR_INFO}NeoForge$COLOR_RESET"
$loaderChoice = Get-Input "Выберите вариант (1-3)" "1"

$loaderType = "forge"
if ($loaderChoice -eq "2") { $loaderType = "fabric" }
if ($loaderChoice -eq "3") { $loaderType = "neoforge" }

$ramGb = Get-Input "Сколько ГБ оперативной памяти выделить серверу" "4"
if (-not $ramGb.EndsWith("G") -and -not $ramGb.EndsWith("M")) {
    $ramGb = "$($ramGb)G"
}

$onlineInput = Get-Input "Разрешить вход без лицензии (пиратский режим)? (y/n)" "y"
$onlineMode = "TRUE"
if ($onlineInput.ToLower() -eq 'y') { $onlineMode = "FALSE" }

$serverPort = Get-Input "Основной порт сервера" "25565"

$voiceChatInput = Get-Input "Установить 3D Голосовой чат (Simple Voice Chat)? (y/n)" "y"
$voiceEnabled = $voiceChatInput.ToLower() -eq 'y'

$vrModsInput = Get-Input "Скачать VR моды (Vivecraft, Iris, Sodium и др.)? (y/n)" "y"
$vrEnabled = $vrModsInput.ToLower() -eq 'y'

# Create server directory
$serverDir = Join-Path $baseDir "server"
$null = New-Item -ItemType Directory -Force -Path $serverDir

Write-Host "`n$COLOR_INFO[*] Генерация docker-compose.yml...$COLOR_RESET"
$voicePort = "24454"

$composeLines = @(
    "services:",
    "  minecraft-server:",
    "    image: itzg/minecraft-server:latest",
    "    container_name: mc-vr-server",
    "    ports:",
    "      - `"$serverPort:25565`""
)

if ($voiceEnabled) {
    $composeLines += "      - `"${voicePort}:$voicePort/udp`""
}

$composeLines += @(
    "    environment:",
    "      EULA: `"TRUE`"",
    "      VERSION: `"$mcVersion`"",
    "      TYPE: `"$($loaderType.ToUpper())`"",
    "      MEMORY: `"$ramGb`"",
    "      ONLINE_MODE: `"$onlineMode`"",
    "      ENABLE_RCON: `"true`"",
    "      RCON_PASSWORD: `"minecraft_rcon_pass`"",
    "    volumes:",
    "      - ./data:/data",
    "    restart: unless-stopped"
)

$composeContent = $composeLines -join "`n"
$composePath = Join-Path $serverDir "docker-compose.yml"
[System.IO.File]::WriteAllText($composePath, $composeContent, [System.Text.Encoding]::UTF8)

Write-Host "$COLOR_SUCCESS[✓] docker-compose.yml создан в $composePath$COLOR_RESET"

$serverModsDir = Join-Path $serverDir "data"
$serverModsDir = Join-Path $serverModsDir "mods"
$clientModsDir = Join-Path $baseDir "client_mods"

if ($vrEnabled) {
    $null = New-Item -ItemType Directory -Force -Path $serverModsDir
    $null = New-Item -ItemType Directory -Force -Path $clientModsDir
    Handle-Mods $mcVersion $loaderType $voiceEnabled $serverModsDir $clientModsDir
}

Write-Host "`n$COLOR_INFO[*] Запуск Docker контейнера с сервером Майнкрафт...$COLOR_RESET"
Write-Host "$COLOR_INFO    (Это может занять некоторое время при первом запуске, скачивается образ)$COLOR_RESET"

Invoke-Compose $composeCmd @("up", "-d") $serverDir

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n$COLOR_SUCCESS[✓] Сервер Майнкрафт успешно запущен в фоновом режиме Docker!$COLOR_RESET"
} else {
    Write-Host "`n$COLOR_FAIL[✕] Не удалось запустить сервер через Docker Compose.$COLOR_RESET"
    Write-Host "${COLOR_WARN}Вы можете попробовать запустить его вручную, перейдя в папку 'server' и выполнив: $COLOR_BOLD$($composeCmd -join ' ') up$COLOR_RESET"
}

try {
    Create-DesktopShortcuts $composeCmd $serverDir
} catch {
    Write-Host "$COLOR_WARN[!] Ошибка создания ярлыков на Рабочем столе: $_$COLOR_RESET"
}

$localIp = Get-LocalIP

Write-Host "`n$COLOR_TITLE$COLOR_BOLD============================================================="
Write-Host "                 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                "
Write-Host "=============================================================$COLOR_RESET"
Write-Host "`n$COLOR_BOLD📍 IP-адрес для подключения игроков в локальной сети:$COLOR_RESET"
Write-Host "   $COLOR_SUCCESS$COLOR_BOLD${localIp}:$serverPort$COLOR_RESET"

if ($vrEnabled) {
    Write-Host "`n$COLOR_BOLD🎮 Инструкция для VR-игроков (клиент):$COLOR_RESET"
    Write-Host "   1. Скачанные моды для вашего клиента находятся в папке:"
    Write-Host "      $COLOR_INFO$clientModsDir$COLOR_RESET"
    Write-Host "   2. Скопируйте ВСЕ файлы из этой папки в ваш каталог $COLOR_BOLD.minecraft/mods$COLOR_RESET"
    Write-Host "      (на ПК в Prism Launcher, CurseForge или официальном лаунчере с установленным $($loaderType.substring(0,1).ToUpper() + $loaderType.substring(1)))"
    Write-Host "   3. Для игры в VR убедитесь, что вы запускаете игру через VR-шлем (SteamVR / Link / Virtual Desktop)!"
    if ($voiceEnabled) {
        Write-Host "   4. Голосовой чат (Simple Voice Chat) автоматически настроен. В игре нажмите клавишу $COLOR_BOLD'V'$COLOR_RESET для настроек микрофона."
    }
}

Write-Host "`n$COLOR_BOLD🔧 Управление сервером:$COLOR_RESET"
Write-Host "   - Остановить сервер: перейти в папку ${COLOR_INFO}server/$COLOR_RESET и ввести: $COLOR_BOLD$($composeCmd -join ' ') down$COLOR_RESET"
Write-Host "   - Посмотреть логи сервера: $COLOR_BOLD$($composeCmd -join ' ') logs -f minecraft-server$COLOR_RESET"
Write-Host "`n${COLOR_SUCCESS}Приятной игры в виртуальной реальности! 🚀$COLOR_RESET`n"
