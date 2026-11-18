$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!$env:XMAGE_HOME -or !$env:RULES_BRIDGE_TOKEN) { throw 'Set XMAGE_HOME and RULES_BRIDGE_TOKEN.' }
& java -Xmx512m --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -cp "build/magicboard-rules.jar;lib/*;$env:XMAGE_HOME/mage-client/lib/*" magicboard.rules.BridgeMain @args
exit $LASTEXITCODE
