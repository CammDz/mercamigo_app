<#
    Mercamigo · Ejecutor de las pruebas SQL de las migraciones.

    Crea una base de datos PostgreSQL LOCAL con el esquema inicial (replica
    del proyecto Supabase) + el catalogo real, aplica las migraciones
    corregidas y ejecuta la bateria de verificacion.

    ⚠ No toca el proyecto remoto de Supabase en ningun momento: solo la base
      local `mercamigo_test`.

    Uso:
      powershell -ExecutionPolicy Bypass -File supabase/tests/ejecutar_pruebas.ps1
#>
param(
    [string]$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    [string]$Createdb = "C:\Program Files\PostgreSQL\18\bin\createdb.exe",
    [string]$Dropdb = "C:\Program Files\PostgreSQL\18\bin\dropdb.exe",
    [string]$Host_ = "127.0.0.1",
    [int]$Port = 5432,
    [string]$User = "postgres",
    [string]$Password = "",
    [string]$Database = "mercamigo_test"
)

$ErrorActionPreference = "Stop"
if ($Password -ne "") { $env:PGPASSWORD = $Password }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrations = Join-Path $root "supabase\migrations"
$tests = Join-Path $root "supabase\tests"

function Run-Psql([string]$sqlFile, [switch]$Quiet) {
    $args = @("-v", "ON_ERROR_STOP=1", "-U", $User, "-h", $Host_, "-p", "$Port",
              "-d", $Database, "-f", $sqlFile)
    if ($Quiet) { $args = @("-q") + $args }
    & $Psql @args
    if ($LASTEXITCODE -ne 0) { throw "Fallo en $sqlFile (exit $LASTEXITCODE)" }
}

Write-Output "== 1. Recreando la base de pruebas '$Database' =="
$ErrorActionPreference = "Continue"
& $Dropdb -U $User -h $Host_ -p $Port --if-exists $Database 2>&1 | Out-Null
& $Createdb -U $User -h $Host_ -p $Port $Database 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

Write-Output ""
Write-Output "== 1b. Version del servidor =="
& $Psql -U $User -h $Host_ -p $Port -d $Database -tAc "select version();"

Write-Output "== 1. Esquema inicial (replica del proyecto) =="
Run-Psql (Join-Path $tests "schema_inicial.sql") -Quiet
Write-Output "== 2. Catalogo real (8 categorias, 40 productos, 40 codigos) =="
Run-Psql (Join-Path $tests "datos_demo.sql") -Quiet
Write-Output "== 3. Migracion 20261021001000_crear_pedido =="
Run-Psql (Join-Path $migrations "20261021001000_crear_pedido.sql") -Quiet
Write-Output "== 4. Migracion 20261021002000_roles_y_administracion =="
Run-Psql (Join-Path $migrations "20261021002000_roles_y_administracion.sql") -Quiet
Write-Output "== 4b. Migracion 20261021100000_admin_productos_y_codigos =="
Run-Psql (Join-Path $migrations "20261021100000_admin_productos_y_codigos.sql") -Quiet

Write-Output ""
Write-Output "== 5. Verificacion funcional =="
Run-Psql (Join-Path $tests "verificacion.sql")

Write-Output ""
Write-Output "== 5b. Verificacion del panel de administracion =="
Run-Psql (Join-Path $tests "verificacion_admin.sql")

Write-Output ""
Write-Output "== 6. Pruebas SQL completadas =="
