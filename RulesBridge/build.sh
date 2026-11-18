#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${XMAGE_HOME:?Set XMAGE_HOME to the extracted xmage directory containing mage-client and mage-server}"
mkdir -p lib build
if [ ! -f lib/Java-WebSocket-1.6.0.jar ]; then
    curl -L --fail --silent --show-error https://repo.maven.apache.org/maven2/org/java-websocket/Java-WebSocket/1.6.0/Java-WebSocket-1.6.0.jar -o lib/Java-WebSocket-1.6.0.jar
fi
printf '%s\n' 'eae29213e4f16515639c28957200f011b3967fffcada1962cf0255d24919c22f  lib/Java-WebSocket-1.6.0.jar' | shasum -a 256 -c -
rm -rf build/main-classes
mkdir -p build/main-classes
javac --release 17 -encoding UTF-8 -cp "$XMAGE_HOME/mage-client/lib/*:lib/*" -d build/main-classes src/magicboard/rules/*.java
jar --create --file build/magicboard-rules.jar -C build/main-classes .
