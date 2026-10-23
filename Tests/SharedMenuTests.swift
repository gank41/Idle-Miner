import Foundation
@main struct SharedMenuTests {
 static func main()throws {
  func expect(_ ok:Bool,_ message:String) { if !ok { print("FAIL: \(message)");exit(1) } }
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("miner-shared-"+UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  let firstCoordinator=try ProfileCoordinator(base:root,profile:"default")
  let secondCoordinator=try ProfileCoordinator(base:root,profile:"ETH")
  withExtendedLifetime((firstCoordinator,secondCoordinator)) {
   do {
    let first=try SharedMenuStore(base:root,profile:"default"),second=try SharedMenuStore(base:root,profile:"ETH")
    expect(first.claimOwnership(),"first instance owns presentation")
    expect(!second.claimOwnership(),"second instance cannot create a second icon")
    first.releaseOwnership();expect(second.claimOwnership(),"remaining worker takes over after owner quits")
    try first.publish(coin:"BTC",level:"working",enabled:true,lines:["Hashing","Fresh work"],now:100)
    try second.publish(coin:"ETH",level:"inactive",enabled:false,lines:["Stopped"],now:100)
    let peers=first.snapshots(now:102);expect(peers.count==2,"each live profile has independent status")
    expect(first.snapshots(now:114).isEmpty,"stale status cannot remain green")
    let btc=peers.first{$0.coin=="BTC"}!,eth=peers.first{$0.coin=="ETH"}!
    try second.send(btc,action:"stop",now:102)
    expect(second.commands(coin:"ETH",now:103).isEmpty,"commands do not cross profiles")
    expect(first.commands(coin:"BTC",now:103).map(\.action)==["stop"],"only intended worker receives command")
    expect(first.commands(coin:"BTC",now:103).isEmpty,"commands consumed exactly once")
    try first.send(eth,action:"boost",minutes:15,now:102)
    let boost=second.commands(coin:"ETH",now:103)
    expect(boost.first?.minutes==15,"timed boost preserved")
    expect((try? first.send(eth,action:"shell",now:103))==nil,"arbitrary commands rejected")
    expect((try? first.send(eth,action:"boost",minutes:7,now:103))==nil,"unsupported timers rejected")
    try first.send(eth,action:"start",now:102)
    expect(second.commands(coin:"BTC",now:103).isEmpty,"old currency command cannot start a newly selected coin")
    try second.send(btc,action:"start",now:102)
    expect(first.commands(coin:"BTC",now:120).isEmpty,"expired start commands rejected")
    try second.send(btc,action:"start",now:105)
    try second.send(btc,action:"stop",now:106)
    expect(first.commands(coin:"BTC",now:107).map(\.action)==["start","stop"],"rapid start then stop preserves the user's final intent")
    let attrs=try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("SharedMenu/snapshot-default.json").path)
    expect(attrs[.posixPermissions] as? Int==0o600,"status files remain private")
    print("PASS: single icon election, owner failover, per-currency freshness, targeted commands, timers, replay and privacy")
   } catch { print(error);exit(1) }
  }
 }
}
