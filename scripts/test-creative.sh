#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

for required_tool in xcodebuild python3 luajit; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Missing required tool: $required_tool" >&2
        exit 1
    fi
done

creative_artifacts=$(mktemp -d "${TMPDIR:-/tmp}/bellith-creative-checks.XXXXXX")
creative_derived_data=${BELLITH_CREATIVE_DERIVED_DATA:-/tmp/bellith-creative-derived-data}
trap 'echo "Creative check artifacts: $creative_artifacts"' EXIT

echo "Running focused creative app tests…"
creative_suites=(StudioTests CreativeCompanionLaunchTests CreativeProjectTests CreativeProjectHistoryTests
    CreativeReviewLinkTests ResolveGoalSessionTests ResolveGoalPlannerTests LogicTransportTests SessionStateTests)
creative_test_args=()
for suite in "${creative_suites[@]}"; do
    creative_test_args+=("-only-testing:BellithTests/$suite")
done
if ! xcodebuild -project Bellith.xcodeproj -scheme Bellith -configuration Debug \
    -derivedDataPath "$creative_derived_data" "${creative_test_args[@]}" test \
    > "$creative_artifacts/xcode-tests.log" 2>&1; then
    echo "Focused app tests failed. See $creative_artifacts/xcode-tests.log" >&2
    exit 1
fi

echo "Checking the Resolve Lua bridge…"
luajit scripts/tests/resolve-bridge-tests.lua
creative_cli="$creative_derived_data/Build/Products/Debug/Bellith.app/Contents/Resources/bellith"
test -x "$creative_cli"
echo "Checking built MCP protocols…"
python3 scripts/tests/creative-evidence-tests.py "$creative_cli"
python3 scripts/tests/logic-evidence-tests.py "$creative_cli"
echo "Creative checks passed. Live UI, provider authentication and host execution are separate qualifications."
