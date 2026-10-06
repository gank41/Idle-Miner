import Foundation

// Only GETs to fixed HTTPS origins. Never follows redirects with a wallet in the URL.
final class StatsHTTP:NSObject,URLSessionTaskDelegate {
 lazy var session:URLSession = {
  let config=URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest=15; config.timeoutIntervalForResource=25
  config.httpCookieStorage=nil; config.urlCache=nil; config.httpMaximumConnectionsPerHost=2
  return URLSession(configuration:config,delegate:self,delegateQueue:nil)
 }()
 // Initialize before concurrent price/pool requests; Swift lazy initialization is not synchronized.
 override init() { super.init(); _=session }
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
 func get(_ url:URL)async throws->Data {
  guard url.scheme=="https",["api.unmineable.com","api.coinbase.com"].contains(url.host ?? "") else { throw StatsError.invalidResponse }
  var req=URLRequest(url:url); req.httpMethod="GET"; req.setValue("IdleMiner/1.2",forHTTPHeaderField:"User-Agent")
  let (data,response)=try await session.data(for:req)
  guard let response=response as? HTTPURLResponse else { throw StatsError.invalidResponse }
  guard response.statusCode==200 else { throw StatsError.http(response.statusCode) }
  guard data.count<2_000_000 else { throw StatsError.invalidResponse }
  return data
 }
}
@MainActor final class StatsService {
 var quote:PriceQuote?
 var pool:PoolSnapshot?
 var priceError:String?
 var poolError:String?
 var refreshing=false
 var updated:(()->Void)?
 private var key=""
 private var generation=UUID()
 private var lastAttempt=Date.distantPast
 private var task:Task<Void,Never>?
 private let http=StatsHTTP()
 func configure(coin:String,address:String) {
  let newKey=coin+":"+address
  guard key != newKey else { return }
  task?.cancel(); generation=UUID(); key=newKey; quote=nil; pool=nil; priceError=nil; poolError=nil
  lastAttempt = .distantPast; refreshing=false
 }
 func refresh(coin:String,address:String,force:Bool=false) {
  configure(coin:coin,address:address)
  let interval=force ? 30.0 : 120.0
  guard !refreshing,Date().timeIntervalSince(lastAttempt)>=interval,["LTC","BTC","DOGE"].contains(coin) else { return }
  lastAttempt=Date(); refreshing=true; let token=generation; updated?()
  task=Task { [weak self] in
   guard let self=self else { return }
   async let priceResult=self.fetchPrice(coin:coin)
   async let poolResult=self.fetchPool(coin:coin,address:address)
   let (price,balance)=await (priceResult,poolResult)
   guard self.generation==token,!Task.isCancelled else { return }
   switch price { case .success(let value):self.quote=value; self.priceError=nil; case .failure: self.priceError="Price unavailable; retrying automatically." }
   switch balance { case .success(let value):self.pool=value; self.poolError=nil; case .failure: self.poolError=address.isEmpty ? "Add a receive address in Settings to see earnings." : "Pool stats unavailable; retrying automatically. Open the pool dashboard for details." }
   self.refreshing=false; self.updated?()
  }
 }
 private func fetchPrice(coin:String)async->Result<PriceQuote,Error> {
  do { return .success(try PriceQuote.parse(await http.get(URL(string:"https://api.coinbase.com/v2/prices/\(coin)-USD/spot")!),coin:coin)) } catch { return .failure(error) }
 }
 private func fetchPool(coin:String,address:String)async->Result<PoolSnapshot,Error> {
  do {
   guard Wallet.valid(address,coin:coin) else { throw StatsError.invalidResponse }
   var components=URLComponents(string:"https://api.unmineable.com/v4/address/")!
   components.path += address; components.queryItems=[URLQueryItem(name:"coin",value:coin)]
   let a=try await http.get(components.url!)
   let id=try PoolSnapshot.identifier(a,address:address)
   async let stats=http.get(URL(string:"https://api.unmineable.com/v4/account/\(id)/stats")!)
   async let workers:Data?=try? http.get(URL(string:"https://api.unmineable.com/v4/account/\(id)/workers")!)
   return .success(try await PoolSnapshot.parse(addressData:a,statsData:stats,workersData:workers,coin:coin))
  } catch { return .failure(error) }
 }
}
