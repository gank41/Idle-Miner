import AppKit

private final class CurrencyMenuAction:NSObject {
 let coin:String
 let peer:MenuPeerSnapshot?
 let action:String
 let minutes:Int?
 init(coin:String,peer:MenuPeerSnapshot?,action:String,minutes:Int?=nil) { self.coin=coin;self.peer=peer;self.action=action;self.minutes=minutes }
}
extension MinerApp {
 func drainSharedMenuCommands() {
  if sharedMenuStore==nil { sharedMenuStore=try? SharedMenuStore(base:baseFolder,profile:profileName) }
  let incoming=sharedMenuStore?.commands(coin:settings.coin) ?? []
  for command in incoming {
   if quitting { break }
   performCurrencyCommand(command.action,minutes:command.minutes)
  }
 }
 func refreshSharedMenu(level:String,lines:[String]) {
  if sharedMenuStore==nil { sharedMenuStore=try? SharedMenuStore(base:baseFolder,profile:profileName) }
  guard let store=sharedMenuStore else { statusItem.menu=profileMenu;statusItem.isVisible=settings.showMenuBar;return }
  guard !quitting else { statusItem.isVisible=false;store.releaseOwnership();return }
  try? store.publish(coin:settings.coin,level:level,enabled:enabled,lines:lines)
  guard settings.showMenuBar else { statusItem.isVisible=false;store.releaseOwnership();return }
  guard store.claimOwnership() else { statusItem.isVisible=false;return }
  statusItem.isVisible=true
  let snapshots=store.snapshots()
  var selected=[String:MenuPeerSnapshot]()
  for peer in snapshots {
   if selected[peer.coin]==nil || peer.rank>selected[peer.coin]!.rank { selected[peer.coin]=peer }
  }
  let local=MenuPeerSnapshot(pid:ProcessInfo.processInfo.processIdentifier,profile:profileName,coin:settings.coin,nonce:store.nonce,updated:Date().timeIntervalSince1970,level:level,enabled:enabled,lines:lines)
  if selected[settings.coin]==nil || local.rank>=selected[settings.coin]!.rank { selected[settings.coin]=local }
  let signature=settings.coin+"|"+Settings.coins.map { coin in selected[coin].map{coin+":"+$0.profile+":"+$0.nonce} ?? coin }.joined(separator:"|")
  if unifiedMenu==nil || (signature != sharedMenuSignature && !sharedMenuTracking) {
   sharedMenuSignature=signature;buildUnifiedMenu(selected)
  }
  for coin in Settings.coins {
   guard let row=sharedCurrencyRows[coin] else { continue }
   let peer=selected[coin]
   let color=menuColor(peer?.level ?? "inactive")
   row.attributedTitle=NSAttributedString(string:currencyName(coin),attributes:[.foregroundColor:color,.font:NSFont.menuFont(ofSize:13)])
   row.image=NSImage(size:NSSize(width:10,height:10),flipped:false) { rect in color.setFill();NSBezierPath(ovalIn:rect.insetBy(dx:1,dy:1)).fill();return true }
   row.image?.isTemplate=false
   row.toolTip=peer?.lines.dropFirst().first ?? "Not running or status unavailable · open for details"
   if peer?.profile != profileName { sharedRemoteSummaries[coin]?.update(peer?.lines ?? ["Not running or status unavailable","Open this currency to configure or start mining.","Payout currency: \(coin)","No session work","Price unavailable","Pool balance unavailable"]) }
  }
  let overall=selected.values.contains{$0.level=="issue"} ? "issue" : selected.values.contains{$0.level=="working"} ? "working" : "inactive"
  statusItem.button?.attributedTitle=NSAttributedString(string:"₿",attributes:[.foregroundColor:menuColor(overall),.font:NSFont.systemFont(ofSize:16,weight:.medium)])
  statusItem.button?.toolTip="Idle Miner · \(selected.count) currency instance\(selected.count==1 ? "":"s") · open for per-currency status"
  rootLoginItem?.state=loginItem.state
  rootUpdateItem?.title=builtInUpdater.menuTitle
 }
 func menuColor(_ level:String)->NSColor { level=="working" ? .systemGreen : level=="issue" ? .systemRed : .systemGray }
 func currencyName(_ coin:String)->String { ["BTC":"Bitcoin (BTC)","LTC":"Litecoin (LTC)","DOGE":"Dogecoin (DOGE)","ETH":"Ethereum (ETH)"][coin] ?? coin }
 func buildUnifiedMenu(_ peers:[String:MenuPeerSnapshot]) {
  if let old=unifiedMenu { for row in old.items { row.submenu=nil } }
  sharedCurrencyRows.removeAll();sharedRemoteSummaries.removeAll()
  let menu=NSMenu();menu.autoenablesItems=false;menu.delegate=self
  for coin in Settings.coins {
   let row=NSMenuItem(title:currencyName(coin),action:nil,keyEquivalent:"")
   if let peer=peers[coin],peer.profile==profileName { row.submenu=profileMenu }
   else {
    let sub=NSMenu(title:currencyName(coin));sub.autoenablesItems=false
    let summary=MenuSummary();sharedRemoteSummaries[coin]=summary
    let info=NSMenuItem();info.view=summary;sub.addItem(info);sub.addItem(.separator())
    func command(_ title:String,_ action:String,_ minutes:Int?=nil,to target:NSMenu?=nil) {
     let item=add(title,#selector(currencyMenuAction(_:)),to:target ?? sub)
     item.representedObject=CurrencyMenuAction(coin:coin,peer:peers[coin],action:action,minutes:minutes)
    }
    command("Mining Stats…","stats");command("Start Mining","start");command("Stop Mining","stop")
    let boosts=NSMenu(title:"Boost Mining");boosts.autoenablesItems=false
    for minutes in TimedBoost.durations { command(TimedBoost.label(minutes:minutes),"boost",minutes,to:boosts) }
    let boost=NSMenuItem(title:"Boost Mining",action:nil,keyEquivalent:"");boost.submenu=boosts;sub.addItem(boost)
    command("End Boost · Return to Automatic","endBoost");sub.addItem(.separator())
    command("Settings…","settings");command("View Pool Payouts…","pool");command("Show Latest Log","log");command("Quit This Currency","quit")
    row.submenu=sub
   }
   sharedCurrencyRows[coin]=row;menu.addItem(row)
  }
  menu.addItem(.separator());_=add("Settings…",#selector(showSettings),key:",",to:menu)
  rootLoginItem=add("Start at Login",#selector(toggleLoginItem),to:menu);rootLoginItem?.state=loginItem.state
  rootUpdateItem=add(builtInUpdater.menuTitle,#selector(checkForUpdates),to:menu)
  _=add("Wallet & Payout Help",#selector(showHelp),to:menu);_=add("About Idle Miner",#selector(showAbout),to:menu)
  menu.addItem(.separator());_=add("Stop All Mining",#selector(stopAllCurrencies),to:menu);_=add("Quit Idle Miner",#selector(quitAllCurrencies),key:"q",to:menu)
  unifiedMenu=menu;statusItem.menu=menu
 }
 @objc func currencyMenuAction(_ item:NSMenuItem) {
  guard let target=item.representedObject as? CurrencyMenuAction else { return }
  if let peer=target.peer {
   if peer.profile==profileName { performCurrencyCommand(target.action,minutes:target.minutes) }
   else { do { try sharedMenuStore?.send(peer,action:target.action,minutes:target.minutes) } catch { alert(error.localizedDescription) } }
  } else {
   // Never implicitly mine from a hover or a Stats/Settings click.
   if target.action=="stats" || target.action=="settings" { openCurrencyInstance(target.coin,startMining:false,showStats:target.action=="stats",showSettings:target.action=="settings") }
   else if target.action=="start" || target.action=="boost" { openCurrencyInstance(target.coin,startMining:true,showStats:false,boostMinutes:target.action=="boost" ? target.minutes : nil) }
  }
 }
 func performCurrencyCommand(_ action:String,minutes:Int?=nil) {
  switch action {
  case "stats":showStatistics()
  case "start":startMining()
  case "stop":stopMining()
  case "boost":if let minutes=minutes,TimedBoost.durations.contains(minutes) { beginBoost(minutes:minutes) }
  case "endBoost":endBoost()
  case "settings":showSettings()
  case "pool":openPool()
  case "log":showLog()
  case "quit":quitApp()
  default:break
  }
 }
 @objc func stopAllCurrencies() {
  for peer in sharedMenuStore?.snapshots() ?? [] where peer.profile != profileName { try? sharedMenuStore?.send(peer,action:"stop") }
  stopMining()
 }
 @objc func quitAllCurrencies() {
  for peer in sharedMenuStore?.snapshots() ?? [] where peer.profile != profileName { try? sharedMenuStore?.send(peer,action:"quit") }
  quitApp()
 }
 func menuDidClose(_ menu:NSMenu) { if menu === unifiedMenu { sharedMenuTracking=false } }
}
