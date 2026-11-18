param(
    [ValidateRange(512, 8192)]
    [int]$HeapMB = 1024
)

$ErrorActionPreference = 'Stop'
if (!$env:XMAGE_HOME) { throw 'Set XMAGE_HOME to your extracted xmage directory.' }
$serverDirectory = Join-Path $env:XMAGE_HOME 'mage-server'
$serverJar = Join-Path $serverDirectory 'lib/mage-server-1.4.63.jar'
if (!(Test-Path -LiteralPath $serverJar)) {
    throw "The pinned XMage server was not found at $serverJar. See README.md for the matching release."
}
if (!(Get-Command java -ErrorAction SilentlyContinue)) { throw 'Install Java 17 and add it to PATH.' }

# XMage reads its config and plugins relative to its server directory.
Push-Location -LiteralPath $serverDirectory
try {
    & java "-Xmx${HeapMB}m" --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -jar $serverJar
    $serverExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $serverExitCode
