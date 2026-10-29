import Foundation

@main struct AutomaticUpdateTests {
 static func expect(_ value:Bool,_ message:String) { if !value { fatalError(message) } }
 static func main() throws {
  if CommandLine.arguments.count==3 && CommandLine.arguments[1]=="--claim" {
   let store=AutomaticUpdateStore(base:URL(fileURLWithPath:CommandLine.arguments[2]))
   print(try store.claimDue(enabled:true,frequency:"daily",now:100) ? "1":"0");return
  }
  let root=URL(fileURLWithPath:"/private/tmp/idle-auto-tests-\(UUID())",isDirectory:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let legacy=try JSONDecoder().decode(Settings.self,from:Data("{}".utf8))
  expect(!legacy.automaticUpdateChecks && legacy.updateCheckFrequency=="daily","legacy settings must stay manual")
  let invalid=try JSONDecoder().decode(Settings.self,from:Data("{\"automaticUpdateChecks\":true,\"updateCheckFrequency\":\"unknown\"}".utf8))
  expect(!invalid.automaticUpdateChecks && invalid.updateCheckFrequency=="daily","unsupported frequency must fail closed")
  let state=AutomaticUpdateStore(base:root)
  expect(try state.claimDue(enabled:false,frequency:"daily",now:100)==false,"off must never claim a check")
  expect(!FileManager.default.fileExists(atPath:root.path),"off must not write scheduler state")
  let concurrent=root.appendingPathComponent("concurrent")
  var workers=[Process]();var outputs=[Pipe]()
  for _ in 0..<2 {
   let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=["--claim",concurrent.path]
   let pipe=Pipe();child.standardOutput=pipe;outputs.append(pipe);try child.run();workers.append(child)
  }
  for worker in workers { worker.waitUntilExit();expect(worker.terminationStatus==0,"claim process failed") }
  let answers=outputs.map{String(data:$0.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)!.trimmingCharacters(in:.whitespacesAndNewlines)}
  expect(answers.sorted()==["0","1"],"competing processes must share a single due request")
  expect(try state.claimDue(enabled:true,frequency:"daily",now:100),"first opted-in check is due")
  expect(try AutomaticUpdateStore(base:root).claimDue(enabled:true,frequency:"daily",now:100)==false,"other currency cannot duplicate due check")
  expect(try state.claimDue(enabled:true,frequency:"daily",now:86499)==false,"daily interval must not fire early")
  expect(try state.claimDue(enabled:true,frequency:"daily",now:86500),"exactly one day is due")
  expect(try state.claimDue(enabled:true,frequency:"weekly",now:86500+604799)==false,"weekly interval must not fire early")
  expect(try state.claimDue(enabled:true,frequency:"weekly",now:86500+604800),"exactly a week is due")
  expect(try state.claimDue(enabled:true,frequency:"daily",now:1000),"clock rollback permits one refreshed attempt")
  expect(try state.claimDue(enabled:true,frequency:"daily",now:1001)==false,"rollback must not cause repeated requests")
  let permissionState=AutomaticUpdateStore(base:root.appendingPathComponent("pendingPermission"))
  let pending=AvailableUpdate(version:"1.9.3",build:15)
  expect(try permissionState.recordAvailable(pending,installedBuild:14,markNotified:false),"pending authorization still records availability")
  expect(try permissionState.recordAvailable(pending,installedBuild:14),"permission completion can still claim the first notification")
  expect(try permissionState.recordAvailable(pending,installedBuild:14)==false,"other instances cannot repeat an authorized notification")
  try permissionState.retryNotification(pending)
  expect(try permissionState.recordAvailable(pending,installedBuild:14),"failed enqueue leaves notification eligible for retry")
  let release=AvailableUpdate(version:"1.9.3",build:15)
  expect(try state.recordAvailable(release,installedBuild:14),"new signed release should notify once")
  expect(try AutomaticUpdateStore(base:root).recordAvailable(release,installedBuild:14)==false,"notification dedup survives controller restart")
  expect(try state.availableUpdate(installedBuild:14)==release,"other currency can show available release hint")
  expect(try state.availableUpdate(installedBuild:15)==nil,"installed release must not show an old badge")
  try state.clearAvailable()
  expect(try state.availableUpdate(installedBuild:14)==nil,"current/no-update clears obsolete available hint")
  expect(try state.recordAvailable(release,installedBuild:14)==false,"transient feed regression must not duplicate notification")
  expect(try state.recordAvailable(AvailableUpdate(version:"1.9.4",build:16),installedBuild:14),"newer release should notify")
  expect(try state.recordAvailable(release,installedBuild:14)==false,"an older signed release must not cause a repeated alert")
  let settingsURL=root.appendingPathComponent("settings.json")
  var initial=Settings();initial.startMiningAtLogin=true
  try initial.save(to:settingsURL,startMiningAtLoginChange:true)
  var stale=try Settings.load(from:settingsURL)
  var changed=stale;changed.automaticUpdateChecks=true;changed.updateCheckFrequency="weekly"
  try changed.save(to:settingsURL,automaticUpdateChecksChange:true,updateCheckFrequencyChange:"weekly")
  stale.idleThreads=8;try stale.save(to:settingsURL)
  var saved=try Settings.load(from:settingsURL)
  expect(saved.automaticUpdateChecks && saved.updateCheckFrequency=="weekly" && saved.startMiningAtLogin && saved.idleThreads==8,"stale settings save must preserve update/login consent")
  saved.automaticUpdateChecks=false
  try saved.save(to:settingsURL,automaticUpdateChecksChange:false)
  saved=try Settings.load(from:settingsURL)
  expect(!saved.automaticUpdateChecks && saved.updateCheckFrequency=="weekly","disabling checks preserves chosen interval")
  print("PASS: optional scheduler defaults, exact daily/weekly timing, cross-instance claims/notification dedup, rollback, available hint and selective settings merges")
 }
}
