import Foundation
import CryptoKit
import Darwin

struct Settings: Codable {
 static let coins=["LTC","DOGE","BTC"]
 var coin="LTC"
 var address=""
 var idleThreads=4
 var pauseWhileActive=false
 var idleSeconds:Double=300
 var wallets=[String:String]()
 var showDock=false
 var showMenuBar=true
 init() {}
 enum CodingKeys:String,CodingKey { case coin,address,idleThreads,pauseWhileActive,idleSeconds,wallets,showDock,showMenuBar }
 init(from decoder:Decoder)throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  coin=try c.decodeIfPresent(String.self,forKey:.coin) ?? "LTC"
  address=try c.decodeIfPresent(String.self,forKey:.address) ?? ""
  idleThreads=try c.decodeIfPresent(Int.self,forKey:.idleThreads) ?? 4
  pauseWhileActive=try c.decodeIfPresent(Bool.self,forKey:.pauseWhileActive) ?? false
  idleSeconds=try c.decodeIfPresent(Double.self,forKey:.idleSeconds) ?? 300
  wallets=try c.decodeIfPresent([String:String].self,forKey:.wallets) ?? [:]
  showDock=try c.decodeIfPresent(Bool.self,forKey:.showDock) ?? false
  showMenuBar=try c.decodeIfPresent(Bool.self,forKey:.showMenuBar) ?? true
  if wallets[coin]==nil && !address.isEmpty { wallets[coin]=address }
  address=wallets[coin] ?? address
 }
 mutating func switchCoin(to currency:String) {
  guard Self.coins.contains(currency) else { return }
  if wallets[coin]==nil && !address.isEmpty { wallets[coin]=address }
  coin=currency; address=wallets[currency] ?? ""
 }
 func validated()throws->Settings {
  guard Self.coins.contains(coin),[2,4,8,12].contains(idleThreads),idleSeconds==300 else { throw MinerError.message("Unsupported settings. Please save Settings again.") }
  guard showDock || showMenuBar else { throw MinerError.message("Keep the Dock icon, menu bar icon, or both enabled.") }
  guard address.isEmpty || Wallet.valid(address,coin:coin) else { throw MinerError.message("The address checksum or network does not match \(coin). Copy its native Receive address again.") }
  for (currency,value) in wallets {
   guard Self.coins.contains(currency),value.isEmpty || Wallet.valid(value,coin:currency) else { throw MinerError.message("Check the saved \(currency) native-network Receive address.") }
  }
  return self
 }
 func save(to url:URL,walletChanges:[String:String]?=nil,updateDefaultCoin:Bool=true)throws {
  _=try validated()
  try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let lock=try FileLease(url:url.deletingLastPathComponent().appendingPathComponent("settings.lock"),nonblocking:false)
  defer { withExtendedLifetime(lock){} }
  let previous=try Self.load(from:url)
  var stored=self;stored.wallets=previous.wallets
  let changes=walletChanges ?? wallets.merging([coin:address]) { _,new in new }
  for (currency,value) in changes { stored.wallets[currency]=value }
  if !updateDefaultCoin { stored.coin=previous.coin }
  stored.address=stored.wallets[stored.coin] ?? ""
  _=try stored.validated()
  try JSONEncoder().encode(stored).write(to:url,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
 }
 static func load(from url:URL)throws->Settings {
  guard FileManager.default.fileExists(atPath:url.path) else { return Settings() }
  return try JSONDecoder().decode(Self.self,from:Data(contentsOf:url)).validated()
 }
}

enum MinerError: LocalizedError { case message(String); var errorDescription:String? { if case .message(let s) = self { return s }; return nil } }
struct Environment {
 var idleSeconds:Double = 0
 var onAC = true
 var thermal = 0
 var memoryPressure = false
 var sleeping = false
 var busy = false
 var cpuUtilization:Double?
 var cores = 16
}
enum Policy {
 static func threads(_ s:Settings,_ e:Environment,boost:Bool=false,ceiling:Int=12) -> Int {
  if !e.onAC || e.thermal >= 2 || e.memoryPressure || e.sleeping { return 0 }
  if (!boost && e.idleSeconds < s.idleSeconds) || e.thermal == 1 { return s.pauseWhileActive ? 0 : 1 }
  return min(s.idleThreads,max(1,e.cores-2),max(1,ceiling))
 }
 static func pauseReason(_ e:Environment) -> String {
  if e.sleeping { return "Paused · system sleep" }
  if !e.onAC { return "Paused · battery or power unavailable" }
  if e.memoryPressure { return "Paused · memory pressure" }
  if e.thermal >= 2 { return "Paused · thermal pressure" }
  if e.busy { return "Paused · Mac is busy" }
  return "Paused · waiting for five minutes idle"
 }
}
enum Wallet {
 static func valid(_ s:String,coin:String) -> Bool {
  guard !s.isEmpty, s.count <= 90, s.allSatisfy({$0.isASCII}), s == s.trimmingCharacters(in:.whitespacesAndNewlines) else { return false }
  let lower=s.lowercased()
  if lower.hasPrefix("bc1") || lower.hasPrefix("ltc1") {
   let hrp=coin == "BTC" ? "bc" : coin == "LTC" ? "ltc" : ""
   return bech32(s,hrp:hrp)
  }
  let alphabet=Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
  var bytes=[UInt8]()
  for ch in s {
   guard let value=alphabet.firstIndex(of:ch) else { return false }
   var carry=value
   for i in bytes.indices { carry += Int(bytes[i])*58; bytes[i]=UInt8(carry & 255); carry >>= 8 }
   while carry>0 { bytes.append(UInt8(carry & 255)); carry >>= 8 }
  }
  let decoded=Array(repeating:UInt8(0),count:s.prefix(while:{$0 == "1"}).count)+bytes.reversed()
  guard decoded.count == 25 else { return false }
  let allowed:[UInt8] = coin == "BTC" ? [0,5] : coin == "LTC" ? [48,50] : coin == "DOGE" ? [30] : []
  guard allowed.contains(decoded[0]) else { return false }
  let hash=Array(SHA256.hash(data:Data(SHA256.hash(data:Data(decoded.prefix(21))))))
  return Array(decoded.suffix(4)) == Array(hash.prefix(4))
 }
 private static func bech32(_ s:String,hrp:String) -> Bool {
  guard !hrp.isEmpty, s == s.lowercased() || s == s.uppercased() else { return false }
  let v=s.lowercased(); guard v.hasPrefix(hrp+"1") else { return false }
  let chars=Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
  let values=v.dropFirst(hrp.count+1).compactMap { chars.firstIndex(of:$0).map(UInt32.init) }
  guard values.count == v.count-hrp.count-1, values.count >= 7 else { return false }
  // Native SegWit v0 only; avoid unsupported Taproot/MWEB payout routes.
  guard values[0] == 0 else { return false }
  let expanded=hrp.utf8.map{UInt32($0>>5)}+[0]+hrp.utf8.map{UInt32($0 & 31)}
  var chk:UInt32=1
  let generators:[UInt32]=[0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]
  for x in expanded+values {
   let top=chk>>25; chk=((chk & 0x1ffffff)<<5)^x
   for i in 0..<5 where (top>>i)&1 != 0 { chk ^= generators[i] }
  }
  guard chk == 1 else { return false }
  var acc:UInt32=0; var bits=0; var program=[UInt8]()
  for x in values.dropFirst().dropLast(6) {
   acc=((acc<<5)|x)&0xffff; bits += 5
   while bits>=8 { bits -= 8; program.append(UInt8((acc>>bits)&255)) }
  }
  return bits<5 && ((acc<<(8-bits))&255)==0 && [20,32].contains(program.count)
 }
}
enum EngineConfig {
 static func make(_ settings:Settings,threads:Int,benchmark:Bool) throws -> Data {
  guard (1...12).contains(threads) else { throw MinerError.message("Invalid thread count") }
  _ = try settings.validated()
  if !benchmark && !Wallet.valid(settings.address,coin:settings.coin) { throw MinerError.message("Configure a valid public receive address in Settings first.") }
  let pools:[[String:Any]]=benchmark ? [] : [["url":"rx.unmineable.com:443","user":"\(settings.coin):\(settings.address).IdleMiner","pass":"x","tls":true,"keepalive":true,"algo":"rx/0"]]
  var obj:[String:Any] = ["watch":true,"autosave":false,"background":false,"colors":false,"donate-level":1,"pools":pools,"cpu":["enabled":true,"priority":1,"yield":true,"huge-pages":false,"rx":Array(repeating:-1,count:threads),"*":false],"randomx":["init":min(threads,2),"mode":"fast"],"opencl":false,"cuda":false,"http":["enabled":false],"print-time":5,"retries":3,"retry-pause":10]
  if benchmark { obj["benchmark"]=["size":"1M","submit":false] }
  return try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys])
 }
}
struct LineBuffer {
 var pending=Data()
 mutating func feed(_ data:Data)->[String] {
  pending.append(data); var lines=[String]()
  while let idx=pending.firstIndex(of:10) { lines.append(String(decoding:pending[..<idx],as:UTF8.self)); pending.removeSubrange(...idx) }
  if pending.count>65536 { pending.removeAll() }
  return lines
 }
}

enum Completion {
 static func isFailure(code:Int32,requested:Bool,benchmark:Bool)->Bool { !requested && !(benchmark && code==0) }
}

// A continuous monotonic clock includes system sleep and ignores wall-clock changes.
enum BoostClock {
 static var now:Double {
  var info=mach_timebase_info_data_t()
  mach_timebase_info(&info)
  return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
 }
}
struct TimedBoost {
 static let durations=[15,30,60,360,720,1440]
 let deadline:Double
 init?(minutes:Int,now:Double) {
  guard Self.durations.contains(minutes) else { return nil }
  deadline=now+Double(minutes*60)
 }
 func remaining(at now:Double)->Int { max(0,Int(ceil(deadline-now))) }
 func isActive(at now:Double)->Bool { now<deadline }
 static func label(minutes:Int)->String {
  minutes<60 ? "\(minutes) Min" : "\(minutes/60) Hour\(minutes==60 ? "" : "s")"
 }
 func countdown(at now:Double)->String {
  let seconds=remaining(at:now)
  return String(format:"%d:%02d:%02d",seconds/3600,(seconds%3600)/60,seconds%60)
 }
}

// Hold a reduced ceiling for the session. Mining must not repeatedly trip its
// own load detector, then recover to the same overload 30 seconds later.
struct LoadGovernor {
 private(set) var ceiling=12
 private var highSince:Double?
 mutating func reset() { self=LoadGovernor() }
 mutating func observe(utilization:Double?,threads:Int,ready:Bool,now:Double) {
  guard ready,threads>1,let load=utilization,load.isFinite,load>0.85 else { highSince=nil; return }
  if let since=highSince,now-since>=5 {
   ceiling=min(ceiling,max(1,threads/2)); highSince=nil
  } else if highSince==nil { highSince=now }
 }
}
