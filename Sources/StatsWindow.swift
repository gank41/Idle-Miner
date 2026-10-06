import AppKit

final class HashrateGraph:NSView {
 var samples=[HashSample]() { didSet { needsDisplay=true } }
 override var isOpaque:Bool { false }
 override func draw(_ dirtyRect:NSRect) {
  NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect:bounds,xRadius:10,yRadius:10).fill()
  let area=bounds.insetBy(dx:48,dy:25)
  guard area.width>0 && area.height>0 else { return }
  let now=Date(); let start=max(samples.first?.date ?? now,now.addingTimeInterval(-1800))
  let span=max(30,now.timeIntervalSince(start)); let maximum=max(1,samples.compactMap(\.rate).max() ?? 1)
  let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.secondaryLabelColor]
  NSColor.separatorColor.setStroke()
  for i in 0...2 {
   let y=area.minY+area.height*Double(i)/2
   let line=NSBezierPath(); line.move(to:CGPoint(x:area.minX,y:y)); line.line(to:CGPoint(x:area.maxX,y:y)); line.stroke()
   (String(format:"%.0f",maximum*Double(i)/2) as NSString).draw(at:CGPoint(x:4,y:y-5),withAttributes:attributes)
  }
  ("H/s" as NSString).draw(at:CGPoint(x:4,y:bounds.maxY-16),withAttributes:attributes)
  (StatsFormat.time(start) as NSString).draw(at:CGPoint(x:area.minX,y:5),withAttributes:attributes)
  ("Now" as NSString).draw(at:CGPoint(x:area.maxX-24,y:5),withAttributes:attributes)
  guard samples.contains(where:{$0.rate != nil}) else {
   ("Waiting for hashrate samples…" as NSString).draw(at:CGPoint(x:area.midX-85,y:area.midY),withAttributes:attributes); return
  }
  let path=NSBezierPath(); path.lineWidth=2
  var previous:Date?
  NSColor.systemOrange.setStroke()
  for sample in samples where sample.date>=start {
   guard let rate=sample.rate else { previous=nil; continue }
   let point=CGPoint(x:area.minX+area.width*sample.date.timeIntervalSince(start)/span,y:area.minY+area.height*rate/maximum)
   if let prior=previous,sample.date.timeIntervalSince(prior)<20 { path.line(to:point) } else { path.move(to:point) }
   NSColor.systemOrange.setFill(); NSBezierPath(ovalIn:NSRect(x:point.x-1.5,y:point.y-1.5,width:3,height:3)).fill()
   previous=sample.date
  }
  path.stroke()
 }
}
final class StatsDocument:NSView { override var isFlipped:Bool { true } }
final class StatsWindow {
 let window:NSWindow
 private var fittedInitialSize=false
 let state=NSTextField(wrappingLabelWithString:"")
 let activity=NSTextField(wrappingLabelWithString:"")
 let shares=NSTextField(wrappingLabelWithString:"")
 let graph=HashrateGraph()
 let market=NSTextField(wrappingLabelWithString:"")
 let balance=NSTextField(wrappingLabelWithString:"")
 let rewards=NSTextField(wrappingLabelWithString:"")
 let payments=NSTextField(wrappingLabelWithString:"")
 let progress=NSProgressIndicator()
 let threshold=NSTextField(wrappingLabelWithString:"")
 let freshness=NSTextField(wrappingLabelWithString:"")
 let refresh=NSButton(title:"Refresh Stats",target:nil,action:nil)
 init(target:AnyObject,refreshAction:Selector,poolAction:Selector) {
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="Idle Miner · Mining Stats"; window.isReleasedWhenClosed=false; window.center()
  let scroll=NSScrollView(frame:window.contentView!.bounds); scroll.autoresizingMask=[.width,.height]; scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true; scroll.drawsBackground=false
  window.contentView!.addSubview(scroll)
  let document=StatsDocument(); document.translatesAutoresizingMaskIntoConstraints=false; scroll.documentView=document
  document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
  let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=11
  stack.translatesAutoresizingMaskIntoConstraints=false; document.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-20)])
  func row(_ view:NSView) { stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
  func label(_ text:String,size:CGFloat=12,bold:Bool=false,secondary:Bool=false)->NSTextField {
   let f=NSTextField(wrappingLabelWithString:text); f.font=bold ? .boldSystemFont(ofSize:size) : .systemFont(ofSize:size)
   if secondary { f.textColor = .secondaryLabelColor }; row(f); return f
  }
  _=label("Mining Stats",size:24,bold:true)
  state.font = .boldSystemFont(ofSize:14); row(state)
  for f in [activity,shares] { f.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular); row(f) }
  _=label("This Mac’s hashrate · last 30 minutes of this session",bold:true)
  row(graph); graph.heightAnchor.constraint(equalToConstant:130).isActive=true
  _=label("Accepted shares are valid work received by the pool. They are not coins or wallet deposits. Share difficulty varies, so the count cannot be converted directly into dollars.",secondary:true)
  market.font = .boldSystemFont(ofSize:14); row(market)
  balance.font = .boldSystemFont(ofSize:15); row(balance)
  for f in [rewards,payments,threshold,freshness] { f.font = .systemFont(ofSize:12) }
  row(rewards); row(payments)
  progress.isIndeterminate=false; progress.minValue=0; progress.maxValue=100; progress.style = .bar; row(progress); row(threshold)
  freshness.textColor = .secondaryLabelColor; row(freshness)
  _=label("Pool totals belong to the selected payout address and may include other miners. A payout reported by the pool is not verification of a Robinhood deposit. USD values are estimates before electricity and any selling fees.",secondary:true)
  _=label("Green ₿ = mining is working. Red = a mining, reporting, or payout issue; see the status above. Gray = paused, stopped, or starting. These colors do not indicate earnings or a new deposit.",secondary:true)
  let buttons=NSStackView(); buttons.orientation = .horizontal; buttons.spacing=12
  refresh.target=target; refresh.action=refreshAction
  buttons.addArrangedSubview(refresh); buttons.addArrangedSubview(NSButton(title:"Open Pool Dashboard",target:target,action:poolAction)); stack.addArrangedSubview(buttons)
 }
 // Fit once after the first populated render. Later refreshes and reopening
 // leave the user's chosen size alone; the scroll view handles small screens.
 func fitInitialContent() {
  guard !fittedInitialSize else { return }
  fittedInitialSize=true
  guard let screen=window.screen ?? NSScreen.main,let content=window.contentView,
        let scroll=content.subviews.first as? NSScrollView,let document=scroll.documentView else { return }
  let available=screen.visibleFrame.insetBy(dx:12,dy:12)
  let chrome=window.frame.height-content.bounds.height
  let maximumHeight=max(1,available.height-chrome)
  let width=min(760,available.width)
  window.contentMinSize=NSSize(width:min(560,width),height:min(480,maximumHeight))
  window.setContentSize(NSSize(width:width,height:min(900,maximumHeight)))
  content.layoutSubtreeIfNeeded()
  window.setContentSize(NSSize(width:width,height:min(max(860,ceil(document.frame.height)+8),maximumHeight)))
  window.center()
  var frame=window.frame
  frame.origin.x=max(available.minX,min(frame.minX,available.maxX-frame.width))
  frame.origin.y=max(available.minY,min(frame.minY,available.maxY-frame.height))
  window.setFrame(frame,display:true)
 }
 func show() { NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil) }
}
