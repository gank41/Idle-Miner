import Foundation
import CryptoKit
import Darwin

struct Settings: Codable {
 static let coins=["LTC","DOGE","BTC","ETH"]
 var coin="LTC"
 var address=""
 var idleThreads=4
 var pauseWhileActive=false
 var idleSeconds:Double=300
 var wallets=[String:String]()
 var showDock=false
 var showMenuBar=true
 var startMiningAtLogin=false
 var automaticUpdateChecks=false
 var updateCheckFrequency="daily"
 init() {}
 enum CodingKeys:String,CodingKey { case coin,address,idleThreads,pauseWhileActive,idleSeconds,wallets,showDock,showMenuBar,startMiningAtLogin,automaticUpdateChecks,updateCheckFrequency }
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
  startMiningAtLogin=try c.decodeIfPresent(Bool.self,forKey:.startMiningAtLogin) ?? false
  automaticUpdateChecks=try c.decodeIfPresent(Bool.self,forKey:.automaticUpdateChecks) ?? false
  updateCheckFrequency=try c.decodeIfPresent(String.self,forKey:.updateCheckFrequency) ?? "daily"
  if !["daily","weekly"].contains(updateCheckFrequency) { automaticUpdateChecks=false;updateCheckFrequency="daily" }
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
  guard ["daily","weekly"].contains(updateCheckFrequency) else { throw MinerError.message("Choose Daily or Weekly for update checks.") }
  guard showDock || showMenuBar else { throw MinerError.message("Keep the Dock icon, menu bar icon, or both enabled.") }
  guard address.isEmpty || Wallet.valid(address,coin:coin) else { throw MinerError.message("The address checksum or network does not match \(coin). Copy its native Receive address again.") }
  for (currency,value) in wallets {
   guard Self.coins.contains(currency),value.isEmpty || Wallet.valid(value,coin:currency) else { throw MinerError.message("Check the saved \(currency) native-network Receive address.") }
  }
  return self
 }
 func save(to url:URL,walletChanges:[String:String]?=nil,updateDefaultCoin:Bool=true,startMiningAtLoginChange:Bool?=nil,automaticUpdateChecksChange:Bool?=nil,updateCheckFrequencyChange:String?=nil)throws {
  _=try validated()
  try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let lock=try FileLease(url:url.deletingLastPathComponent().appendingPathComponent("settings.lock"),nonblocking:false)
  defer { withExtendedLifetime(lock){} }
  let previous=try Self.load(from:url)
  var stored=self;stored.wallets=previous.wallets
  stored.startMiningAtLogin=startMiningAtLoginChange ?? previous.startMiningAtLogin
  stored.automaticUpdateChecks=automaticUpdateChecksChange ?? previous.automaticUpdateChecks
  stored.updateCheckFrequency=updateCheckFrequencyChange ?? previous.updateCheckFrequency
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
  if coin == "ETH" { return EthereumAddress.valid(s) }
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

// ERC-55 uses Ethereum Keccak-256, whose padding differs from SHA3-256.
enum EthereumAddress {
 static func valid(_ address:String)->Bool {
  guard address.hasPrefix("0x"),address.utf8.count==42 else { return false }
  let body=String(address.dropFirst(2))
  guard body.utf8.allSatisfy({(48...57).contains($0)||(65...70).contains($0)||(97...102).contains($0)}),body.contains(where:{$0 != "0"}) else { return false }
  if body==body.lowercased() || body==body.uppercased() { return true }
  let lower=body.lowercased(),hash=keccak256(Array(lower.utf8))
  for (i,ch) in body.utf8.enumerated() where (65...70).contains(ch)||(97...102).contains(ch) {
   let nibble=i%2==0 ? hash[i/2]>>4 : hash[i/2]&15
   if ((65...70).contains(ch)) != (nibble>=8) { return false }
  }
  return true
 }
 static func keccak256(_ input:[UInt8])->[UInt8] {
  let rotations=[0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14]
  let constants:[UInt64]=[0x0000000000000001,0x0000000000008082,0x800000000000808a,0x8000000080008000,0x000000000000808b,0x0000000080000001,0x8000000080008081,0x8000000000008009,0x000000000000008a,0x0000000000000088,0x0000000080008009,0x000000008000000a,0x000000008000808b,0x800000000000008b,0x8000000000008089,0x8000000000008003,0x8000000000008002,0x8000000000000080,0x000000000000800a,0x800000008000000a,0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
  func rotate(_ x:UInt64,_ n:Int)->UInt64 { n==0 ? x : (x<<n)|(x>>(64-n)) }
  var bytes=input+[UInt8](repeating:0,count:136-input.count%136)
  bytes[input.count]=1;bytes[bytes.count-1] |= 0x80
  var a=[UInt64](repeating:0,count:25)
  for offset in stride(from:0,to:bytes.count,by:136) {
   for i in 0..<136 { a[i/8] ^= UInt64(bytes[offset+i])<<((i%8)*8) }
   for constant in constants {
    var c=[UInt64](repeating:0,count:5),d=c,b=a
    for x in 0..<5 { c[x]=a[x]^a[x+5]^a[x+10]^a[x+15]^a[x+20] }
    for x in 0..<5 { d[x]=c[(x+4)%5]^rotate(c[(x+1)%5],1) }
    for y in 0..<5 { for x in 0..<5 { a[x+5*y] ^= d[x] } }
    for y in 0..<5 { for x in 0..<5 { b[y+5*((2*x+3*y)%5)]=rotate(a[x+5*y],rotations[x+5*y]) } }
    for y in 0..<5 { for x in 0..<5 { a[x+5*y]=b[x+5*y]^((~b[(x+1)%5+5*y])&b[(x+2)%5+5*y]) } }
    a[0] ^= constant
   }
  }
  return (0..<32).map { UInt8((a[$0/8]>>(($0%8)*8))&255) }
 }
}
enum StartupPlan {
 static func currencies(_ settings:Settings,loginLaunch:Bool,loginEnabled:Bool,profile:String="default")->[String] {
  guard loginLaunch,loginEnabled,settings.startMiningAtLogin,profile=="default" else { return [] }
  let ordered=[settings.coin]+Settings.coins.filter{$0 != settings.coin}
  return ordered.filter { Wallet.valid(settings.wallets[$0] ?? ($0==settings.coin ? settings.address : ""),coin:$0) }
 }
}
