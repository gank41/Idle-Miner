#!/bin/zsh
set -euo pipefail
root=${0:A:h}
zsh "$root/tools/fetch-sparkle.sh"
common=("$root/Sources/Core.swift" "$root/Sources/ProfileCoordination.swift" "$root/Sources/SessionClock.swift")
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Tests/CoreTests.swift" -o /private/tmp/miner-core-tests
/private/tmp/miner-core-tests
/usr/bin/python3 "$root/Tests/SupervisorTests.py" "$root/Idle Miner.app/Contents/Resources/miner-supervisor"
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Tests/EngineIntegration.swift" -o /private/tmp/miner-engine-test
/private/tmp/miner-engine-test "$root/Idle Miner.app/Contents/Resources"
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/BuiltInUpdater.swift" "$root/Sources/UpdateUserDriver.swift" "$root/Sources/UpdateCoordination.swift" -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$root/Vendor/Sparkle" "$root/Sources/SharedMenuStore.swift" "$root/Sources/SharedMenuPresentation.swift" "$root/Sources/UpdateService.swift" "$root/Sources/UpdatePresentation.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/UISmoke.swift" -o /private/tmp/MinerUISmoke
IDLE_MINER_STATE=$(mktemp -d /private/tmp/miner-ui.XXXXXX) /private/tmp/MinerUISmoke

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Tests/StatsTests.swift" -o /private/tmp/miner-stats-tests
/private/tmp/miner-stats-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Tests/EngineFaultTests.swift" -o /private/tmp/miner-fault-tests
/private/tmp/miner-fault-tests "$root/Idle Miner.app/Contents/Resources"

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Tests/FeatureTests.swift" -o /private/tmp/miner-feature-tests
/private/tmp/miner-feature-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/BuiltInUpdater.swift" "$root/Sources/UpdateUserDriver.swift" "$root/Sources/UpdateCoordination.swift" -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$root/Vendor/Sparkle" "$root/Sources/SharedMenuStore.swift" "$root/Sources/SharedMenuPresentation.swift" "$root/Sources/UpdateService.swift" "$root/Sources/UpdatePresentation.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/MultiInstanceIntegration.swift" -o /private/tmp/miner-multi-tests
/private/tmp/miner-multi-tests "$root/Idle Miner.app/Contents/Resources"

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Tests/EthereumStartupTests.swift" -o /private/tmp/miner-eth-tests
/private/tmp/miner-eth-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/BuiltInUpdater.swift" "$root/Sources/UpdateUserDriver.swift" "$root/Sources/UpdateCoordination.swift" -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$root/Vendor/Sparkle" "$root/Sources/SharedMenuStore.swift" "$root/Sources/SharedMenuPresentation.swift" "$root/Sources/UpdateService.swift" "$root/Sources/UpdatePresentation.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/LoginStartupIntegration.swift" -o /private/tmp/miner-login-tests
IDLE_MINER_STATE=$(mktemp -d /private/tmp/miner-login.XXXXXX) /private/tmp/miner-login-tests
IDLE_MINER_STATE=$(mktemp -d /private/tmp/miner-manual.XXXXXX) /private/tmp/miner-login-tests --manual

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "${common[@]}" "$root/Sources/SharedMenuStore.swift" "$root/Tests/SharedMenuTests.swift" -o /private/tmp/miner-shared-tests
/private/tmp/miner-shared-tests
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache "$root/Sources/UpdateService.swift" "$root/Tests/UpdateTests.swift" -o /private/tmp/miner-update-tests
/private/tmp/miner-update-tests

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -framework IOKit "${common[@]}" "$root/Sources/Runtime.swift" "$root/Sources/App.swift" "$root/Sources/BuiltInUpdater.swift" "$root/Sources/UpdateUserDriver.swift" "$root/Sources/UpdateCoordination.swift" -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$root/Vendor/Sparkle" "$root/Sources/SharedMenuStore.swift" "$root/Sources/SharedMenuPresentation.swift" "$root/Sources/UpdateService.swift" "$root/Sources/UpdatePresentation.swift" "$root/Sources/LoginItem.swift" "$root/Sources/MiningStats.swift" "$root/Sources/StatsService.swift" "$root/Sources/StatsWindow.swift" "$root/Sources/StatsPresentation.swift" "$root/Sources/MenuSummary.swift" "$root/Sources/ProfilePresentation.swift" "$root/Tests/SharedMenuIntegration.swift" -o /private/tmp/miner-native-shared-integration
/private/tmp/miner-native-shared-integration

/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit "$root/Sources/Core.swift" "$root/Sources/ProfileCoordination.swift" "$root/Sources/UpdateCoordination.swift" "$root/Tests/BuiltInUpdatePolicyTests.swift" -o /private/tmp/idle-updater-tests
/private/tmp/idle-updater-tests
/usr/bin/swiftc -parse-as-library -module-cache-path /private/tmp/miner-swift-cache -framework AppKit -F "$root/Vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$root/Vendor/Sparkle" "$root/Sources/Core.swift" "$root/Sources/ProfileCoordination.swift" "$root/Sources/UpdateCoordination.swift" "$root/Sources/UpdateUserDriver.swift" "$root/Tests/BuiltInUpdateUISmoke.swift" -o /private/tmp/idle-updater-ui-tests
/private/tmp/idle-updater-ui-tests
/usr/bin/python3 "$root/Tests/SparkleInstallIntegration.py"
