#!/bin/zsh
set -euo pipefail
root=${0:A:h}
common=("$root/Sources/Core.swift" "$root/Sources/ProfileCoordination.swift" "$root/Sources/SessionClock.swift")
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Tests/CoreTests.swift" -o /private/tmp/miner-core-tests
/private/tmp/miner-core-tests
/usr/bin/python3 "$root/Tests/SupervisorTests.py" "$root/Idle Miner.app/Contents/Resources/miner-supervisor"
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Tests/EngineIntegration.swift" -o /private/tmp/miner-engine-test
/private/tmp/miner-engine-test "$root/Idle Miner.app/Contents/Resources"
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/UISmoke.swift" -o /private/tmp/MinerUISmoke
IDLE_MINER_STATE=$(mktemp -d /private/tmp/miner-ui.XXXXXX) /private/tmp/MinerUISmoke

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Tests/StatsTests.swift" -o /private/tmp/miner-stats-tests
/private/tmp/miner-stats-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Tests/EngineFaultTests.swift" -o /private/tmp/miner-fault-tests
/private/tmp/miner-fault-tests "$root/Idle Miner.app/Contents/Resources"

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Tests/FeatureTests.swift" -o /private/tmp/miner-feature-tests
/private/tmp/miner-feature-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/MultiInstanceIntegration.swift" -o /private/tmp/miner-multi-tests
/private/tmp/miner-multi-tests "$root/Idle Miner.app/Contents/Resources"
