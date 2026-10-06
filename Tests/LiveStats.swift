import Foundation
@main struct LiveStats {
 @MainActor static func main() async throws {
  let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Idle Miner")
  let settings=try Settings.load(from:folder.appendingPathComponent("settings.json"))
  let service=StatsService()
  service.refresh(coin:settings.coin,address:settings.address)
  for _ in 0..<60 {
   if !service.refreshing { break }
   try await Task.sleep(nanoseconds:1_000_000_000)
  }
  guard let pool=service.pool,let price=service.quote,service.poolError==nil,service.priceError==nil else { print("FAIL: Live stats; refreshing=\(service.refreshing), price=\(service.quote != nil), pool=\(service.pool != nil), priceError=\(service.priceError ?? "none"), poolError=\(service.poolError ?? "none")"); exit(1) }
  print("PASS: live HTTPS stats; coin \(price.coin), price \(StatsFormat.usd(price.usd)), unpaid \(StatsFormat.amount(pool.balance)), paid \(StatsFormat.amount(pool.paid)), credited earnings \(pool.hasEarnings), worker online \(pool.workerOnline == true)")
 }
}
