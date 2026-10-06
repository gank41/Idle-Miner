import Foundation
import AppKit
@main struct Integration {
 static func main() throws {
  let resources=URL(fileURLWithPath:CommandLine.arguments[1])
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent("idle-miner-engine-test-"+UUID().uuidString)
  let engine=Engine(resources:resources,folder:temp)
  var exited=false; var output=false; var exitRequested=false; var initializations=0; var phase=0; var changedAt=Date(); var switchTimes=[Double](); var fault:String?
  engine.onFault={ fault=$0 }
  engine.onLine={ line in
   if line.contains("XMRig") { output=true }
   if line.contains("init dataset") { initializations += 1 }
   if phase==1 && line.contains("READY threads 2/2 ") { switchTimes.append(Date().timeIntervalSince(changedAt)); phase=2 }
   else if phase==3 && line.contains("READY threads 1/1 ") { switchTimes.append(Date().timeIntervalSince(changedAt)); phase=4 }
  }
  engine.onExit={ _,requested in exited=true; exitRequested=requested }
  try engine.start(settings:Settings(),threads:1,benchmark:true)
  let owner=engine.process!.processIdentifier
  let start=Date(); var stopped=false
  while !exited && Date().timeIntervalSince(start)<100 {
   RunLoop.main.run(until:Date().addingTimeInterval(0.1))
   engine.checkTransitionTimeout()
   if phase==0 && engine.ready { phase=1; changedAt=Date(); try engine.changeThreads(to:2) }
   else if phase==2 { phase=3; changedAt=Date(); try engine.changeThreads(to:1) }
   else if phase==4 && !stopped { stopped=true; engine.stop() }
   if fault != nil { engine.stop() }
  }
  guard fault==nil,phase==4,initializations==1,switchTimes.allSatisfy({$0<5}) else { engine.stop(); print("FAIL: reload / thread limits / retained dataset",fault ?? "",phase,initializations,switchTimes); exit(1) }
  guard exited && exitRequested && !engine.running else { engine.stop(); print("FAIL: engine did not stop"); exit(1) }
  guard output else { print("FAIL: startup output not delivered"); exit(1) }
  guard (try FileManager.default.contentsOfDirectory(at:temp,includingPropertiesForKeys:nil)).allSatisfy({$0.pathExtension != "json"}) else { print("FAIL: ephemeral config not removed"); exit(1) }
  print("PASS: actual offline 1→2→1 threads; one dataset initialization; reload seconds \(switchTimes); same supervisor \(owner); Stop/config cleanup")
 }
}
