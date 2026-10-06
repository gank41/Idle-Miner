import Foundation
import Darwin
@main struct FeatureTests {
 static func main() throws {
  func expect(_ value:Bool,_ message:String) { if !value { fatalError(message) } }
  let old=Data(#"{"coin":"BTC","address":"1BoatSLRHtKNngkdXEeobR76b53LETtpyT","idleThreads":4,"pauseWhileActive":false,"idleSeconds":300}"#.utf8)
  var settings=try JSONDecoder().decode(Settings.self,from:old)
  expect(settings.wallets["BTC"]==settings.address,"legacy address migrated")
  settings.switchCoin(to:"DOGE");expect(settings.address.isEmpty,"switch cannot reuse a wrong-coin wallet")
  settings.switchCoin(to:"BTC");expect(settings.address=="1BoatSLRHtKNngkdXEeobR76b53LETtpyT","saved wallet restored")
  settings.showDock=false;settings.showMenuBar=false;expect((try? settings.validated())==nil,"both access paths cannot be disabled")
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent("miner-feature-"+UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:folder) }
  var good=Settings();good.coin="BTC";good.address="1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
  let file=folder.appendingPathComponent("settings.json");try good.save(to:file)
  var first=try Settings.load(from:file);var second=first
  first.showDock=true;try first.save(to:file,walletChanges:["BTC":good.address])
  second.switchCoin(to:"DOGE");try second.save(to:file,walletChanges:["DOGE":""])
  expect(try Settings.load(from:file).wallets["BTC"]==good.address,"peer wallet edits do not get discarded")
  var clock=SessionClock(launchedAt:100)
  clock.begin(date:Date(timeIntervalSince1970:1),at:110);clock.sample(at:115,hashing:true);clock.sample(at:120,hashing:false)
  expect(clock.hashingSeconds==5,"hashing clock excludes initialization")
  clock.stop(at:125);expect(clock.elapsed(at:500)==15,"Stop freezes session elapsed")
  expect(clock.uptime(at:500)==400,"app uptime independent of mining")
  expect(SessionClock.duration(90061)=="1d 1h 1m 1s","multi-day duration")
  let a=try ProfileCoordinator(base:folder,profile:"default")
  expect((try? ProfileCoordinator(base:folder,profile:"default"))==nil,"duplicate profile is locked")
  let b=try ProfileCoordinator(base:folder,profile:"DOGE")
  expect(a.claimCoin("BTC"),"first currency available");expect(!b.claimCoin("BTC"),"currency cannot mine twice")
  expect(b.claimCoin("DOGE"),"separate currency allowed")
  expect(try a.quota(requested:8,actual:0,budget:8,cores:16)==8,"single instance uses configured budget")
  expect(try b.quota(requested:8,actual:0,budget:8,cores:16)==0,"second waits for actual threads to be released")
  expect(try a.quota(requested:8,actual:8,budget:8,cores:16)==4,"first shares budget")
  expect(try a.quota(requested:8,actual:4,budget:8,cores:16)==4,"reduction acknowledged")
  expect(try b.quota(requested:8,actual:0,budget:8,cores:16)==4,"second gets remaining half")
  a.releaseCoin();expect(b.claimCoin("BTC"),"currency lease released cleanly")
  let crashFolder=folder.appendingPathComponent("crash")
  var crashed:ProfileCoordinator?=try ProfileCoordinator(base:crashFolder,profile:"default")
  expect(crashed!.claimCoin("BTC"),"Crash fixture claims currency")
  _=try crashed!.quota(requested:4,actual:4,budget:8,cores:16)
  var remainingEngine:FileLease?=try FileLease(url:crashed!.engineLeaseURL)
  crashed=nil
  let peer=try ProfileCoordinator(base:crashFolder,profile:"DOGE")
  expect(!peer.claimCoin("BTC"),"Crashed controller cannot release its currency before engine cleanup")
  expect(try peer.quota(requested:8,actual:0,budget:8,cores:16)==4,"Orphan engine still reserves CPU capacity")
  expect((try? ProfileCoordinator(base:crashFolder,profile:"default"))==nil,"Relaunch cannot overwrite the orphan reservation")
  withExtendedLifetime(remainingEngine){}
  remainingEngine=nil
  expect(peer.claimCoin("BTC"),"Currency recovers after engine lease is released")
  expect(try peer.quota(requested:8,actual:4,budget:8,cores:16)==8,"Capacity recovers after engine cleanup")
  print("PASS: settings migration, wallet merge, visibility, clocks and multi-instance CPU/currency controls")
 }
}
