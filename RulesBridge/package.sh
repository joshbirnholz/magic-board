#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${XMAGE_HOME:?Set XMAGE_HOME to the extracted xmage directory}"
sh build.sh
rules_package=build/package/MagicBoard-RulesBridge
rm -rf "$rules_package"
mkdir -p "$rules_package/build" "$rules_package/lib"
cp build/magicboard-rules.jar "$rules_package/build/"
cp lib/Java-WebSocket-1.6.0.jar "$rules_package/lib/"
cp run.sh run.ps1 start-server.ps1 build.sh build.ps1 README.md PC-SETUP.md "$rules_package/"
cp -R src tests ThirdParty "$rules_package/"
git rev-parse HEAD > "$rules_package/SOURCE-COMMIT.txt"
rm -f build/MagicBoard-RulesBridge.zip
(cd build/package && zip -q -r ../MagicBoard-RulesBridge.zip MagicBoard-RulesBridge)
shasum -a 256 build/MagicBoard-RulesBridge.zip > build/MagicBoard-RulesBridge.zip.sha256
printf 'Bridge package: %s\n' "$PWD/build/MagicBoard-RulesBridge.zip"
