#!/bin/sh
set -eu
rules_repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
if [ ! -f "$rules_repo_root/Magic Board/RulesPlay/RulesProtocol.swift" ] || [ ! -f "$rules_repo_root/RulesBridge/tests/DecodeRulesEvents.swift" ]; then
    printf '%s\n' 'Run this checker from the full repository checkout; the standalone bridge bundle does not include the app wire models.' >&2
    exit 66
fi
rules_decode_build="$rules_repo_root/RulesBridge/build"
mkdir -p "$rules_decode_build/swift-module-cache"
xcrun swiftc -parse-as-library -module-cache-path "$rules_decode_build/swift-module-cache" \
    "$rules_repo_root/Magic Board/RulesPlay/RulesProtocol.swift" \
    "$rules_repo_root/RulesBridge/tests/DecodeRulesEvents.swift" \
    -o "$rules_decode_build/decode-events"
exec "$rules_decode_build/decode-events" "$@"
