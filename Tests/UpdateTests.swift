import Foundation

class UpdateFixtureProtocol:URLProtocol {
 override class func canInit(with request:URLRequest)->Bool { true }
 override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
 var responseStatus:Int { 200 }
 var responseData:Data { UpdateTests.fixture() }
 var responseHeaders:[String:String] { [:] }
 override func startLoading() {
  // A wrong endpoint or any user data in a request must fail before returning a fixture.
  guard request.url?.absoluteString=="https://idleminer.app/updates/stable.json",
        request.httpMethod=="GET",request.httpBody==nil,
        request.value(forHTTPHeaderField:"Cookie")==nil,
        request.value(forHTTPHeaderField:"Authorization")==nil else {
   client?.urlProtocol(self,didFailWithError:URLError(.badURL));return
  }
  let response=HTTPURLResponse(url:request.url!,statusCode:responseStatus,httpVersion:"HTTP/1.1",headerFields:responseHeaders)!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:responseData)
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
final class UpdateUnavailableProtocol:UpdateFixtureProtocol { override var responseStatus:Int { 503 } }
final class UpdateRedirectResponseProtocol:UpdateFixtureProtocol {
 override var responseStatus:Int { 302 }
 override var responseHeaders:[String:String] { ["Location":"https://elsewhere.example/private"] }
}
final class UpdateOversizedProtocol:UpdateFixtureProtocol {
 override var responseData:Data { Data(repeating:32,count:65_537) }
}
final class UpdateDeclaredOversizedProtocol:UpdateFixtureProtocol {
 override var responseHeaders:[String:String] { ["Content-Length":"65537"] }
}
final class UpdatePendingProtocol:UpdateFixtureProtocol { override func startLoading() {} }

@main struct UpdateTests {
 static var assertions=0
 static func expect(_ value:Bool,_ message:String) {
  assertions += 1
  if !value { fputs("FAIL: \(message)\n",stderr);exit(1) }
 }
 static func fixture(_ changes:[String:Any]=[:])->Data {
  var json:[String:Any]=[
   "schemaVersion":1,"version":"1.8","build":11,
   "releaseNotesURL":"https://idleminer.app/releases/1.8/",
   "platforms":[
    "macos":["url":"https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-macOS.dmg","sha256":String(repeating:"a",count:64)],
    "linux":["url":"https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-Linux.tar.gz","sha256":String(repeating:"b",count:64)]
   ]
  ]
  for (key,value) in changes { json[key]=value }
  return try! JSONSerialization.data(withJSONObject:json)
 }
 static func rejects(_ data:Data,_ message:String) {
  do { _=try UpdateManifest.parse(data);expect(false,message) } catch { expect(true,message) }
 }
 @MainActor static func main() async throws {
  let manifest=try UpdateManifest.parse(fixture())
  expect(manifest.version.text=="1.8" && manifest.version.build==11,"valid release retains version and build")
  expect(manifest.macOS.url.pathExtension=="dmg","Mac installer is selected")
  expect(manifest.linux.url.lastPathComponent=="Idle-Miner-1.8-Linux.tar.gz","Linux archive is selected")
  expect(try ReleaseVersion("1.10",build:1)>ReleaseVersion("1.9",build:999),"numeric versions order 1.10 after 1.9")
  expect(try ReleaseVersion("1.8",build:12)>ReleaseVersion("1.8.0",build:11),"build breaks equal numeric versions")
  expect(try ReleaseVersion("1.8",build:11)==ReleaseVersion("1.8.0",build:11),"missing patch is zero")
  expect(try ReleaseVersion("1.8.1",build:1)>ReleaseVersion("1.8",build:999),"patch outranks build")
  for version in ["","1","v1.8","1.8-beta","1.8+build","1.08","1.-2","1.8."," 1.8","1.8.0.1","١.٨","99999999999999999999999999.8"] {
   rejects(fixture(["version":version]),"reject malformed version \(version)")
  }
  let boundary=fixture()+Data(repeating:32,count:65_536-fixture().count)
  expect(try UpdateManifest.parse(boundary).version.text=="1.8","accept a valid manifest exactly at the size limit")
  rejects(fixture(["build":true]),"reject Boolean builds")
  rejects(fixture(["build":0]),"reject nonpositive builds")
  rejects(fixture(["build":1.2]),"reject fractional builds")
  rejects(fixture(["schemaVersion":2]),"reject unsupported schemas")
  rejects(fixture(["schemaVersion":true]),"reject Boolean schemas")
  rejects(fixture(["platforms":[:]]),"reject missing platforms")
  rejects(Data("bad json".utf8),"reject malformed JSON")
  rejects(Data(repeating:32,count:65_537),"bound manifest parsing to 64 KiB")
  for url in [
   "http://idleminer.app/releases/1.8/","https://evil.example/releases/1.8/",
   "https://idleminer.app.evil.example/releases/1.8/","https://user:password@idleminer.app/releases/1.8/",
   "https://idleminer.app/releases/1.8/?wallet=secret","https://idleminer.app/releases/1.8/#fragment",
   "https://idleminer.app:8443/releases/1.8/","https://idleminer.app/downloads/1.8/",
   "https://idleminer.app/releases/../private/","https://idleminer.app/releases/%2e%2e/private/"
  ] { rejects(fixture(["releaseNotesURL":url]),"reject unsafe release notes \(url)") }
  for (platform,validName) in [("macos","x.dmg"),("linux","x.tar.gz")] {
   for url in ["https://elsewhere.example/downloads/\(validName)","https://idleminer.app/\(validName)","https://idleminer.app/downloads/x.exe","https://user@idleminer.app/downloads/\(validName)","https://idleminer.app/downloads/\(validName)?address=secret","https://idleminer.app/downloads/../\(validName)","https://idleminer.app/downloads/%2e%2e/\(validName)"] {
    var platforms=(try JSONSerialization.jsonObject(with:fixture()) as! [String:Any])["platforms"] as! [String:Any]
    platforms[platform]=["url":url,"sha256":String(repeating:"a",count:64)]
    rejects(fixture(["platforms":platforms]),"reject unsafe \(platform) installer \(url)")
   }
   for digest in ["",String(repeating:"g",count:64),String(repeating:"a",count:63)] {
    var platforms=(try JSONSerialization.jsonObject(with:fixture()) as! [String:Any])["platforms"] as! [String:Any]
    platforms[platform]=["url":"https://idleminer.app/downloads/\(validName)","sha256":digest]
    rejects(fixture(["platforms":platforms]),"reject malformed \(platform) checksum")
   }
  }
  let redirectPolicy=UpdateRedirectPolicy()
  let redirectSession=URLSession(configuration:.ephemeral)
  let redirectTask=redirectSession.dataTask(with:URL(string:"https://idleminer.app/updates/stable.json")!)
  let redirectResponse=HTTPURLResponse(url:URL(string:"https://idleminer.app/updates/stable.json")!,statusCode:302,httpVersion:"HTTP/1.1",headerFields:nil)!
  for target in ["https://elsewhere.example/private","https://idleminer.app/other.json"] {
   var called=false
   redirectPolicy.urlSession(redirectSession,task:redirectTask,willPerformHTTPRedirection:redirectResponse,newRequest:URLRequest(url:URL(string:target)!)) { request in
    called=true;expect(request==nil,"reject redirects before any follow-up request")
   }
   expect(called,"redirect policy completes the URLSession decision")
  }
  redirectSession.invalidateAndCancel()
  let service=UpdateService(protocolClasses:[UpdateFixtureProtocol.self])
  let fetched=try await service.check()
  expect(fetched.version.text=="1.8","service fetches the fixed manifest without user data")
  expect(!service.isChecking,"service clears busy state after success")
  for protocolClass in [UpdateUnavailableProtocol.self,UpdateRedirectResponseProtocol.self,UpdateOversizedProtocol.self,UpdateDeclaredOversizedProtocol.self] {
   let failed=UpdateService(protocolClasses:[protocolClass])
   do { _=try await failed.check();expect(false,"service rejects invalid HTTP response") }
   catch { expect(!failed.isChecking,"service resets busy state after HTTP or size failure") }
  }
  let pending=UpdateService(protocolClasses:[UpdatePendingProtocol.self])
  let first=Task { try await pending.check() }
  while !pending.isChecking { await Task.yield() }
  do { _=try await pending.check();expect(false,"duplicate check is rejected") }
  catch UpdateError.busy { expect(pending.isChecking,"duplicate check preserves the active request") }
  first.cancel()
  do { _=try await first.value;expect(false,"cancelled check fails") }
  catch { expect(!pending.isChecking,"cancellation clears busy state") }
  print("Update tests passed (\(assertions) assertions)")
 }
}
