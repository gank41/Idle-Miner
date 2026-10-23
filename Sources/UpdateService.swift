import Foundation

struct ReleaseVersion:Comparable,Sendable {
 let text:String
 let build:Int
 private let components:[Int]
 init(_ text:String,build:Int)throws {
  let pieces=text.split(separator:".",omittingEmptySubsequences:false)
  guard (2...3).contains(pieces.count),build>0 else { throw UpdateError.invalidManifest }
  var numbers=[Int]()
  for piece in pieces {
   guard !piece.isEmpty,piece.utf8.allSatisfy({ $0>=48 && $0<=57 }),
         piece.count==1 || piece.first != "0",let number=Int(piece) else { throw UpdateError.invalidManifest }
   numbers.append(number)
  }
  self.text=text;self.build=build;components=numbers+[Int](repeating:0,count:3-numbers.count)
 }
 static func ==(lhs:Self,rhs:Self)->Bool { lhs.components==rhs.components && lhs.build==rhs.build }
 static func <(lhs:Self,rhs:Self)->Bool {
  if lhs.components != rhs.components { return lhs.components.lexicographicallyPrecedes(rhs.components) }
  return lhs.build<rhs.build
 }
}

struct UpdateManifest:Sendable {
 struct Asset:Sendable { let url:URL;let sha256:String }
 let version:ReleaseVersion
 let releaseNotesURL:URL
 let macOS:Asset
 let linux:Asset
 static let maximumBytes=65_536
 private struct Payload:Decodable {
  struct Download:Decodable { let url:String;let sha256:String }
  struct Platforms:Decodable { let macos:Download;let linux:Download }
  let schemaVersion:Int
  let version:String
  let build:Int
  let releaseNotesURL:String
  let platforms:Platforms
 }
 static func parse(_ data:Data)throws->Self {
  guard data.count<=maximumBytes else { throw UpdateError.tooLarge }
  do {
   let raw=try JSONDecoder().decode(Payload.self,from:data)
   guard raw.schemaVersion==1 else { throw UpdateError.invalidManifest }
   let version=try ReleaseVersion(raw.version,build:raw.build)
   let notes=try validatedURL(raw.releaseNotesURL,prefix:"/releases/")
   func asset(_ value:Payload.Download,suffix:String)throws->Asset {
    let url=try validatedURL(value.url,prefix:"/downloads/")
    guard url.path.hasSuffix(suffix),value.sha256.utf8.count==64,
          value.sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw UpdateError.invalidManifest }
    return Asset(url:url,sha256:value.sha256.lowercased())
   }
   return Self(version:version,releaseNotesURL:notes,macOS:try asset(raw.platforms.macos,suffix:".dmg"),linux:try asset(raw.platforms.linux,suffix:".tar.gz"))
  } catch let error as UpdateError { throw error }
  catch { throw UpdateError.invalidManifest }
 }
 private static func validatedURL(_ text:String,prefix:String)throws->URL {
  guard text.utf8.allSatisfy({ $0>=33 && $0<=126 }),
        let parts=URLComponents(string:text),parts.scheme=="https",parts.host=="idleminer.app",
        parts.user==nil,parts.password==nil,parts.port==nil,parts.query==nil,parts.fragment==nil,
        parts.percentEncodedPath==parts.path,parts.path.hasPrefix(prefix),!parts.path.contains("//"),
        parts.path.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,47,95].contains($0) }),
        !parts.path.split(separator:"/").contains(where:{ $0=="." || $0==".." }),let url=parts.url else { throw UpdateError.invalidManifest }
  return url
 }
}

enum UpdateError:LocalizedError {
 case invalidManifest,tooLarge,invalidResponse,busy
 var errorDescription:String? {
  switch self {
  case .invalidManifest:return "The update information could not be verified. Please try again later."
  case .tooLarge:return "The update server returned too much information. Please try again later."
  case .invalidResponse:return "The update server is unavailable or returned an unexpected response. Please try again later."
  case .busy:return "An update check is already in progress."
  }
 }
}

// Stateless delegate: manifest redirects are always rejected, including same-origin redirects.
final class UpdateRedirectPolicy:NSObject,URLSessionTaskDelegate {
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
}

@MainActor final class UpdateService {
 static let manifestURL=URL(string:"https://idleminer.app/updates/stable.json")!
 private(set) var isChecking=false
 private let protocolClasses:[AnyClass]?
 init(protocolClasses:[AnyClass]?=nil) { self.protocolClasses=protocolClasses }
 func check()async throws->UpdateManifest {
  guard !isChecking else { throw UpdateError.busy }
  isChecking=true;defer { isChecking=false }
  let config=URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=15
  config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil;config.urlCache=nil
  config.requestCachePolicy = .reloadIgnoringLocalCacheData;config.waitsForConnectivity=false
  if let protocolClasses { config.protocolClasses=protocolClasses }
  let session=URLSession(configuration:config,delegate:UpdateRedirectPolicy(),delegateQueue:nil)
  defer { session.invalidateAndCancel() }
  var request=URLRequest(url:Self.manifestURL)
  request.httpMethod="GET";request.setValue("application/json",forHTTPHeaderField:"Accept")
  request.setValue("IdleMiner",forHTTPHeaderField:"User-Agent")
  let (bytes,response)=try await session.bytes(for:request)
  guard let response=response as? HTTPURLResponse,response.statusCode==200,response.url==Self.manifestURL else { throw UpdateError.invalidResponse }
  guard response.expectedContentLength<=Int64(UpdateManifest.maximumBytes) else { throw UpdateError.tooLarge }
  var data=Data()
  for try await byte in bytes {
   try Task.checkCancellation()
   guard data.count<UpdateManifest.maximumBytes else { throw UpdateError.tooLarge }
   data.append(byte)
  }
  return try UpdateManifest.parse(data)
 }
}
