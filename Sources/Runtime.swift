import AppKit
import IOKit.ps
import CoreGraphics
import Darwin

final class Sensors {
 var sleeping=false
 var pressure=false
 var lastWake=Date()
 private var previous:[UInt32]?
 private var memorySource:DispatchSourceMemoryPressure?
 init() {
  var level:Int32=0; var size=MemoryLayout.size(ofValue:level)
  if sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&size,nil,0)==0 { pressure = level>1 }
  let source=DispatchSource.makeMemoryPressureSource(eventMask:[.normal,.warning,.critical],queue:.main)
  source.setEventHandler { [weak self] in self?.pressure = !source.data.contains(.normal) }
  source.resume(); memorySource=source
 }
 func sample()->Environment {
  var e=Environment(); e.cores=ProcessInfo.processInfo.activeProcessorCount
  let idle=CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)
  e.idleSeconds=idle.isFinite ? max(0,min(idle,Date().timeIntervalSince(lastWake))) : 0
  e.thermal=ProcessInfo.processInfo.thermalState.rawValue; e.memoryPressure=pressure; e.sleeping=sleeping
  if let snapshot=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let type=IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() { e.onAC = (type as String)==kIOPSACPowerValue } else { e.onAC=false }
  var info=host_cpu_load_info(); var count=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size/MemoryLayout<integer_t>.size)
  let result=withUnsafeMutablePointer(to:&info) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics(mach_host_self(),HOST_CPU_LOAD_INFO,$0,&count) } }
  if result==KERN_SUCCESS {
   let now=[info.cpu_ticks.0,info.cpu_ticks.1,info.cpu_ticks.2,info.cpu_ticks.3]
   if let old=previous {
    let delta=zip(now,old).map{Double($0 &- $1)}; let total=delta.reduce(0,+)
    if total>0 { e.cpuUtilization=1-delta[2]/total; e.busy=e.cpuUtilization!>0.85 }
   }
   previous=now
  }
  return e
 }
}

final class Engine {
 var onLine:((String)->Void)?
 var onExit:((Int32,Bool)->Void)?
 private(set) var process:Process?
 private(set) var threads=0
 private(set) var reservedThreads=0
 private(set) var logURL:URL?
 private var stopping=false
 private(set) var ready=false
 private var changingUntil:Double?
 private var activeSettings=Settings()
 private var offline=false
 var onFault:((String)->Void)?
 var isChanging:Bool { changingUntil != nil }
 private var pipe:Pipe?
 private var lines=LineBuffer()
 private var handle:FileHandle?
 private var loggedBytes=0
 private var configURL:URL?
 var leaseURL:URL?
 let resources:URL
 let folder:URL
 init(resources:URL,folder:URL) { self.resources=resources; self.folder=folder }
 var running:Bool { process != nil }
 var isStopping:Bool { stopping }
 func start(settings:Settings,threads:Int,benchmark:Bool) throws {
  guard process==nil else { return }
  defer { if process==nil { try? handle?.close(); handle=nil; if let url=configURL { try? FileManager.default.removeItem(at:url) }; configURL=nil } }
  activeSettings=settings; offline=benchmark; ready=false; changingUntil=nil
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let files=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.creationDateKey])) ?? []
  let logs=files.filter{$0.pathExtension=="log"}.sorted{ $0.lastPathComponent>$1.lastPathComponent }
  for old in logs.dropFirst(9) { try? FileManager.default.removeItem(at:old) }
  let id="\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
  let config=folder.appendingPathComponent(id+".json")
  try EngineConfig.make(settings,threads:threads,benchmark:benchmark).write(to:config,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:config.path)
  configURL=config
  let log=folder.appendingPathComponent(id+".log")
  FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
  handle=try FileHandle(forWritingTo:log); logURL=log; loggedBytes=0; lines=LineBuffer()
  let child=Process(); let output=Pipe()
  child.executableURL=resources.appendingPathComponent("miner-supervisor")
  child.currentDirectoryURL=folder
  child.arguments=[String(getpid())]+(leaseURL.map{["--lease="+$0.path]} ?? [])+[resources.appendingPathComponent("xmrig").path,"-c",config.path,"--no-color"]
  child.standardInput=FileHandle.nullDevice; child.standardOutput=output; child.standardError=output
  output.fileHandleForReading.readabilityHandler = { [weak self,weak child] input in
   let data=input.availableData
   if data.isEmpty { input.readabilityHandler=nil; return }
   DispatchQueue.main.async { guard let self=self, let child=child, self.process === child else { return }; self.receive(data) }
  }
  child.terminationHandler = { [weak self] ended in
   DispatchQueue.main.async {
    guard let self=self, self.process === ended else { return }
    self.pipe?.fileHandleForReading.readabilityHandler=nil
    let requested=self.stopping
    self.process=nil; self.pipe=nil; self.threads=0; self.reservedThreads=0; self.ready=false; self.changingUntil=nil
    try? self.handle?.close(); self.handle=nil
    if let url=self.configURL { try? FileManager.default.removeItem(at:url) }; self.configURL=nil
    self.onExit?(ended.terminationStatus,requested)
   }
  }
  self.process=child; self.pipe=output; self.threads=threads; self.reservedThreads=threads; stopping=false
  do { try child.run() } catch {
   output.fileHandleForReading.readabilityHandler=nil; process=nil; pipe=nil; self.threads=0; self.reservedThreads=0
   try? handle?.close(); handle=nil; try? FileManager.default.removeItem(at:config)
   throw error
  }
 }
 private func receive(_ data:Data) {
  if loggedBytes<2_000_000 { let chunk=data.prefix(2_000_000-loggedBytes); try? handle?.write(contentsOf:chunk); loggedBytes += chunk.count }
  for line in lines.feed(data) {
   if line.contains("READY threads ") {
    if line.contains("READY threads \(threads)/\(threads) ") { ready=true; reservedThreads=threads; changingUntil=nil }
    else { onFault?("Engine reported an unexpected thread count. Mining stopped for safety."); stop() }
   }
   onLine?(line)
  }
 }
 func changeThreads(to count:Int) throws {
  guard ready,!stopping,!isChanging,count != threads,let url=configURL else { return }
  try EngineConfig.make(activeSettings,threads:count,benchmark:offline).write(to:url,options:.atomic)
  // The same 0600 file is replaced atomically. XMRig's watcher reopens it.
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
  reservedThreads=max(reservedThreads,count); threads=count; ready=false; changingUntil=BoostClock.now+15
 }
 func checkTransitionTimeout(now:Double=BoostClock.now) {
  if let end=changingUntil,now>=end {
   changingUntil=nil; onFault?("Thread change was not confirmed. Mining stopped; check the log."); stop()
  }
 }
 func stop() {
  guard let child=process,child.isRunning,!stopping else { return }
  stopping=true; child.interrupt()
  // Supervisor stops only its own engine group, including if this app crashes.
 }
}
