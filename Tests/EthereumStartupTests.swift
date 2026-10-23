import Foundation
@main struct EthereumStartupTests {
 static func main() throws {
  func expect(_ ok:Bool,_ message:String) { if !ok { print("FAIL: \(message)");exit(1) } }
  // Public ERC-55 examples, not user wallets.
  let vectors=["0x52908400098527886E0F7030069857D2E4169EE7","0x8617E340B3D01FA5F11F306F4090FD50E238070D","0xde709f2102306220921060314715629080e2fb77","0x27b1fdb04752bbc536007a920d24acb045561c26","0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed","0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359","0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB","0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"]
  for value in vectors { expect(Wallet.valid(value,coin:"ETH"),"ERC-55 example rejected") }
  for bad in ["0x0000000000000000000000000000000000000000","0x5aaeb6053F3E94C9b9A09f33669435E7Ef1BeAed","0x"+String(repeating:"g",count:40),vectors[0]+" ","ethereum:"+vectors[0],vectors[0]+".worker",String(vectors[0].dropLast()),"0X"+String(vectors[0].dropFirst(2))] { expect(!Wallet.valid(bad,coin:"ETH"),"invalid ETH address accepted") }
  expect(!Wallet.valid(vectors[0],coin:"BTC"),"ETH cannot route to Bitcoin")
  expect(!Wallet.valid("1BoatSLRHtKNngkdXEeobR76b53LETtpyT",coin:"ETH"),"Bitcoin cannot route to ETH")
  let legacy=try JSONDecoder().decode(Settings.self,from:Data("{}".utf8))
  let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(legacy)) as! [String:Any]
  expect(encoded["startMiningAtLogin"] as? Bool == false,"old settings must default login mining off")
  let opted=try JSONDecoder().decode(Settings.self,from:Data(#"{"startMiningAtLogin":true}"#.utf8))
  let optedJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(opted)) as! [String:Any]
  expect(optedJSON["startMiningAtLogin"] as? Bool == true,"explicit opt-in must roundtrip")
  var settings=Settings();settings.coin="BTC";settings.address="1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
  settings.wallets=["BTC":settings.address,"ETH":vectors[4],"LTC":""]
  expect(StartupPlan.currencies(settings,loginLaunch:true,loginEnabled:true).isEmpty,"opt-in is required")
  settings.startMiningAtLogin=true
  expect(StartupPlan.currencies(settings,loginLaunch:false,loginEnabled:true).isEmpty,"manual launch remains stopped")
  expect(StartupPlan.currencies(settings,loginLaunch:true,loginEnabled:false).isEmpty,"disabled or unapproved login cannot mine")
  expect(StartupPlan.currencies(settings,loginLaunch:true,loginEnabled:true,profile:"ETH").isEmpty,"children cannot recursively start peers")
  expect(StartupPlan.currencies(settings,loginLaunch:true,loginEnabled:true)==["BTC","ETH"],"only configured currencies, selected first, no duplicates")
  settings.wallets["DOGE"]="invalid"
  expect(StartupPlan.currencies(settings,loginLaunch:true,loginEnabled:true)==["BTC","ETH"],"bad or blank wallet is skipped")
  settings.wallets.removeValue(forKey:"DOGE")
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("miner-login-"+UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  let file=root.appendingPathComponent("settings.json")
  let stale=Settings();try stale.save(to:file)
  try settings.save(to:file,startMiningAtLoginChange:true)
  try stale.save(to:file,walletChanges:[:],updateDefaultCoin:false)
  let preserved=try Settings.load(from:file)
  expect(preserved.startMiningAtLogin && preserved.wallets["ETH"]==vectors[4],"stale Settings must preserve login consent and peer wallets")
  try preserved.save(to:file,walletChanges:[:],updateDefaultCoin:false,startMiningAtLoginChange:false)
  expect(try Settings.load(from:file).startMiningAtLogin==false,"explicit opt-out is saved")
  var routing=preserved;routing.switchCoin(to:"ETH")
  let object=try JSONSerialization.jsonObject(with:EngineConfig.make(routing,threads:1,benchmark:false)) as! [String:Any]
  let pool=(object["pools"] as! [[String:Any]])[0]
  expect(pool["user"] as? String == "ETH:"+vectors[4]+".IdleMiner","ETH reaches the pool without substituting another wallet")
  expect(ProfileCoordinator.profileArgument(["app","--profile=ETH"])=="ETH","ETH has a distinct profile")
  let hash=EthereumAddress.keccak256([]).map{String(format:"%02x",$0)}.joined()
  expect(hash=="c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470","Ethereum Keccak must not be SHA3-256")
  print("PASS: ETH ERC-55 validation, payout routing, login consent, migration, and stale preference preservation")
 }
}
