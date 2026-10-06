import Foundation
@main struct CoreTests {
 static func main() throws {
  var checks = 0
  func expect(_ value: Bool, _ label: String) { checks += 1; if !value { print("FAIL: \(label)"); exit(1) } }
  expect(!Completion.isFailure(code:0,requested:false,benchmark:true), "successful benchmark is not failure")
  expect(Completion.isFailure(code:0,requested:false,benchmark:false), "live miner unexpectedly ending is reported")
  expect(Completion.isFailure(code:1,requested:false,benchmark:true), "failed benchmark is reported")
  var s = Settings(); var e = Environment()
  expect(Policy.threads(s, e) == 1, "active user gets one thread")
  e.idleSeconds = 299; expect(Policy.threads(s,e) == 1, "no early idle boost")
  e.idleSeconds = 300; expect(Policy.threads(s,e) == 4, "boost at five minutes")
  e.onAC = false; expect(Policy.threads(s,e) == 0, "battery blocks idle mining")
  e.onAC = true; e.thermal = 2; expect(Policy.threads(s,e) == 0, "serious thermals pause")
  e.thermal = 1; expect(Policy.threads(s,e) == 1, "fair thermals restrict")
  e.thermal = 0; e.memoryPressure = true; expect(Policy.threads(s,e) == 0, "memory warning pauses")
  e.memoryPressure = false; e.sleeping = true; expect(Policy.threads(s,e) == 0, "sleep pauses")
  e.sleeping = false; e.idleSeconds = 0; s.pauseWhileActive = true
  expect(Policy.threads(s,e) == 0, "user can disable active mining")
  e.idleSeconds = 400; e.busy = true; expect(Policy.threads(s,e,ceiling:2) == 2, "sustained load ceiling controls idle mining")
  s.pauseWhileActive = false; s.idleThreads = 12; e.busy = false; e.cores = 4
  expect(Policy.threads(s,e) == 2, "reserve hardware headroom")
  s=Settings(); s.idleThreads=8; e=Environment()
  let session=TimedBoost(minutes:15,now:100)!
  expect(session.remaining(at:100)==900,"15 minute countdown")
  expect(session.isActive(at:999.9),"boost runs until deadline")
  expect(!session.isActive(at:1000),"boost expires exactly at deadline")
  expect(session.remaining(at:2000)==0,"sleep past deadline does not extend boost")
  expect(Policy.threads(s,e,boost:session.isActive(at:999))==8,"boost overrides active user limit")
  expect(Policy.threads(s,e,boost:session.isActive(at:1000))==1,"expiry returns active user to one thread")
  s.pauseWhileActive=true
  expect(Policy.threads(s,e,boost:true)==8,"explicit boost overrides pause while active")
  expect(Policy.threads(s,e,boost:false)==0,"expiry restores pause preference")
  e.idleSeconds=400
  expect(Policy.threads(s,e,boost:false)==8,"expiry preserves ordinary idle mining")
  e.onAC=false; expect(Policy.threads(s,e,boost:true)==0,"boost cannot override battery protection")
  e.onAC=true; e.thermal=2; expect(Policy.threads(s,e,boost:true)==0,"boost cannot override thermal protection")
  e.thermal=0; e.memoryPressure=true; expect(Policy.threads(s,e,boost:true)==0,"boost cannot override memory protection")
  e.memoryPressure=false; e.sleeping=true; expect(Policy.threads(s,e,boost:true)==0,"boost cannot override sleep")
  e.sleeping=false; e.busy=true; expect(Policy.threads(s,e,boost:true,ceiling:1)==1,"boost preserves sustained load ceiling")
  s.pauseWhileActive=false; e.busy=false; e.thermal=1
  expect(Policy.threads(s,e,boost:true)==1,"boost reduces threads with fair thermals")
  e.thermal=0; e.cores=4
  expect(Policy.threads(s,e,boost:true)==2,"boost reserves CPU headroom")
  expect(TimedBoost(minutes:5,now:0)==nil,"reject unsupported duration")
  for minutes in TimedBoost.durations {
   expect(TimedBoost(minutes:minutes,now:0)!.remaining(at:0)==minutes*60,"duration \(minutes) minutes")
  }
  expect(session.countdown(at:100)=="0:15:00","countdown formatting")
  expect(Wallet.valid("1BoatSLRHtKNngkdXEeobR76b53LETtpyT", coin: "BTC"), "known valid Base58 Bitcoin")
  expect(!Wallet.valid("1BoatSLRHtKNngkdXEeobR76b53LETtpyU", coin: "BTC"), "reject bad checksum")
  expect(!Wallet.valid("1BoatSLRHtKNngkdXEeobR76b53LETtpyT", coin: "LTC"), "reject wrong network")
  expect(!Wallet.valid(" ", coin: "LTC"), "reject empty wallet")
  expect(!Wallet.valid("Lanything.worker#ref", coin: "LTC"), "reject pool username injection")
  expect(Wallet.valid("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", coin:"BTC"), "BIP173 witness address")
  expect(!Wallet.valid("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", coin:"BTC"), "reject bech32 typo")
  s = Settings(); s.coin="BTC"; s.address="1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
  let payload = try EngineConfig.make(s, threads:4, benchmark:false)
  let obj = try JSONSerialization.jsonObject(with:payload) as! [String:Any]
  let pool = (obj["pools"] as! [[String:Any]])[0]
  expect(pool["tls"] as? Bool == true, "TLS mandatory")
  expect(pool["user"] as? String == "BTC:1BoatSLRHtKNngkdXEeobR76b53LETtpyT.IdleMiner", "correct payout routing")
  let offline = try JSONSerialization.jsonObject(with:EngineConfig.make(Settings(),threads:2,benchmark:true)) as! [String:Any]
  expect((offline["pools"] as! [Any]).isEmpty, "offline test cannot use a pool")
  expect((offline["benchmark"] as? [String:Any])?["size"] as? String == "1M", "benchmark configured in file to retain CPU limits")
  expect((offline["cpu"] as! [String:Any])["yield"] as? Bool == true,"benchmark still yields CPU")
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:dir) }
  let url=dir.appendingPathComponent("settings.json"); try s.save(to:url)
  expect(try Settings.load(from:url).address == s.address, "wallet survives relaunch")
  var parser = LineBuffer(); expect(parser.feed(Data("abc".utf8)).isEmpty,"partial chunk retained")
  expect(parser.feed(Data("def\nnext\n".utf8)) == ["abcdef","next"], "chunk boundaries preserve messages")
  var governor=LoadGovernor()
  governor.observe(utilization:0.95,threads:8,ready:true,now:0)
  governor.observe(utilization:0.95,threads:8,ready:true,now:4)
  expect(governor.ceiling==12,"brief CPU spike does not change threads")
  governor.observe(utilization:0.95,threads:8,ready:true,now:5)
  expect(governor.ceiling==4,"sustained load halves threads")
  for t in 6...120 { governor.observe(utilization:0.4,threads:4,ready:true,now:Double(t)) }
  expect(governor.ceiling==4,"low load does not rebound into the same overload")
  governor.observe(utilization:0.99,threads:4,ready:true,now:121)
  governor.observe(utilization:0.99,threads:4,ready:true,now:126)
  expect(governor.ceiling==2,"continued load can back off further")
  governor.reset(); governor.observe(utilization:0.99,threads:8,ready:false,now:0)
  governor.observe(utilization:0.99,threads:8,ready:false,now:10)
  expect(governor.ceiling==12,"initialization is not mistaken for steady mining load")
  expect(offline["watch"] as? Bool == true,"configuration changes watched without an HTTP control server")
  print("PASS: \(checks) policy, wallet, settings, and engine checks")
 }
}
