import Foundation
import Darwin

struct AvailableUpdate:Codable,Equatable,Sendable {
 let version:String
 let build:Int
 var valid:Bool { !version.isEmpty && version.count<=64 && !version.unicodeScalars.contains{$0.value<32} && build>0 }
}

// Shared per-user metadata only. No wallet, mining state or credentials.
final class AutomaticUpdateStore {
 private struct Record:Codable {
  var schema=1
  var lastAttempt:TimeInterval?
  var lastNotified:AvailableUpdate?
  var available:AvailableUpdate?
 }
 private let directory:URL
 private var file:URL { directory.appendingPathComponent("state.json") }
 init(base:URL) { directory=base.appendingPathComponent("AutomaticUpdates",isDirectory:true) }
 static func interval(_ frequency:String)->TimeInterval? { frequency=="daily" ? 86400 : frequency=="weekly" ? 604800:nil }
 private func failed()->Error { MinerError.message("Automatic update preferences could not be read safely. Check for updates manually.") }
 private func read()throws->Record {
  var st=stat()
  if lstat(file.path,&st) != 0 { if errno==ENOENT { return Record() };throw failed() }
  guard st.st_uid==getuid(),st.st_mode & S_IFMT==S_IFREG,st.st_mode & 0o777==0o600,st.st_size>0,st.st_size<=16384 else { throw failed() }
  let record=try JSONDecoder().decode(Record.self,from:Data(contentsOf:file))
  guard record.schema==1,record.lastAttempt.map({$0.isFinite && $0>=0}) ?? true,record.lastNotified?.valid ?? true,record.available?.valid ?? true else { throw failed() }
  return record
 }
 private func write(_ record:Record)throws {
  try JSONEncoder().encode(record).write(to:file,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
 }
 private func transaction<T>(_ action:()throws->T)throws->T {
  try FileManager.default.createDirectory(at:directory.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  // Foundation applies directory attributes after mkdir; another currency can
  // observe a temporary 0755 mode. Create this private leaf atomically instead.
  if mkdir(directory.path,0o700) != 0 && errno != EEXIST { throw failed() }
  var st=stat()
  guard lstat(directory.path,&st)==0,st.st_uid==getuid(),st.st_mode & S_IFMT==S_IFDIR,st.st_mode & 0o777==0o700 else { throw failed() }
  let lease=try FileLease(url:directory.appendingPathComponent("state.lock"),nonblocking:false)
  defer { withExtendedLifetime(lease){} }
  return try action()
 }
 func claimDue(enabled:Bool,frequency:String,now:TimeInterval=Date().timeIntervalSince1970)throws->Bool {
  guard enabled,let interval=Self.interval(frequency),now.isFinite,now>=0 else { return false }
  return try transaction {
   var record=try read()
   if let last=record.lastAttempt,now>=last,now-last<interval { return false }
   // Write before networking: all currency instances and failures share this
   // attempt. A wall-clock rollback permits one fresh anchor, never a burst.
   record.lastAttempt=now;try write(record);return true
  }
 }
 func recordAvailable(_ update:AvailableUpdate,installedBuild:Int,markNotified:Bool=true)throws->Bool {
  guard update.valid,update.build>installedBuild else { return false }
  return try transaction {
   var record=try read();let notify=record.lastNotified.map{update.build>$0.build} ?? true
   record.available=update;if notify && markNotified { record.lastNotified=update };try write(record);return notify
  }
 }
 func availableUpdate(installedBuild:Int)throws->AvailableUpdate? {
  let update=try read().available
  return update.map{$0.build>installedBuild} == true ? update:nil
 }
 func retryNotification(_ update:AvailableUpdate)throws {
  try transaction { var record=try read();if record.lastNotified==update { record.lastNotified=nil;try write(record) } }
 }
 func clearAvailable()throws {
  // An ordinary no-update check need not create an empty preference directory.
  guard FileManager.default.fileExists(atPath:file.path) else { return }
  try transaction { var record=try read();record.available=nil;try write(record) }
 }
}
