import Foundation
@main struct FaultTests {
 static func main() throws {
  let base=FileManager.default.temporaryDirectory.appendingPathComponent("idle-fault-"+UUID().uuidString)
  let resources=base.appendingPathComponent("resources"); try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true)
  try FileManager.default.copyItem(at:URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("miner-supervisor"),to:resources.appendingPathComponent("miner-supervisor"))
  func wait(_ condition:()->Bool,seconds:Double) ->Bool {
   let until=Date().addingTimeInterval(seconds)
   while !condition() && Date()<until { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
   return condition()
  }
  for wrongCount in [true,false] {
   let fake=resources.appendingPathComponent("xmrig")
   try Data("#!/bin/sh\necho 'cpu READY threads \(wrongCount ? "16/16" : "1/1") (1)'\nexec /bin/sleep 30\n".utf8).write(to:fake)
   try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:fake.path)
   let engine=Engine(resources:resources,folder:base.appendingPathComponent(wrongCount ? "wrong" : "timeout"));var fault:String?;var exited=false
   engine.onFault={fault=$0};engine.onExit={_,_ in exited=true}
   try engine.start(settings:Settings(),threads:1,benchmark:true)
   if wrongCount { precondition(wait({exited},seconds:6) && fault?.contains("unexpected thread count")==true) }
   else {
    precondition(wait({engine.ready},seconds:3));try engine.changeThreads(to:2)
    precondition(engine.isChanging);engine.checkTransitionTimeout(now:BoostClock.now+16)
    precondition(wait({exited},seconds:6) && fault?.contains("not confirmed")==true)
   }
   precondition(!engine.running)
  }
  print("PASS: unexpected thread count and missing reload acknowledgement stop the owned engine")
 }
}
