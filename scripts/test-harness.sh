#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
luajit scripts/tests/resolve-bridge-tests.lua
task_dir=$(mktemp -d /tmp/bellith-harness-tests.XXXXXX)
mkdir -p "$task_dir/Sources/Bellith" "$task_dir/Tests/BellithTests"
cp Bellith/Models/ResolveGoalSession.swift Bellith/Models/CreativeReviewLink.swift "$task_dir/Sources/Bellith/"
cp Bellith/Services/ResolveHarnessModel.swift Bellith/Services/ResolveComputerAdapter.swift Bellith/Services/ResolveGoalPlanner.swift "$task_dir/Sources/Bellith/"
cp BellithTests/ResolveGoalSessionTests.swift BellithTests/ResolveGoalPlannerTests.swift "$task_dir/Tests/BellithTests/"
cat > "$task_dir/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "BellithHarnessChecks", platforms: [.macOS(.v14)], targets: [
    .target(name: "Bellith"),
    .testTarget(name: "BellithTests", dependencies: ["Bellith"]),
])
PACKAGE
swift test --package-path "$task_dir"
echo "Test artifacts: $task_dir"
