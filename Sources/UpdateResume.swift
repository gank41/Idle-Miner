import Foundation
import Darwin

struct UpdateResumePlan {
 let primaryCoin:String
 let currencies:[String:Bool]
}

// Only a successful Sparkle relaunch arms this short-lived receipt. It contains
// process/currency intent only; wallets and settings remain in their own store.
final class UpdateResumeStore {
 private struct State:Codable { let coin:String;let enabled:Bool }
 private struct Receipt:Codable {
  let schema:Int
  let id:UUID
  let bundlePath:String
  let sourceBuild:String
  let targetBuild:String
  let targetVersion:String
  let created:Date
  let primaryProfile:String
  let expected:[String:Int32]
  var states:[String:State]
  var finalized:Bool
  var armed:Bool
 }
 private let directory:URL
 private var receiptURL:URL { directory.appendingPathComponent("receipt.json") }
 private var transaction:UUID?
 init(base:URL) { directory=base.appendingPathComponent("UpdateResume",isDirectory:true) }
 private static func path(_ url:URL)->String { url.resolvingSymlinksInPath().standardizedFileURL.path }
 private func failure()->Error { MinerError.message("The update's previous mining state could not be captured safely. The update was cancelled. Try again after closing other Idle Miner windows.") }
 private func check(_ url:URL,directory:Bool)throws {
  var st=stat()
  guard lstat(url.path,&st)==0,st.st_uid==getuid(),st.st_mode & 0o777 == (directory ? 0o700:0o600),st.st_mode & S_IFMT == (directory ? S_IFDIR:S_IFREG),directory || st.st_nlink==1 else { throw failure() }
 }
 private func locked<T>(_ body:()throws->T)throws->T {
  do { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
  catch { throw failure() }
  try check(directory,directory:true)
  let lockURL=directory.appendingPathComponent("transaction.lock")
  let fd=open(lockURL.path,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0o600)
  guard fd>=0 else { throw failure() };defer { close(fd) }
  var st=stat()
  guard fstat(fd,&st)==0,st.st_uid==getuid(),st.st_mode & 0o777==0o600,st.st_mode & S_IFMT==S_IFREG,st.st_nlink==1,flock(fd,LOCK_EX)==0 else { throw failure() }
  defer { flock(fd,LOCK_UN) }
  return try body()
 }
 private func read(now:Date?)throws->Receipt? {
  var st=stat()
  if lstat(receiptURL.path,&st) != 0 { if errno==ENOENT { return nil };throw failure() }
  try check(receiptURL,directory:false)
  let fd=open(receiptURL.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
  guard fd>=0 else { throw failure() };defer { close(fd) }
  var opened=stat()
  guard fstat(fd,&opened)==0,opened.st_ino==st.st_ino,opened.st_dev==st.st_dev,opened.st_size>0,opened.st_size<=16384 else { throw failure() }
  let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
  let bytes=try handle.read(upToCount:16385) ?? Data()
  guard bytes.count<=16384,let receipt=try? JSONDecoder().decode(Receipt.self,from:bytes),valid(receipt,now:now ?? receipt.created) else { throw failure() }
  return receipt
 }
 private func valid(_ r:Receipt,now:Date)->Bool {
  let age=now.timeIntervalSince(r.created)
  let profiles=Set(["default"]+Settings.coins)
  return r.schema==1 && age>=0 && age<=3600 && r.bundlePath.hasPrefix("/") &&
   Int(r.sourceBuild).map{$0>0}==true && Int(r.targetBuild).map{$0>(Int(r.sourceBuild) ?? Int.max)}==true &&
   !r.targetVersion.isEmpty && r.targetVersion.count<=64 && profiles.contains(r.primaryProfile) &&
   !r.expected.isEmpty && r.expected.count<=5 && r.expected[r.primaryProfile] != nil &&
   r.expected.allSatisfy{profiles.contains($0.key) && $0.value>1} && Set(r.expected.values).count==r.expected.count &&
   r.states.allSatisfy{r.expected[$0.key] != nil && Settings.coins.contains($0.value.coin)} &&
   (!r.finalized || r.states.count==r.expected.count) && (!r.armed || r.finalized)
 }
 private func write(_ receipt:Receipt)throws {
  // Atomic replacement starts private as well, including the temporary file.
  let temporary=directory.appendingPathComponent(".receipt-\(UUID())")
  let fd=open(temporary.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
  guard fd>=0 else { throw failure() }
  defer { close(fd);try? FileManager.default.removeItem(at:temporary) }
  let data=try JSONEncoder().encode(receipt)
  try FileHandle(fileDescriptor:fd,closeOnDealloc:false).write(contentsOf:data)
  guard fsync(fd)==0,rename(temporary.path,receiptURL.path)==0 else { throw failure() }
 }
 func begin(bundleURL:URL,sourceBuild:String,targetBuild:String,targetVersion:String,primaryProfile:String,expected:[String:Int32],now:Date=Date())throws {
  try locked {
   let r=Receipt(schema:1,id:UUID(),bundlePath:Self.path(bundleURL),sourceBuild:sourceBuild,targetBuild:targetBuild,targetVersion:targetVersion,created:now,primaryProfile:primaryProfile,expected:expected,states:[:],finalized:false,armed:false)
   guard valid(r,now:now) else { throw failure() }
   try write(r);transaction=r.id
  }
 }
 func acknowledge(bundleURL:URL,sourceBuild:String,profile:String,pid:Int32,coin:String,enabled:Bool,now:Date=Date())throws {
  try locked {
   guard var r=try read(now:now) else { return }
   guard r.bundlePath==Self.path(bundleURL),r.sourceBuild==sourceBuild,r.expected[profile]==pid,!r.finalized else { return }
   guard Settings.coins.contains(coin) else { throw failure() }
   if r.states[profile]==nil { r.states[profile]=State(coin:coin,enabled:enabled);try write(r) }
  }
 }
 func finalize(now:Date=Date())throws {
  try locked {
   guard var r=try read(now:now),r.id==transaction,r.states.count==r.expected.count else { throw failure() }
   r.finalized=true;try write(r)
  }
 }
 @discardableResult func arm(now:Date=Date())throws->UUID {
  try locked {
   guard var r=try read(now:now),r.id==transaction,r.finalized else { throw failure() }
   r.armed=true;try write(r);return r.id
  }
 }
 func cancel()throws {
  try locked {
   // A stale controller must never erase a newer update's transaction.
   guard let id=transaction else { return }
   if let r=try read(now:nil),r.id==id { try FileManager.default.removeItem(at:receiptURL) }
   transaction=nil
  }
 }
 func controllerCapability(bundleURL:URL,sourceBuild:String,pid:Int32,now:Date=Date())throws->UUID? {
  try locked {
   guard let r=try read(now:now),r.armed,r.bundlePath==Self.path(bundleURL),r.sourceBuild==sourceBuild,r.expected.values.contains(pid) else { return nil }
   return r.id
  }
 }
 func relaunchCapability(bundleURL:URL,build:String,version:String,now:Date=Date())throws->UUID? {
  try locked {
   guard let r=try read(now:now),r.armed,r.bundlePath==Self.path(bundleURL),r.targetBuild==build,r.targetVersion==version else { return nil }
   return r.id
  }
 }
 func discard(capability:UUID)throws {
  try locked {
   if let r=try read(now:nil),r.id==capability { try FileManager.default.removeItem(at:receiptURL) }
  }
 }
 func consume(bundleURL:URL,build:String,version:String,loginLaunch:Bool,capability:UUID?=nil,now:Date=Date())throws->UpdateResumePlan? {
  try locked {
   guard let r=try read(now:now),r.bundlePath==Self.path(bundleURL) else { return nil }
   // Delete under the same lock before any launch side effect: no later manual
   // launch can replay this state, including after a crash during restoration.
   try FileManager.default.removeItem(at:receiptURL)
   guard !loginLaunch,capability==r.id,r.armed,r.targetBuild==build,r.targetVersion==version,let primary=r.states[r.primaryProfile] else { return nil }
   var currencies=[String:Bool]()
   for state in r.states.values { currencies[state.coin]=(currencies[state.coin] ?? false) || state.enabled }
   return UpdateResumePlan(primaryCoin:primary.coin,currencies:currencies)
  }
 }
}
