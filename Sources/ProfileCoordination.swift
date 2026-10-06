import Foundation
import Darwin

// Locks use stable files: atomic replacement is reserved for metadata/configs.
final class FileLease {
 let descriptor:Int32
 init(url:URL,nonblocking:Bool=true)throws {
  descriptor=open(url.path,O_RDWR|O_CREAT|O_CLOEXEC,0o600)
  guard descriptor>=0 else { throw MinerError.message("Could not open the app's coordination lock.") }
  if flock(descriptor,LOCK_EX | (nonblocking ? LOCK_NB : 0)) != 0 {
   close(descriptor);throw MinerError.message("This Idle Miner profile is already open.")
  }
 }
 deinit { flock(descriptor,LOCK_UN);close(descriptor) }
}
private struct WorkerReservation:Codable {
 var pid:Int32
 var requested:Int
 var reserved:Int
 var coin:String?
}
final class ProfileCoordinator {
 let base:URL
 let profile:String
 private let directory:URL
 private let instance:FileLease
 private var currency:FileLease?
 private var currencyName:String?
 private(set) var peers=1
 static func profileArgument(_ arguments:[String])->String {
  let raw=arguments.first(where:{$0.hasPrefix("--profile=")}).map{String($0.dropFirst(10))} ?? "default"
  return Settings.coins.contains(raw) ? raw : "default"
 }
 init(base:URL,profile:String)throws {
  guard profile=="default" || Settings.coins.contains(profile) else { throw MinerError.message("Unknown mining profile.") }
  self.base=base;self.profile=profile;directory=base.appendingPathComponent("Coordination",isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  instance=try FileLease(url:directory.appendingPathComponent("instance-\(profile).lock"))
  // Do not overwrite a crashed controller's reservation while its supervised
  // engine is still shutting down.
  let oldEngine=try FileLease(url:engineLeaseURL)
  withExtendedLifetime(oldEngine){}
  _=try quota(requested:0,actual:0,budget:4,cores:ProcessInfo.processInfo.activeProcessorCount)
 }
 var engineLeaseURL:URL { directory.appendingPathComponent("engine-\(profile).lock") }
 var stateFolder:URL { profile=="default" ? base : base.appendingPathComponent("Profiles/\(profile)",isDirectory:true) }
 func claimCoin(_ coin:String)->Bool {
  if currencyName==coin { return true }
  guard Settings.coins.contains(coin),let lease=try? FileLease(url:directory.appendingPathComponent("currency-\(coin).lock")) else { return false }
  do {
   let transaction=try FileLease(url:directory.appendingPathComponent("transaction.lock"),nonblocking:false)
   defer { withExtendedLifetime(transaction){} }
   for key in ["default"]+Settings.coins where key != profile {
    if held("engine-\(key).lock"),let bytes=try? Data(contentsOf:metadata(key)),let row=try? JSONDecoder().decode(WorkerReservation.self,from:bytes),row.coin==coin { return false }
   }
   currency=lease;currencyName=coin;return true
  } catch { return false }
 }
 func releaseCoin() { currency=nil;currencyName=nil }
 private func held(_ name:String)->Bool {
  let fd=open(directory.appendingPathComponent(name).path,O_RDWR|O_CLOEXEC)
  guard fd>=0 else { return false };defer { close(fd) }
  if flock(fd,LOCK_EX|LOCK_NB)==0 { flock(fd,LOCK_UN);return false }
  return true
 }
 private func metadata(_ key:String)->URL { directory.appendingPathComponent("instance-\(key).json") }
 private func store(_ value:WorkerReservation,key:String)throws {
  let url=metadata(key);try JSONEncoder().encode(value).write(to:url,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
 }
 // A request persists while waiting. Reservations decrease only after the
 // engine acknowledges its smaller profile or exits; increases reserve first.
 func quota(requested:Int,actual:Int,budget:Int,cores:Int)throws->Int {
  let transaction=try FileLease(url:directory.appendingPathComponent("transaction.lock"),nonblocking:false)
  defer { withExtendedLifetime(transaction){} }
  let cap=min(max(1,budget),max(1,cores-2),12)
  let request=min(max(0,requested),cap)
  var rows=[profile:WorkerReservation(pid:getpid(),requested:request,reserved:max(0,actual),coin:currencyName)]
  for key in ["default"]+Settings.coins where key != profile {
   let controllerHeld=held("instance-\(key).lock")
   let engineHeld=held("engine-\(key).lock")
   guard controllerHeld || engineHeld else { continue }
   if let bytes=try? Data(contentsOf:metadata(key)),var row=try? JSONDecoder().decode(WorkerReservation.self,from:bytes),row.pid>1,(0...12).contains(row.requested),(0...12).contains(row.reserved) {
    if !controllerHeld || kill(row.pid,0) != 0 { row.requested=0 }
    rows[key]=row
   } else { rows[key]=WorkerReservation(pid:0,requested:0,reserved:cap,coin:nil) }
  }
  peers=rows.count
  var shares=rows.mapValues{_ in 0};var left=cap
  let keys=rows.keys.sorted()
  while left>0 {
   var progress=false
   for key in keys where left>0 {
    if shares[key,default:0]<rows[key]!.requested { shares[key,default:0]+=1;left-=1;progress=true }
   }
   if !progress { break }
  }
  let occupied=rows.filter{$0.key != profile}.values.reduce(0){$0+$1.reserved}
  let grant=min(shares[profile,default:0],max(0,cap-occupied))
  try store(WorkerReservation(pid:getpid(),requested:request,reserved:max(actual,grant),coin:currencyName),key:profile)
  return grant
 }
 static func existingPID(base:URL,profile:String)->pid_t? {
  let directory=base.appendingPathComponent("Coordination")
  let fd=open(directory.appendingPathComponent("instance-\(profile).lock").path,O_RDWR|O_CLOEXEC)
  guard fd>=0 else { return nil };defer { close(fd) }
  if flock(fd,LOCK_EX|LOCK_NB)==0 { flock(fd,LOCK_UN);return nil }
  guard let bytes=try? Data(contentsOf:directory.appendingPathComponent("instance-\(profile).json")),let row=try? JSONDecoder().decode(WorkerReservation.self,from:bytes),kill(row.pid,0)==0 else { return nil }
  return row.pid
 }
}
