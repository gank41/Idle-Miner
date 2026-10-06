import Foundation
import CoreFoundation

struct HashSample {
 let date:Date
 let rate:Double?
}
struct LocalMiningStats {
 var accepted=0
 var rejected=0
 var lastAccepted:Date?
 var sessionStarted=Date()
 var latestRate:Double?
 var rateUpdated:Date?
 var connection="No pool connection yet"
 var history=[HashSample]()
 var offline=false
 var donating=false
 var engineStartedAt:Date?
 var lastPositiveRateAt:Date?
 var poolConnected=false
 var connectionIssue:String?
 mutating func reset(now:Date=Date()) { self=LocalMiningStats(); sessionStarted=now }
 mutating func engineStarted(offline:Bool,now:Date=Date()) {
  self.offline=offline; donating=false; latestRate=nil; rateUpdated=nil
  engineStartedAt=now; lastPositiveRateAt=nil; poolConnected=false; connectionIssue=nil
  connection=offline ? "Offline benchmark · no earnings" : "Connecting to the mining pool…"
  append(rate:nil,now:now)
 }
 mutating func threadsChanged(now:Date=Date()) {
  latestRate=nil; rateUpdated=nil; lastPositiveRateAt=nil; engineStartedAt=now; append(rate:nil,now:now)
 }
 mutating func engineStopped(now:Date=Date()) {
  latestRate=nil; rateUpdated=nil; engineStartedAt=nil; lastPositiveRateAt=nil; poolConnected=false; connectionIssue=nil; connection="Engine stopped"; append(rate:nil,now:now)
 }
 mutating func consume(_ line:String,now:Date=Date()) {
  if line.contains("donate started") { donating=true }
  if line.contains("donate finished") { donating=false }
  if line.contains("new job from") && !donating && !offline {
   poolConnected=true; connectionIssue=nil; connection="Pool is sending mining jobs"
  }
  let lower=line.lowercased()
  if !offline && !donating && ["connect error","no active pools","login error","read error","write error","connection reset","connection refused","connection timed out","dns error","tls handshake failed","tls handshake error"].contains(where:{lower.contains($0)}) {
   poolConnected=false; connectionIssue="Pool connection interrupted · retrying"
   connection="Pool connection interrupted · retrying"; latestRate=nil; rateUpdated=nil; append(rate:nil,now:now)
  }
  if let range=line.range(of:"speed 10s/60s/15m "),let word=line[range.upperBound...].split(separator:" ").first {
   let value=Double(word)
   latestRate=value.flatMap{$0.isFinite && $0>=0 ? $0 : nil}; rateUpdated=now
   if let rate=latestRate,rate>0 { lastPositiveRateAt=now }
   append(rate:latestRate,now:now)
  }
  if !offline && !donating {
   if line.contains("accepted (") { accepted += 1; lastAccepted=now; poolConnected=true; connectionIssue=nil; connection="Pool accepted work from this Mac" }
   if line.contains("rejected (") { rejected += 1 }
  }
 }
 mutating func append(rate:Double?,now:Date) {
  history.append(HashSample(date:now,rate:rate))
  history.removeAll{$0.date<now.addingTimeInterval(-1800)}
  if history.count>360 { history.removeFirst(history.count-360) }
 }
 func currentRate(now:Date=Date())->Double? {
  guard let updated=rateUpdated,now.timeIntervalSince(updated)<=30 else { return nil }
  return latestRate
 }
}
struct PriceQuote {
 let coin:String
 let usd:Double
 let fetchedAt:Date
 static func parse(_ data:Data,coin:String,now:Date=Date()) throws ->PriceQuote {
  guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
        let d=root["data"] as? [String:Any],d["base"] as? String==coin,d["currency"] as? String=="USD",
        let number=StatsFormat.number(d["amount"]),number>0 else { throw StatsError.invalidResponse }
  return PriceQuote(coin:coin,usd:number,fetchedAt:now)
 }
 func isFresh(now:Date=Date())->Bool { now.timeIntervalSince(fetchedAt)<600 }
}
enum StatsError:LocalizedError {
 case invalidResponse, http(Int)
 var errorDescription:String? {
  switch self {
  case .invalidResponse: return "The service returned an unrecognized response."
  case .http(let code): return "The service is unavailable (HTTP \(code))."
  }
 }
}
enum StatsFormat {
 static func number(_ value:Any?)->Double? {
  let result:Double?
  if let text=value as? String { result=Double(text) }
  else if let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID() { result=n.doubleValue }
  else { result=nil }
  guard let result=result,result.isFinite,result>=0 else { return nil }; return result
 }
 static func amount(_ number:Double)->String { String(format:"%.8f",number) }
 static func usd(_ number:Double)->String {
  if number>0 && number<0.01 { return "<$0.01" }
  let f=NumberFormatter(); f.locale=Locale(identifier:"en_US"); f.numberStyle = .currency; f.currencyCode="USD"
  return f.string(from:NSNumber(value:number)) ?? String(format:"$%.2f",number)
 }
 static func time(_ date:Date?)->String {
  guard let date=date else { return "Not yet" }
  return DateFormatter.localizedString(from:date,dateStyle:.none,timeStyle:.medium)
 }
}

struct PoolSnapshot {
 let coin:String
 let balance:Double
 let payable:Double
 let paid:Double
 let rewards24h:Double?
 let threshold:Double
 let automatic:Bool?
 let payoutIssue:Bool
 let workerRate:Double?
 let workerOnline:Bool?
 let fetchedAt:Date
 var progress:Double { min(100,max(0,payable/threshold*100)) }
 var hasEarnings:Bool { balance>0 || paid>0 }
 func isFresh(now:Date=Date())->Bool { now.timeIntervalSince(fetchedAt)<600 }
 static func payload(_ data:Data)throws->[String:Any] {
  guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["success"] as? Bool==true,let d=root["data"] as? [String:Any] else { throw StatsError.invalidResponse }; return d
 }
 static func identifier(_ data:Data,address:String)throws->String {
  let d=try payload(data)
  guard d["address"] as? String==address,let id=d["uuid"] as? String,UUID(uuidString:id) != nil else { throw StatsError.invalidResponse }; return id
 }
 static func parse(addressData:Data,statsData:Data,workersData:Data?,coin:String,now:Date=Date())throws->PoolSnapshot {
  let a=try payload(addressData),s=try payload(statsData)
  guard s["coin"] as? String==coin,s["network"] as? String==coin,a["network"] as? String==coin,
        let balance=StatsFormat.number(s["balance"]),let paid=StatsFormat.number(s["paid"]),
        let payable=StatsFormat.number(a["balance_payable"]),let threshold=StatsFormat.number(s["payment_threshold"]),threshold>0 else { throw StatsError.invalidResponse }
  let flags=a["err_flags"] as? [String:Any] ?? [:]
  let issue=a["enabled"] as? Bool==false || flags.values.contains{($0 as? Bool)==true}
  let rewards=s["rewarded"] as? [String:Any]
  var online:Bool?; var workerRate:Double?
  if let data=workersData,let workerRoot=try? payload(data),let rx=workerRoot["randomx"] as? [String:Any],let workers=rx["workers"] as? [[String:Any]] {
   let matching=workers.filter{$0["name"] as? String=="IdleMiner"}
   online=matching.contains{$0["online"] as? Bool==true}
   let rates=matching.compactMap{StatsFormat.number($0["chr"])}
   if !matching.isEmpty && rates.count==matching.count { workerRate=rates.reduce(0,+) }
  }
  return PoolSnapshot(coin:coin,balance:balance,payable:payable,paid:paid,rewards24h:StatsFormat.number(rewards?["past_24h"]),threshold:threshold,automatic:a["auto"] as? Bool,payoutIssue:issue,workerRate:workerRate,workerOnline:online,fetchedAt:now)
 }
}


struct MiningHealth:Equatable {
 enum Level:Equatable { case working, issue, inactive }
 let level:Level
 let message:String
 static func evaluate(requested:Bool,running:Bool,stopping:Bool,fatalError:String?,local:LocalMiningStats,reportingIssue:String?=nil,now:Date=Date())->MiningHealth {
  // An unexpected stop is an error; an intentional stop/pause is inactive.
  if let problem=fatalError { return MiningHealth(level:.issue,message:problem) }
  guard requested else { return MiningHealth(level:.inactive,message:"Mining is paused or stopped") }
  if stopping { return MiningHealth(level:.inactive,message:"Switching mining threads…") }
  guard running else { return MiningHealth(level:.inactive,message:"Waiting for the engine to start…") }
  if let problem=local.connectionIssue { return MiningHealth(level:.issue,message:problem) }
  if let problem=reportingIssue { return MiningHealth(level:.issue,message:problem) }
  if let rate=local.currentRate(now:now),rate>0,local.offline || local.poolConnected {
   return MiningHealth(level:.working,message:local.offline ? "Offline benchmark working · no earnings" : "Mining is working · fresh hashrate and pool connection")
  }
  if let positive=local.lastPositiveRateAt,now.timeIntervalSince(positive)>30 {
   return MiningHealth(level:.issue,message:"Hashing has stalled · check the log")
  }
  if let update=local.rateUpdated,now.timeIntervalSince(update)>30 {
   return MiningHealth(level:.issue,message:"No fresh hashrate for over 30 seconds · check the log")
  }
  if let start=local.engineStartedAt,now.timeIntervalSince(start)>180 {
   return MiningHealth(level:.issue,message:"No confirmed mining activity · check the log")
  }
  return MiningHealth(level:.inactive,message:"Starting · waiting for mining activity…")
 }
}
