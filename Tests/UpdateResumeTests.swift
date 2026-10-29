import Foundation
import Darwin

// Losing actual enabled state (including paused automatic mining), accepting an
// unarmed/stale receipt, or consuming twice must fail these behavioral checks.
@main struct UpdateResumeTests {
 static func expect(_ value:Bool,_ message:String) { if !value { fatalError(message) } }
 static func main() throws {
  let root=URL(fileURLWithPath:"/private/tmp/update-resume-\(UUID())",isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let bundle=root.appendingPathComponent("Idle Miner.app")
  let store=UpdateResumeStore(base:root)
  var capability:UUID?
  func arm()throws { capability=try store.arm() }
  let expected:[String:Int32]=["DOGE":11,"BTC":12,"ETH":13,"default":14]
  func capture(_ now:Date=Date()) throws {
   try store.begin(bundleURL:bundle,sourceBuild:"12",targetBuild:"13",targetVersion:"1.9.1",primaryProfile:"DOGE",expected:expected,now:now)
   for (profile,pid,coin,enabled) in [("DOGE",Int32(11),"ETH",true),("BTC",12,"BTC",false),("ETH",13,"DOGE",true),("default",14,"LTC",false)] {
    try store.acknowledge(bundleURL:bundle,sourceBuild:"12",profile:profile,pid:pid,coin:coin,enabled:enabled,now:now)
   }
   try store.finalize(now:now)
  }
  try capture()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability)==nil,"manual launch cannot consume an unarmed plan")
  try capture();try arm()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false)==nil,"manual new-build launch cannot replay armed state after installer failure or a crash before consumption")
  try capture();try arm()
  let plan=try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability)
  expect(plan?.primaryCoin=="ETH","named source profile restores its actual switched currency")
  expect(plan?.currencies==["ETH":true,"BTC":false,"DOGE":true,"LTC":false],"four currencies preserve enabled and manually stopped states")
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability)==nil,"receipt is single use")
  try capture();try arm()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:true,capability:capability)==nil,"actual login discards update state regardless of login opt-in")
  try capture();try arm()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.2",loginLaunch:false,capability:capability)==nil,"wrong target version cannot resume")
  try capture(Date(timeIntervalSinceNow:-3700))
  do { try arm();fatalError("expired plan armed") } catch {}
  try capture();try arm()
  expect(try store.consume(bundleURL:root.appendingPathComponent("Other.app"),build:"13",version:"1.9.1",loginLaunch:false,capability:capability)==nil,"different bundle cannot resume")
  expect(try store.consume(bundleURL:bundle,build:"12",version:"1.9",loginLaunch:false,capability:capability)==nil,"old build cannot resume")
  try capture();try store.cancel()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability)==nil,"cancelled install has no resume state")
  try store.begin(bundleURL:bundle,sourceBuild:"12",targetBuild:"13",targetVersion:"1.9.1",primaryProfile:"DOGE",expected:expected)
  try store.acknowledge(bundleURL:bundle,sourceBuild:"12",profile:"DOGE",pid:11,coin:"ETH",enabled:true)
  try store.acknowledge(bundleURL:bundle,sourceBuild:"12",profile:"DOGE",pid:11,coin:"ETH",enabled:false)
  do { try store.finalize();fatalError("missing peer state admitted") } catch {}
  for (profile,pid) in expected where profile != "DOGE" { try store.acknowledge(bundleURL:bundle,sourceBuild:"12",profile:profile,pid:pid,coin:"ETH",enabled:false) }
  try store.finalize();try arm()
  expect(try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability)?.currencies==["ETH":true],"first ack wins and duplicate currency enabled states combine with OR")
  try capture(Date(timeIntervalSinceNow:-3700))
  do { _=try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability);fatalError("expired receipt consumed") } catch {}
  try store.cancel()
  try capture();try arm()
  let receipt=root.appendingPathComponent("UpdateResume/receipt.json")
  try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:receipt.path)
  do { _=try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability);fatalError("public receipt admitted") } catch {}
  try FileManager.default.removeItem(at:receipt)
  try Data("malformed".utf8).write(to:receipt)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:receipt.path)
  do { _=try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability);fatalError("malformed receipt admitted") } catch {}
  try FileManager.default.removeItem(at:receipt)
  try FileManager.default.createSymbolicLink(at:receipt,withDestinationURL:root.appendingPathComponent("private-data"))
  do { _=try store.consume(bundleURL:bundle,build:"13",version:"1.9.1",loginLaunch:false,capability:capability);fatalError("symlink receipt admitted") } catch {}
  print("PASS: exact update resume, switched named profiles, paused enabled state, mixed stopped currencies, login precedence, expiry, cancellation, single use and private-file validation")
 }
}
