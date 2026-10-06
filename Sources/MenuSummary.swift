import AppKit

// Status is information, not a disabled command. Keep native menu translucency
// while using full-contrast semantic text that also respects Increase Contrast.
@MainActor final class MenuSummary:NSView {
 private var previousLines=[String]()
 let labels=(0..<6).map { _ in NSTextField(wrappingLabelWithString:"") }
 override var isFlipped:Bool { true }
 init() {
  super.init(frame:NSRect(x:0,y:0,width:360,height:180))
  for (index,label) in labels.enumerated() {
   label.textColor = .labelColor
   label.font = .systemFont(ofSize:index==0 ? 13 : 12,weight:index==0 ? .semibold : .regular)
   label.maximumNumberOfLines=0
   label.isSelectable=false
   addSubview(label)
  }
 }
 required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
 func update(_ lines:[String]) {
  guard lines != previousLines else { return }; previousLines=lines
  var y:CGFloat=10
  for (label,line) in zip(labels,lines) {
   label.stringValue=line
   let size=label.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:328,height:1000))
   label.frame=NSRect(x:16,y:y,width:328,height:ceil(size.height))
   y += ceil(size.height)+6
  }
  setFrameSize(NSSize(width:360,height:y+4))
 }
}
