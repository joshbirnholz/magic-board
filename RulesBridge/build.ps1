$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!$env:XMAGE_HOME) { throw 'Set XMAGE_HOME to your extracted xmage directory.' }
New-Item -ItemType Directory -Force lib, build | Out-Null
if (!(Test-Path lib/Java-WebSocket-1.6.0.jar)) {
    Invoke-WebRequest https://repo.maven.apache.org/maven2/org/java-websocket/Java-WebSocket/1.6.0/Java-WebSocket-1.6.0.jar -OutFile lib/Java-WebSocket-1.6.0.jar
}
if ((Get-FileHash lib/Java-WebSocket-1.6.0.jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'eae29213e4f16515639c28957200f011b3967fffcada1962cf0255d24919c22f') {
    throw 'WebSocket dependency checksum mismatch.'
}
$sources = Get-ChildItem src/magicboard/rules/*.java | ForEach-Object FullName
if (Test-Path build/main-classes) { Remove-Item -Recurse -Force build/main-classes }
New-Item -ItemType Directory -Force build/main-classes | Out-Null
& javac --release 17 -encoding UTF-8 -cp "$env:XMAGE_HOME/mage-client/lib/*;lib/*" -d build/main-classes $sources
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
& jar --create --file build/magicboard-rules.jar -C build/main-classes .
if ($LASTEXITCODE -ne 0) { throw 'Jar creation failed.' }
