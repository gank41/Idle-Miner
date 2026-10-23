import Foundation
import Darwin

struct MenuPeerSnapshot:Codable,Equatable {
 let pid:Int32
 let profile:String
 let coin:String
 let nonce:String
 let updated:TimeInterval
 let level:String
 let enabled:Bool
 let lines:[String]
 var rank:Int { level=="working" ? 3 : level=="issue" ? 2 : enabled ? 1 : 0 }
}
struct MenuPeerCommand:Codable {
 let pid:Int32
 let profile:String
 let coin:String
 let nonce:String
 let created:TimeInterval
 let action:String
 let minutes:Int?
}
// Local, per-user IPC only. No sockets, addresses, URLs or executable commands.
final class SharedMenuStore {
 static let actions:Set<String>=["stats","start","stop","boost","endBoost","settings","pool","log","quit"]
 let base:URL
 let profile:String
 let nonce=UUID().uuidString
 private let directory:URL
 private var owner:FileLease?
 private var lastPublish:TimeInterval = -Double.infinity
 private var lastContent=[String]()
 var ownsMenu:Bool { owner != nil }
 init(base:URL,profile:String)throws {
  guard profile=="default" || Settings.coins.contains(profile) else { throw MinerError.message("Unknown menu profile.") }
  self.base=base;self.profile=profile;directory=base.appendingPathComponent("SharedMenu",isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
 }
 @discardableResult func claimOwnership()->Bool {
  if owner==nil { owner=try? FileLease(url:directory.appendingPathComponent("owner.lock")) };return ownsMenu
 }
 func releaseOwnership() { owner=nil }
 private func write<T:Encodable>(_ value:T,to url:URL)throws {
  try JSONEncoder().encode(value).write(to:url,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
 }
 func publish(coin:String,level:String,enabled:Bool,lines:[String],now:TimeInterval=Date().timeIntervalSince1970)throws {
  guard Settings.coins.contains(coin),["working","issue","inactive"].contains(level) else { return }
  let safe=Array(lines.prefix(6)).map{String($0.prefix(256))}
  let content=[coin,level,enabled ? "yes":"no"]+safe
  guard content != lastContent || now-lastPublish>=3 || now<lastPublish else { return }
  let item=MenuPeerSnapshot(pid:getpid(),profile:profile,coin:coin,nonce:nonce,updated:now,level:level,enabled:enabled,lines:safe)
  try write(item,to:directory.appendingPathComponent("snapshot-\(profile).json"));lastContent=content;lastPublish=now
 }
 func snapshots(now:TimeInterval=Date().timeIntervalSince1970)->[MenuPeerSnapshot] {
  (["default"]+Settings.coins).compactMap { key in
   guard let data=try? Data(contentsOf:directory.appendingPathComponent("snapshot-\(key).json")),data.count<=8192,
    let item=try? JSONDecoder().decode(MenuPeerSnapshot.self,from:data),item.profile==key,Settings.coins.contains(item.coin),
    UUID(uuidString:item.nonce) != nil,item.pid>1,item.pid==ProfileCoordinator.existingPID(base:base,profile:key),
    item.updated.isFinite,(-2...12).contains(now-item.updated),["working","issue","inactive"].contains(item.level),
    item.lines.count<=6,item.lines.allSatisfy({$0.count<=256}) else { return nil }
   return item
  }
 }
 func send(_ target:MenuPeerSnapshot,action:String,minutes:Int?=nil,now:TimeInterval=Date().timeIntervalSince1970)throws {
  guard Self.actions.contains(action),action != "boost" || TimedBoost.durations.contains(minutes ?? 0),
    target.profile=="default" || Settings.coins.contains(target.profile),Settings.coins.contains(target.coin),
    UUID(uuidString:target.nonce) != nil,target.pid==ProfileCoordinator.existingPID(base:base,profile:target.profile) else { throw MinerError.message("That currency instance is no longer available.") }
  try write(MenuPeerCommand(pid:target.pid,profile:target.profile,coin:target.coin,nonce:target.nonce,created:now,action:action,minutes:minutes),to:directory.appendingPathComponent("command-\(target.profile)-\(UUID().uuidString).json"))
 }
 func commands(coin:String,now:TimeInterval=Date().timeIntervalSince1970)->[MenuPeerCommand] {
  let files=((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []).filter{$0.lastPathComponent.hasPrefix("command-\(profile)-") && $0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
  return files.prefix(64).compactMap { url in
   defer { try? FileManager.default.removeItem(at:url) }
   guard let data=try? Data(contentsOf:url),data.count<=4096,let command=try? JSONDecoder().decode(MenuPeerCommand.self,from:data),
    command.pid==getpid(),command.profile==profile,command.coin==coin,command.nonce==nonce,
    command.created.isFinite,(-2...15).contains(now-command.created),Self.actions.contains(command.action),
    command.action != "boost" || TimedBoost.durations.contains(command.minutes ?? 0) else { return nil }
   return command
  }.sorted { a,b in
   if a.created != b.created { return a.created<b.created }
   let priority=["start":1,"boost":2,"endBoost":3,"stop":8,"quit":9]
   return priority[a.action,default:0]<priority[b.action,default:0]
  }
 }
}
