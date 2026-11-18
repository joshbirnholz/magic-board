#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${XMAGE_HOME:?Set XMAGE_HOME to the extracted xmage directory}"
: "${RULES_BRIDGE_TOKEN:?Set the bridge connection key}"
mkdir -p build/test-classes
rules_test_classpath="build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*"
javac --release 17 -cp "$rules_test_classpath" -d build/test-classes tests/BridgeSmoke.java
unset RULES_SMOKE_ABILITY RULES_SMOKE_DECK RULES_SMOKE_COVERAGE_ONLY RULES_SMOKE_REQUIRED_PROMPTS RULES_SMOKE_MANUAL_TRIGGERS RULES_SMOKE_SPECIAL_ACTION RULES_SMOKE_RESOLVE_STACK
probe() {
    rules_scenario="$1"
    rules_required="$2"
    shift 2
    env RULES_SMOKE_DECK="tests/decks/$rules_scenario.json" RULES_SMOKE_COVERAGE_ONLY=1 \
        RULES_SMOKE_REQUIRED_PROMPTS="$rules_required" "$@" \
        java -Xmx256m -cp "$rules_test_classpath" BridgeSmoke
}
probe triggers GAME_TARGET/PICK_ABILITY RULES_SMOKE_MANUAL_TRIGGERS=1
probe modes GAME_CHOOSE_ABILITY,MODAL_SPELL_CAST
probe costs ALTERNATIVE_COST,ALTERNATIVE_SPELL_CAST
probe morph SPECIAL_ACTION,MORPH_REVEALED RULES_SMOKE_SPECIAL_ACTION=1
probe x-mana GAME_GET_AMOUNT,NONZERO_X_SPELL_CAST
probe hybrid HYBRID_SPELL_CAST
probe search LIBRARY_CARD_TO_HAND
probe hybrid STACK_RESOLVED_STOP RULES_SMOKE_RESOLVE_STACK=1
