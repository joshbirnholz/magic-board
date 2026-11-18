$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!$env:XMAGE_HOME -or !$env:RULES_BRIDGE_TOKEN) { throw 'Set XMAGE_HOME and RULES_BRIDGE_TOKEN.' }
if (!(Test-Path build/magicboard-rules.jar)) { throw 'The bridge jar is missing. Build it first or extract the complete bridge bundle.' }
if (!(Test-Path "$env:XMAGE_HOME/mage-client/lib/mage-client-1.4.63.jar")) { throw 'XMAGE_HOME must contain the matching mage-client and mage-server directories.' }
& java -Xmx512m --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -Dfile.encoding=UTF-8 -cp "build/magicboard-rules.jar;lib/*;$env:XMAGE_HOME/mage-client/lib/*" magicboard.rules.BridgeMain @args
exit $LASTEXITCODE
