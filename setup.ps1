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

$ESC           = [char]27
$COLOR_TITLE   = "$ESC[95m"  # Purple
$COLOR_INFO    = "$ESC[94m"  # Blue
$COLOR_SUCCESS = "$ESC[92m"  # Green
$COLOR_WARN    = "$ESC[93m"  # Yellow
$COLOR_FAIL    = "$ESC[91m"  # Red
$COLOR_BOLD    = "$ESC[1m"
$COLOR_RESET   = "$ESC[0m"

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Force TLS 1.2 for modern web requests (fixes Forge Maven download error)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Show-Banner {
    $banner = @"
$COLOR_TITLE$COLOR_BOLD=============================================================
    __  ___ _                                 __ _      ____ 
   /  |/  /(_)____   ___   _____  _____ ____ _/ //_/     / __ \
  / /|_/ // // __ \ / _ \ / ___/ / ___// __ ``/ __/ /| /| / /_/ /
 / /  / // // / / //  __// /__  / /   / /_/ / /_  / |/ |/ /_, _/ 
/_/  /_//_//_/ /_/ \___/ \___/ /_/    \__,_/\__/  /__/|__/_/ |_|  
                                                             
             VR SERVER AUTO-INSTALLER (NATIVE WINDOWS)
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

function Download-File ($url, $destPath) {
    try {
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

function Fetch-ModrinthVersion ($slug, $mcVersion, $loader) {
    $url = "https://api.modrinth.com/v2/project/$slug/version"
    $headers = @{ "User-Agent" = "antigravity/minecraft-vr-installer/1.0" }
    
    try {
        $versions = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction SilentlyContinue
        $matching = @()
        foreach ($v in $versions) {
            if ($v.game_versions -notcontains $mcVersion) { continue }
            $loaders = $v.loaders
            if ($loaders -notcontains $loader -and $loaders -notcontains "minecraft") { continue }
            $matching += $v
        }
        if ($matching.Count -eq 0) { return $null }
        foreach ($v in $matching) {
            if ($v.version_type -eq "release") { return $v }
        }
        return $matching[0]
    } catch {
        return $null
    }
}

function Install-PortableJava ($mcVersion, $serverDir) {
    $javaVer = 17
    $parts = $mcVersion.Split('.')
    if ($parts.Length -ge 2 -and [int]$parts[1] -ge 21) {
        $javaVer = 21
    } elseif ($parts.Length -ge 3 -and [int]$parts[1] -eq 20 -and [int]$parts[2] -ge 5) {
        $javaVer = 21
    }
    
    $runtimeDir = Join-Path $serverDir "runtime"
    $jreDir = Join-Path $runtimeDir "jre"
    $javaExe = Join-Path $jreDir "bin\java.exe"
    
    if (Test-Path $javaExe) {
        Write-Host "$COLOR_SUCCESS[✓] Портативная Java $javaVer уже установлена.$COLOR_RESET"
        return $javaExe
    }
    
    Write-Host "`n$COLOR_INFO[*] Скачивание портативной Java $javaVer (около 50 МБ, подождите)...$COLOR_RESET"
    $null = New-Item -ItemType Directory -Force -Path $runtimeDir -ErrorAction SilentlyContinue
    $zipPath = Join-Path $runtimeDir "jre.zip"
    
    $url = "https://api.adoptium.net/v3/binary/latest/$javaVer/ga/windows/x64/jre/hotspot/normal/eclipse"
    $success = Download-File $url $zipPath
    
    if (-not $success) {
        Write-Host "$COLOR_FAIL[✕] Не удалось скачать Java! Пожалуйста, проверьте интернет.$COLOR_RESET"
        Exit 1
    }
    
    Write-Host "$COLOR_INFO[*] Распаковка Java...$COLOR_RESET"
    Expand-Archive -Path $zipPath -DestinationPath $runtimeDir -Force
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    
    $extractedDir = Get-ChildItem -Path $runtimeDir -Directory | Where-Object { $_.Name -like "jdk*" -or $_.Name -like "jre*" } | Select-Object -First 1
    if ($null -ne $extractedDir) {
        Rename-Item -Path $extractedDir.FullName -NewName "jre" -Force
    }
    
    if (Test-Path $javaExe) {
        Write-Host "$COLOR_SUCCESS[✓] Java успешно распакована.$COLOR_RESET"
        return $javaExe
    } else {
        Write-Host "$COLOR_FAIL[✕] Ошибка: java.exe не найден после распаковки.$COLOR_RESET"
        Exit 1
    }
}

Show-Banner

$defaultInstallDir = Get-Location
if ($defaultInstallDir.Path -like "*\System32*" -or $defaultInstallDir.Path -like "*\system32*" -or $defaultInstallDir.Path -eq "C:\Windows" -or $defaultInstallDir.Path -eq "C:\WINDOWS") {
    $defaultInstallDir = "C:\Minecraft-VR-Server"
} elseif ($defaultInstallDir.Path.EndsWith("Minecraft-VR-Server") -or $defaultInstallDir.Path.EndsWith("Minecraft-VR-Server\")) {
    $defaultInstallDir = $defaultInstallDir.Path
} else {
    $defaultInstallDir = Join-Path $defaultInstallDir.Path "Minecraft-VR-Server"
}

Write-Host "`n${COLOR_BOLD}=== ВЫБОР ПАПКИ УСТАНОВКИ ===$COLOR_RESET"
$targetDirInput = Get-Input "Введите путь для установки сервера" $defaultInstallDir

$baseDir = [System.IO.Path]::GetFullPath($targetDirInput)
$serverDir = Join-Path $baseDir "server"
$null = New-Item -ItemType Directory -Force -Path $serverDir
Set-Location $serverDir
Write-Host "${COLOR_SUCCESS}[✓] Папка сервера: $serverDir$COLOR_RESET"

Write-Host "`n$COLOR_BOLD=== НАСТРОЙКА MINECRAFT СЕРВЕРА ===$COLOR_RESET`n"

$mcVersion = Get-Input "Введите версию Minecraft" "1.20.1"
if ([string]::IsNullOrWhiteSpace($mcVersion)) { $mcVersion = "1.20.1" }

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
$onlineMode = "true"
if ($onlineInput.ToLower() -eq 'y') { $onlineMode = "false" }

$serverPort = Get-Input "Основной порт сервера" "25565"
$viewDistance = Get-Input "Дальность прорисовки (чанков)" "10"

$vrModsInput = Get-Input "Скачать VR моды (Vivecraft)? (y/n)" "y"
$vrEnabled = $vrModsInput.ToLower() -eq 'y'

$voiceChatInput = Get-Input "Установить 3D Голосовой чат (Simple Voice Chat)? (y/n)" "y"
$voiceEnabled = $voiceChatInput.ToLower() -eq 'y'

# 1. Setup Java
$javaExe = Install-PortableJava $mcVersion $serverDir

# 2. Download and run Installer
Write-Host "`n$COLOR_INFO[*] Установка ядра $loaderType для Minecraft $mcVersion...$COLOR_RESET"

if ($loaderType -eq "fabric") {
    $fabricMetaUrl = "https://meta.fabricmc.net/v2/versions/loader/$mcVersion"
    $fabricVersions = Invoke-RestMethod $fabricMetaUrl -ErrorAction SilentlyContinue
    if ($null -eq $fabricVersions -or $fabricVersions.Count -eq 0) {
        Write-Host "$COLOR_FAIL[✕] Не найдена версия Fabric для Minecraft $mcVersion$COLOR_RESET"
        Exit 1
    }
    $loaderVer = ($fabricVersions | Where-Object { $_.stable -eq $true })[0].loader.version
    if ($null -eq $loaderVer) { $loaderVer = $fabricVersions[0].loader.version }
    
    $installerMeta = Invoke-RestMethod "https://meta.fabricmc.net/v2/versions/installer" -ErrorAction SilentlyContinue
    $installerVer = $installerMeta[0].version
    if ($null -eq $installerVer) { $installerVer = "1.0.1" }
    
    $serverUrl = "https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loaderVer/$installerVer/server/jar"
    Write-Host "  Поиск Fabric завершен (Лоадер: $loaderVer)"
    Download-File $serverUrl "fabric-server-launch.jar" | Out-Null
} 
elseif ($loaderType -eq "forge") {
    $forgePromosUrl = "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
    $promos = Invoke-RestMethod $forgePromosUrl -ErrorAction SilentlyContinue
    $forgeVer = $promos.promos."$mcVersion-recommended"
    if ($null -eq $forgeVer) { $forgeVer = $promos.promos."$mcVersion-latest" }
    
    if ($null -eq $forgeVer) {
        Write-Host "$COLOR_FAIL[✕] Не найдена версия Forge для Minecraft $mcVersion$COLOR_RESET"
        Exit 1
    }
    $fullForgeVer = "$mcVersion-$forgeVer"
    $installerUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$fullForgeVer/forge-$fullForgeVer-installer.jar"
    Write-Host "  Поиск Forge завершен (Версия: $forgeVer)"
    $success = Download-File $installerUrl "forge-installer.jar"
    
    if ($success) {
        Write-Host "  $COLOR_INFO[*] Запуск установщика Forge (подождите окно установки)...$COLOR_RESET"
        Start-Process -FilePath $javaExe -ArgumentList "-jar", "forge-installer.jar", "--installServer" -Wait -NoNewWindow
        Remove-Item "forge-installer.jar" -ErrorAction SilentlyContinue
        Remove-Item "forge-installer.jar.log" -ErrorAction SilentlyContinue
    }
}
elseif ($loaderType -eq "neoforge") {
    try {
        [xml]$neoMeta = Invoke-RestMethod "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" -ErrorAction SilentlyContinue
        $neoVersions = $neoMeta.metadata.versioning.versions.version
        $matchingVersions = @()
        foreach ($v in $neoVersions) {
            if ($mcVersion -eq "1.20.1" -and $v -like "47.1.*") { $matchingVersions += $v }
            elseif ($mcVersion.StartsWith("1.") -and $v -like "$($mcVersion.Substring(2)).*") { $matchingVersions += $v }
        }
        if ($matchingVersions.Count -eq 0) {
            Write-Host "$COLOR_FAIL[✕] Автоматический поиск версии NeoForge не удался. Выбираем последнюю доступную.$COLOR_RESET"
            $neoVer = $neoVersions[-1]
        } else {
            $neoVer = $matchingVersions[-1]
        }
        $installerUrl = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$neoVer/neoforge-$neoVer-installer.jar"
        Write-Host "  Поиск NeoForge завершен (Версия: $neoVer)"
        $success = Download-File $installerUrl "neoforge-installer.jar"
        if ($success) {
            Write-Host "  $COLOR_INFO[*] Запуск установщика NeoForge (подождите окно установки)...$COLOR_RESET"
            Start-Process -FilePath $javaExe -ArgumentList "-jar", "neoforge-installer.jar", "--installServer" -Wait -NoNewWindow
            Remove-Item "neoforge-installer.jar" -ErrorAction SilentlyContinue
            Remove-Item "neoforge-installer.jar.log" -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "$COLOR_FAIL[✕] Ошибка установки NeoForge: $_$COLOR_RESET"
        Exit 1
    }
}

# 3. Generate Configs
Write-Host "`n$COLOR_INFO[*] Создание конфигурации сервера...$COLOR_RESET"

$eulaPath = Join-Path $serverDir "eula.txt"
Set-Content -Path $eulaPath -Value "eula=true"

$propsPath = Join-Path $serverDir "server.properties"
$propsContent = @"
server-port=$serverPort
online-mode=$onlineMode
view-distance=$viewDistance
"@
Set-Content -Path $propsPath -Value $propsContent
Write-Host "$COLOR_SUCCESS[✓] Настройки сохранены (EULA принята).$COLOR_RESET"

# 4. Download Mods
$modsDir = Join-Path $serverDir "mods"
$null = New-Item -ItemType Directory -Force -Path $modsDir

if ($vrEnabled -or $voiceEnabled) {
    Write-Host "`n$COLOR_INFO[*] Скачивание серверных модов...$COLOR_RESET"
    $modList = @()
    if ($vrEnabled) {
        $modList += [PSCustomObject]@{ Slug = "vivecraft"; Name = "Vivecraft (VR мод)" }
        if ($loaderType -eq "fabric") {
            $modList += [PSCustomObject]@{ Slug = "fabric-api"; Name = "Fabric API" }
        }
    }
    if ($voiceEnabled) {
        $modList += [PSCustomObject]@{ Slug = "simple-voice-chat"; Name = "Simple Voice Chat" }
    }
    
    foreach ($m in $modList) {
        Write-Host "  ${COLOR_BOLD}Поиск $($m.Name)...$COLOR_RESET"
        $vInfo = Fetch-ModrinthVersion $m.Slug $mcVersion $loaderType
        if ($null -ne $vInfo) {
            $fileObj = $vInfo.files | Where-Object { $_.primary } | Select-Object -First 1
            if ($null -eq $fileObj) { $fileObj = $vInfo.files[0] }
            $destPath = Join-Path $modsDir $fileObj.filename
            if (-not (Test-Path $destPath)) {
                $null = Download-File $fileObj.url $destPath
            } else {
                Write-Host "  [✓] Уже скачано."
            }
        } else {
            Write-Host "  $COLOR_WARN[!] Версия не найдена.$COLOR_RESET"
        }
    }
}

# 5. Generate Start Scripts
Write-Host "`n$COLOR_INFO[*] Создание скриптов запуска...$COLOR_RESET"

$startBatPath = Join-Path $serverDir "start.bat"
$startContent = @"

@echo off
title Minecraft VR Server
cd /d "%~dp0"
set JAVA_HOME=%~dp0runtime\jre
set PATH=%JAVA_HOME%\bin;%PATH%
"@

if ($loaderType -eq "fabric") {
    $startContent += "`njava -Xms$ramGb -Xmx$ramGb -jar fabric-server-launch.jar nogui`npause"
} else {
    $jvmArgsPath = Join-Path $serverDir "user_jvm_args.txt"
    if (Test-Path $jvmArgsPath) {
        $jvmContent = Get-Content $jvmArgsPath
        $jvmContent = $jvmContent -replace "#-Xmx4G", "-Xmx$ramGb"
        $jvmContent = $jvmContent -replace "-Xmx\d+[GM]", "-Xmx$ramGb"
        $jvmContent = $jvmContent -replace "-Xms\d+[GM]", "-Xms$ramGb"
        if (-not ($jvmContent -match "-Xmx")) {
            $jvmContent += "`n-Xms$ramGb`n-Xmx$ramGb"
        }
        Set-Content -Path $jvmArgsPath -Value $jvmContent
    }
    $startContent += "`ncall run.bat`npause"
}
$startContent = $startContent -replace "`r`n", "`n" -replace "`n", "`r`n"
Set-Content -Path $startBatPath -Value $startContent

# Control Shortcut
$desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop))
$controlBat = Join-Path $desktopPath "Minecraft_Server_Control.bat"
$controlContent = @"

@echo off
chcp 65001 > nul

for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.IPAddress -notlike '127.*' -and `$_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress"`) do set LOCAL_IP=%%a

:menu
cls
echo =================================================
echo    УПРАВЛЕНИЕ MINECRAFT VR СЕРВЕРОМ
echo =================================================
echo IP для подключения: %LOCAL_IP%:$serverPort
echo =================================================
echo 1] Запустить сервер
echo 2] Остановить сервер
echo 3] Выдать админку (OP)
echo 4] Поменять настройки (запустить установщик)
echo 5] Открыть папку с модами
echo 6] Открыть папку сервера
echo 7] Выйти
echo =================================================
set /p choice="Выберите действие (1-7): "

if "%choice%"=="1" (
    cd /d "$serverDir"
    start cmd /c "start.bat"
    goto menu
)
if "%choice%"=="2" (
    echo.
    echo [ВНИМАНИЕ] Для безопасного выключения сервера перейдите в его окно и напишите 'stop'.
    echo Если вы хотите принудительно убить зависший сервер (может повредить мир):
    set /p kill="Убить процесс сервера принудительно? (y/n): "
    if /i "%kill%"=="y" (
        echo Выключение сервера...
        taskkill /FI "WINDOWTITLE eq Minecraft VR Server" /F /T >nul 2>&1
        echo Сервер принудительно остановлен!
    )
    pause
    goto menu
)
if "%choice%"=="3" (
    echo.
    echo [ИНФОРМАЦИЯ] Для выдачи прав администратора:
    echo Перейдите в открытое черное окно запущенного сервера и напишите:
    echo op ВашНик
    echo.
    pause
    goto menu
)
if "%choice%"=="4" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/aaaSaZaN/Minecraft-VR-Server-Installer/master/setup.ps1 | iex"
    pause
    goto menu
)
if "%choice%"=="5" (
    explorer "$modsDir"
    goto menu
)
if "%choice%"=="6" (
    explorer "$serverDir"
    goto menu
)
if "%choice%"=="7" exit
goto menu
"@
$controlContent = $controlContent -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($controlBat, $controlContent, [System.Text.Encoding]::UTF8)

$localIp = "127.0.0.1"
try {
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" 
    } | Select-Object -First 1).IPAddress
} catch {}

Write-Host "`n$COLOR_TITLE$COLOR_BOLD============================================================="
Write-Host "                 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                "
Write-Host "=============================================================$COLOR_RESET"
Write-Host "`n$COLOR_BOLD📍 IP-адрес для подключения игроков в локальной сети:$COLOR_RESET"
Write-Host "   $COLOR_SUCCESS$COLOR_BOLD${localIp}:$serverPort$COLOR_RESET"
Write-Host "`nЯрлык управления создан на Рабочем столе: $COLOR_INFO$controlBat$COLOR_RESET`n"
Write-Host "Теперь вы можете безопасно выключить и включить сервер через меню ярлыка!"
