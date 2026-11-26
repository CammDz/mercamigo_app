<#
    Mercamigo · Captura de logcat para diagnosticar errores de Java/Android.

    Uso:
        powershell -ExecutionPolicy Bypass -File tool/capturar_logcat.ps1
        powershell -ExecutionPolicy Bypass -File tool/capturar_logcat.ps1 -Segundos 60
        powershell -ExecutionPolicy Bypass -File tool/capturar_logcat.ps1 -NoLimpiar

    Flujo:
        1. Deja el movil conectado por USB con la depuracion autorizada.
        2. Ejecuta este script.
        3. Cuando diga "ABRE LA APP", abre Mercamigo y reproduce el problema
           (si la app ya esta abierta, fuerza el cierre y la vuelve a abrir).
        4. El script se detiene solo y escribe el log completo en:
             build\logs\logcat-<marca>.txt
        5. Muestra en consola la primera excepcion relevante y los "Caused by".
#>
param(
    [int]$Segundos = 60,
    [string]$Paquete = "com.mercamigo.mercamigo_app",
    [switch]$NoLimpiar
)

$adb = "C:\dev\android-sdk\platform-tools\adb.exe"

if (-not (Test-Path $adb)) {
    throw "No se encuentra adb en $adb. Define la ruta del SDK de Android."
}

# --- Dispositivo ------------------------------------------------------------
$lineas = & $adb devices
$dispositivos = $lineas | Select-Object -Skip 1 | Where-Object { $_ -match "\s(device|device)$" }
if (-not $dispositivos) {
    Write-Host ""
    Write-Host "NO HAY NINGUN TELEFONO CONECTADO POR ADB."
    Write-Host ""
    Write-Host "Como conectarlo:"
    Write-Host "  1. Movil: Ajustes -> Acerca del telefono -> Numero de compilacion."
    Write-Host "     Pulsa 7 veces para activar las opciones de desarrollador."
    Write-Host "  2. Ajustes -> Opciones de desarrollador -> Depuracion USB -> activa."
    Write-Host "  3. Conecta el cable USB y acepta 'Permitir depuracion USB'."
    Write-Host "  4. Comprueba con: adb devices"
    Write-Host ""
    throw "Sin dispositivo no se puede capturar el log."
}
Write-Host "Dispositivo: $dispositivos"

$dirLogs = Join-Path (Split-Path -Parent $PSScriptRoot) "build\logs"
New-Item -ItemType Directory -Force -Path $dirLogs | Out-Null
$marca = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $dirLogs "logcat-$marca.txt"

if (-not $NoLimpiar) { & $adb logcat -c | Out-Null }

# --- Captura en vivo --------------------------------------------------------
Write-Host ""
Write-Host "ABRE LA APP Y REPRODUCE EL PROBLEMA. Capturando $Segundos segundos..."
Write-Host "Log completo en: $log"
Write-Host ""

$proc = Start-Process -FilePath $adb `
    -ArgumentList @("logcat", "-v", "threadtime", "*:V") `
    -RedirectStandardOutput $log `
    -NoNewWindow -PassThru

Start-Sleep -Seconds $Segundos

try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
Get-Process -Name "adb" -ErrorAction SilentlyContinue |
    Where-Object { $_.StartTime -ge (Get-Date).AddSeconds(-($Segundos + 30)) } |
    ForEach-Object { try { $_.Kill() } catch { } }

$contenido = Get-Content $log -ErrorAction SilentlyContinue
Write-Host "Capturados $($contenido.Count) lineas."
Write-Host ""

# --- Extraccion de lo relevante --------------------------------------------
$patronError = "AndroidRuntime|FATAL EXCEPTION|E/AndroidRuntime|E/flutter|E/flutter|E ActivityManager|"
$patronError += "java\.|javax\.|kotlin\.|Caused by:|Unhandled Exception|MissingPlugin|"
$patronError += "NoSuchMethodError|NoClassDefFoundError|ClassNotFoundException|"
$patronError += "IllegalStateException|NullPointerException|SecurityException|"
$patronError += "Process: com\.mercamigo|ANR in com\.mercamigo"

$destacado = $contenido | Select-String -Pattern $patronError

Write-Host "===== ERRORES DESTACADOS (linea completa) ====="
if ($destacado) {
    $destacado | ForEach-Object { $_.Line }
} else {
    "(ninguna linea coincide con los filtros)"
}

Write-Host ""
Write-Host "===== PRIMERA EXCEPCION CON SU CADENA 'Caused by' ====="
$excepcion = $contenido | Where-Object { $_ -match "FATAL EXCEPTION|^\S+\s+\S+\s+\d+\s+\d+\s+\S+\s+E AndroidRuntime" } | Select-Object -First 1
if (-not $excepcion) {
    $excepcion = $destacado | Select-Object -First 1
}
if ($excepcion) {
    $linea = ($excepcion | Select-Object -First 1)
    if ($linea -is [System.Management.Automation.MatchInfo]) { $linea = $linea.Line }
    $indice = [array]::IndexOf($contenido, $linea)
    if ($indice -ge 0) {
        $fin = [Math]::Min($contenido.Count - 1, $indice + 80)
        $contenido[$indice..$fin] | ForEach-Object { $_ }
    }
} else {
    "(no se encontro ninguna excepcion)"
}

Write-Host ""
Write-Host "===== LOG DE LA APP (tag Mercamigo/boot y flutter) ====="
$contenido | Where-Object { $_ -match "Mercamigo/boot|flutter" } | Select-Object -Last 60 | ForEach-Object { $_ }

Write-Host ""
Write-Host "===== INFORMACION DEL PROCESO ====="
& $adb shell dumpsys package $Paquete 2>&1 | Select-String -Pattern "versionName|versionCode|firstInstallTime|lastUpdateTime" | ForEach-Object { $_.Line.Trim() }
& $adb shell getprop ro.build.version.release 2>&1 | ForEach-Object { "Android: $_" }
& $adb shell getprop ro.product.model 2>&1 | ForEach-Object { "Modelo: $_" }

Write-Host ""
Write-Host "Log completo: $log"
