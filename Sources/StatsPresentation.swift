import AppKit

extension MinerApp {
 func applyMiningHealth(_ health:MiningHealth) {
  let color:NSColor
  switch health.level { case .working: color = .systemGreen; case .issue: color = .systemRed; case .inactive: color = .systemGray }
  let icon=(coordinator?.peers ?? 1)>1 ? "₿ \(settings.coin)" : "₿"
  if lastHealthLevel != health.level || lastIconText != icon {
   lastIconText=icon
   lastHealthLevel=health.level
   statusItem.button?.attributedTitle=NSAttributedString(string:icon,attributes:[.foregroundColor:color,.font:NSFont.systemFont(ofSize:16,weight:.medium)])
  }
  healthItem.title=health.message
  statusItem.button?.toolTip="Idle Miner · \(stateItem.title)\n\(health.message)"
 }
 @objc func showStatistics() {
  if statsWindow==nil { statsWindow=StatsWindow(target:self,refreshAction:#selector(refreshStatistics),poolAction:#selector(openPool)) }
  statsWindow?.window.title="Idle Miner · \(settings.coin) · Mining Stats"
  statsWindow?.show(); updateStatistics();statsWindow?.fitInitialContent()
 }
 @objc func refreshStatistics() {
  if statisticsNetworkingEnabled { statsService.refresh(coin:settings.coin,address:settings.address,force:true) }
  updateStatistics()
 }
 func updateStatistics() {
  let coin=settings.coin
  let quote=statsService.quote
  let pool=statsService.pool
  let freshPrice=quote?.isFresh()==true && statsService.priceError==nil
  let freshPool=pool?.isFresh()==true && statsService.poolError==nil
  if let quote=quote {
   priceItem.title="1 \(coin) ≈ \(StatsFormat.usd(quote.usd)) USD\(freshPrice ? "" : " · outdated")"
  } else { priceItem.title="\(coin) price · \(statsService.priceError==nil ? "loading…" : "unavailable")" }
  if let pool=pool {
   balanceItem.title="\(freshPool ? "Pool balance" : "Last known balance"): \(StatsFormat.amount(pool.balance)) \(coin)"
  } else { balanceItem.title="Pool balance · \(statsService.poolError==nil ? "checking…" : "unavailable")" }
  let reportingIssue=localStats.offline ? nil : statsService.poolError ?? statsService.priceError ?? (freshPool && pool?.payoutIssue==true ? "Provider reports a payout issue · check Mining Stats" : nil)
  let health=MiningHealth.evaluate(requested:desiredThreads>0,running:engine.running,stopping:engine.isStopping || engine.isChanging,fatalError:fatalError,local:localStats,reportingIssue:reportingIssue)
  applyMiningHealth(health)
  let current=engine.running ? localStats.currentRate() : nil
  if benchmarkDeadline==nil {
   rateItem.title=engine.running ? "RandomX: \(current.map{String(format:"%.1f",$0)} ?? "—") H/s → \(coin)" : "Payout currency: \(coin)"
  }
  menuSummary.update([stateItem,healthItem,rateItem,sharesItem,priceItem,balanceItem].map(\.title))
  guard let view=statsWindow,view.window.isVisible else { return }
  view.state.stringValue=stateItem.title+"\n"+health.message
  let began=sessionClock.startedDate.map{DateFormatter.localizedString(from:$0,dateStyle:.medium,timeStyle:.medium)} ?? "Not started yet"
  view.activity.stringValue="Session began: \(began)\nSession elapsed: \(SessionClock.duration(sessionClock.elapsed())) · Hashing: \(SessionClock.duration(sessionClock.hashingSeconds))\nApp uptime: \(SessionClock.duration(sessionClock.uptime()))\n\(localStats.connection)\nCurrent: \(current.map{String(format:"%.1f H/s",$0)} ?? "awaiting a fresh sample") · \(engine.threads) engine threads"
  view.shares.stringValue="Accepted shares: \(localStats.accepted)  ·  Rejected: \(localStats.rejected)  ·  Last accepted: \(StatsFormat.time(localStats.lastAccepted))"
  view.graph.samples=localStats.history.filter{$0.date>Date().addingTimeInterval(-1800)}
  view.market.stringValue=priceItem.title+"\nCoinbase spot price · checked \(StatsFormat.time(quote?.fetchedAt))"
  view.refresh.isEnabled = !statsService.refreshing
  view.refresh.title=statsService.refreshing ? "Refreshing…" : "Refresh Stats"
  if let pool=pool {
   let usd=freshPrice ? " ≈ \(StatsFormat.usd(pool.balance*quote!.usd)) USD" : ""
   view.balance.stringValue="\(freshPool ? "Unpaid pool balance" : "Last known unpaid balance"): \(StatsFormat.amount(pool.balance)) \(coin)\(usd)"
   let rewards=pool.rewards24h.map{StatsFormat.amount($0)+" "+coin} ?? "Not reported"
   let worker=pool.workerOnline.map{$0 ? "online" : "not currently listed online"} ?? "unavailable"
   let workerRate=pool.workerRate.map{String(format:" · calculated %.1f H/s",$0)} ?? ""
   view.rewards.stringValue="Pool-reported rewards, past 24h: \(rewards)\nIdleMiner worker at last check: \(worker)\(workerRate)"
   view.payments.stringValue="Total paid by pool: \(StatsFormat.amount(pool.paid)) \(coin)\(pool.paid==0 ? " · no payouts yet" : "")"
   view.progress.doubleValue=pool.progress
   let automatic=pool.automatic.map{$0 ? "Automatic payouts on" : "Automatic payouts off · use the pool dashboard when eligible"} ?? "Payout setting not reported"
   let issue=pool.payoutIssue ? "\nProvider reports a payout restriction/error; check the dashboard." : ""
   view.threshold.stringValue=String(format:"%.2f%% of payout minimum",pool.progress)+" · \(StatsFormat.amount(pool.threshold)) \(coin)\nPayable balance: \(StatsFormat.amount(pool.payable)) \(coin)\n\(automatic)\(issue)"
  } else {
   view.balance.stringValue="Unpaid pool balance: awaiting confirmation"
   view.rewards.stringValue="Past 24h rewards and worker status: awaiting confirmation"
   view.payments.stringValue="Payouts: awaiting confirmation"
   view.progress.doubleValue=0; view.threshold.stringValue="Payout minimum: awaiting confirmation"
  }
  let notice=[statsService.poolError,statsService.priceError].compactMap{$0}.joined(separator:" ")
  view.freshness.stringValue="unMineable checked: \(StatsFormat.time(pool?.fetchedAt)) · Refreshes every 2 minutes\n\(notice.isEmpty ? "Pool accounting may lag behind accepted shares. Local session history resets when you start a new session or quit." : notice)"
 }
}
