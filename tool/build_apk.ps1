<#
    Mercamigo · Script único de compilación con la configuración de Supabase.

    Los MISMOS nombres de variable que usa el código
    (lib/core/config/app_config.dart):

        SUPABASE_URL
        SUPABASE_PUBLISHABLE_KEY

    Se pueden sobreescribir por entorno; si no, se usan los valores reales
    del proyecto `moviles-mercamigo` (kbbbwdoommxsczjliqlu).

    La clave que se incrusta es la PUBLICABLE (sb_publishable_...), pensada
    para ir dentro de la app. Nunca la `service_role` ni la contrasena de
    PostgreSQL.

    Uso:
        powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1
        powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1 -Debug
#>
param(
    [switch]$Debug,
    [string]$Target = "lib/main.dart"
)

$ErrorActionPreference = "Stop"

$SupabaseUrl = $env:SUPABASE_URL
$SupabaseKey = $env:SUPABASE_PUBLISHABLE_KEY

if (-not $SupabaseUrl -or -not $SupabaseKey) {
    throw "Faltan SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY. Copia .env.example como .env y exporta las variables antes de compilar."
}

Write-Host "Proyecto Supabase : $SupabaseUrl"
Write-Host "SUPABASE_URL      : $SupabaseUrl"
Write-Host "SUPABASE_PUBLISHABLE_KEY : $($SupabaseKey.Substring(0, 18))..."

$defines = @(
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$SupabaseKey"
)

# Localiza el SDK de Flutter (no depende de que este en el PATH).
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) {
    $candidates = @(
        "$env:FLUTTER_ROOT\bin\flutter.bat",
        "C:\dev\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "$env:USERPROFILE\flutter\bin\flutter.bat"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { $flutter = $candidate; break }
    }
}
if (-not $flutter) {
    throw "No se encuentra el SDK de Flutter. Define FLUTTER_ROOT o anade flutter al PATH."
}
Write-Host "Flutter SDK       : $flutter"

# SDK de Android (sin esto, flutter build apk no arranca).
if (-not $env:ANDROID_HOME) {
    $androidCandidates = @(
        "C:\dev\android-sdk",
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:ANDROID_SDK_ROOT"
    )
    foreach ($candidate in $androidCandidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "platform-tools"))) {
            $env:ANDROID_HOME = $candidate
            $env:ANDROID_SDK_ROOT = $candidate
            break
        }
    }
}
if ($env:ANDROID_HOME) {
    Write-Host "ANDROID_HOME     : $($env:ANDROID_HOME)"
} else {
    Write-Warning "No se encuentra ANDROID_HOME: define el SDK de Android antes de compilar."
}

# JDK 17/21 (Gradle del proyecto no funciona con Java 25).
if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    $jdkCandidates = @()
    foreach ($base in @("C:\Program Files\Java", "C:\Program Files\Eclipse Adoptium")) {
        if (Test-Path $base) {
            $jdkCandidates += Get-ChildItem $base -Directory -ErrorAction SilentlyContinue
        }
    }
    $jdkCandidates = $jdkCandidates |
        Where-Object { $_.Name -match 'jdk-(17|21)' } |
        Sort-Object Name -Descending
    foreach ($candidate in $jdkCandidates) {
        if (Test-Path (Join-Path $candidate.FullName "bin\java.exe")) {
            $env:JAVA_HOME = $candidate.FullName
            break
        }
    }
}
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    Write-Host "JAVA_HOME        : $($env:JAVA_HOME)"
} else {
    Write-Warning "No se encontro un JDK 17/21 valido: define JAVA_HOME antes de compilar."
}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

# ---------------------------------------------------------------------------
# Preparacion: en Windows el daemon de Gradle mantiene abiertos los
# directorios de build/app/intermediates y la tarea :app:cleanMergeReleaseAssets
# falla con "Unable to delete directory ... mergeReleaseAssets" (IOException).
# Se detiene el daemon y se limpian los intermedios ANTES de compilar.
# ---------------------------------------------------------------------------
function Invoke-PreparacionBuild {
    Write-Host "Preparando compilacion (deteniendo el daemon de Gradle)..."
    if (Test-Path "android\gradlew.bat") {
        & "android\gradlew.bat" --stop 2>&1 | Out-Null
    }
    # Espera SOLO a los daemons de Gradle/Kotlin (otros procesos java, como
    # el servidor de VS Code, no bloquean la compilacion ni deben esperarse).
    for ($i = 0; $i -lt 20; $i++) {
        $daemons = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'GradleDaemon|KotlinCompileDaemon' }
        if (-not $daemons) { break }
        Start-Sleep -Seconds 1
    }
    # El daemon de Kotlin no lo detiene `gradlew --stop` y mantiene abiertas
    # carpetas tmp\kotlin-classes de los plugins; se cierra explicitamente.
    Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'KotlinCompileDaemon' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    # Carpetas que Gradle vuelve a generar y que no deben quedarse con
    # ficheros abiertos (el junction build/ apunta fuera de OneDrive, pero
    # OneDrive puede llegar a bloquearlas).
    $relativas = @(
        "build\app\intermediates",
        "build\app\generated",
        "build\app\outputs\apk"
    )
    # Los modulos de plugins tambien se quedan bloqueados en
    # build\<plugin>\intermediates (javac) y build\<plugin>\tmp\kotlin-classes
    # (Kotlin), y hacian fallar compileReleaseJavaWithJavac / compileReleaseKotlin.
    Get-ChildItem (Join-Path $root "build") -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            foreach ($sub in @("intermediates", "tmp\kotlin-classes")) {
                $candidate = Join-Path $_.FullName $sub
                if (Test-Path $candidate) {
                    $relativas += "build\$($_.Name)\$sub"
                }
            }
        }
    foreach ($rel in $relativas) {
        $dir = Join-Path $root $rel
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Build {
    # Out-Host evita que la salida de Flutter se mezcle con el valor de
    # retorno: si no, $code acaba siendo un array y `exit $code` devuelve 0.
    & $flutter build apk --release --target $Target @defines | Out-Host
    return $LASTEXITCODE
}

if (-not $Debug) {
    Invoke-PreparacionBuild
    $code = Invoke-Build
    if ($code -ne 0) {
        # Reintento: el fallo habitual es "Unable to delete directory" por un
        # bloqueo de OneDrive o del daemon de Gradle.
        Write-Host ""
        Write-Warning "La compilacion fallo. Se reintenta limpiando de nuevo."
        Invoke-PreparacionBuild
        $code = Invoke-Build
    }
    Write-Host ""
    Write-Host "APK: $(Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk')"
    Pop-Location
    exit $code
} else {
    & $flutter run --target $Target @defines
}

Pop-Location
