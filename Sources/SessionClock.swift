import Foundation

struct SessionClock {
 let launchedAt:Double
 var startedDate:Date?
 private var start:Double?
 private var end:Double?
 private var lastSample:Double?
 private var wasHashing=false
 private(set) var hashingSeconds:Double=0
 init(launchedAt:Double=BoostClock.now) { self.launchedAt=launchedAt }
 mutating func begin(date:Date=Date(),at:Double=BoostClock.now) {
  startedDate=date;start=at;end=nil;lastSample=at;wasHashing=false;hashingSeconds=0
 }
 mutating func sample(at:Double=BoostClock.now,hashing:Bool) {
  if end==nil,let previous=lastSample,wasHashing {
   let delta=max(0,at-previous)
   // A long scheduling gap can represent system sleep. Never count it as hashing.
   if delta<=10 { hashingSeconds+=delta }
  }
  lastSample=at;wasHashing=hashing && end==nil
 }
 mutating func stop(at:Double=BoostClock.now) { sample(at:at,hashing:false);if start != nil && end==nil { end=at } }
 func elapsed(at:Double=BoostClock.now)->Double { guard let start=start else { return 0 };return max(0,(end ?? at)-start) }
 func uptime(at:Double=BoostClock.now)->Double { max(0,at-launchedAt) }
 static func duration(_ seconds:Double)->String {
  let n=Int(max(0,seconds.isFinite ? seconds : 0));let d=n/86400,h=n/3600%24,m=n/60%60,s=n%60
  if d>0 { return "\(d)d \(h)h \(m)m \(s)s" }
  if h>0 { return "\(h)h \(m)m \(s)s" }
  if m>0 { return "\(m)m \(s)s" }
  return "\(s)s"
 }
}
