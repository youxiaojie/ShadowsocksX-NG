//
//  ServerProfile.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/6.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import XYPingUtil


class ServerProfile: NSObject, NSCopying {
    
    @objc var uuid: String

    @objc var serverHost: String = ""
    @objc var serverPort: uint16 = 8379
    @objc var method:String = "aes-128-gcm"
    @objc var password:String = ""
    @objc var remark:String = ""
    @objc var ota: Bool = false // onetime authentication
    
    @objc var enabledKcptun: Bool = false
    @objc var kcptunProfile = KcptunProfile()
    
    @objc var ping:Int = 0
    
    override init() {
        uuid = UUID().uuidString
    }

    init(uuid: String) {
        self.uuid = uuid
    }

    convenience init?(url: URL) {
        self.init()

        func padBase64(string: String) -> String {
            var length = string.characters.count
            if length % 4 == 0 {
                return string
            } else {
                length = 4 - length % 4 + length
                return string.padding(toLength: length, withPad: "=", startingAt: 0)
            }
        }

        func decodeUrl(url: URL) -> String? {
            let urlStr = url.absoluteString
            let index = urlStr.index(urlStr.startIndex, offsetBy: 5)
            let encodedStr = urlStr[index...]
            guard let data = Data(base64Encoded: padBase64(string: String(encodedStr))) else {
                return url.absoluteString
            }
            guard let decoded = String(data: data, encoding: String.Encoding.utf8) else {
                return nil
            }
            let s = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            return "ss://\(s)"
        }

        guard let decodedUrl = decodeUrl(url: url) else {
            return nil
        }
        guard var parsedUrl = URLComponents(string: decodedUrl) else {
            return nil
        }
        guard let host = parsedUrl.host, let port = parsedUrl.port,
            let user = parsedUrl.user else {
            return nil
        }

        self.serverHost = host
        self.serverPort = UInt16(port)

        // This can be overriden by the fragment part of SIP002 URL
        remark = parsedUrl.queryItems?
            .filter({ $0.name == "Remark" }).first?.value ?? ""

        if let password = parsedUrl.password {
            self.method = user.lowercased()
            self.password = password
        } else {
            // SIP002 URL have no password section
            guard let data = Data(base64Encoded: padBase64(string: user)),
                let userInfo = String(data: data, encoding: .utf8) else {
                return nil
            }

            let parts = userInfo.characters.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count != 2 {
                return nil
            }
            self.method = String(parts[0]).lowercased()
            self.password = String(parts[1])

            // SIP002 defines where to put the profile name
            if let profileName = parsedUrl.fragment {
                self.remark = profileName
            }
        }

        if let otaStr = parsedUrl.queryItems?
            .filter({ $0.name == "OTA" }).first?.value {
            ota = NSString(string: otaStr).boolValue
        }
        if let enabledKcptunStr = parsedUrl.queryItems?
            .filter({ $0.name == "Kcptun" }).first?.value {
            enabledKcptun = NSString(string: enabledKcptunStr).boolValue
        }
        
        if enabledKcptun {
            if let items = parsedUrl.queryItems {
                self.kcptunProfile.loadUrlQueryItems(items: items)
            }
        }
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = ServerProfile()
        copy.serverHost = self.serverHost
        copy.serverPort = self.serverPort
        copy.method = self.method
        copy.password = self.password
        copy.remark = self.remark
        copy.ota = self.ota
        
        copy.enabledKcptun = self.enabledKcptun
        copy.kcptunProfile = self.kcptunProfile.copy() as! KcptunProfile
        copy.ping = self.ping
        return copy;
    }
    
    static func fromDictionary(_ data:[String:Any?]) -> ServerProfile {
        let cp = {
            (profile: ServerProfile) in
            profile.serverHost = data["ServerHost"] as! String
            profile.serverPort = (data["ServerPort"] as! NSNumber).uint16Value
            profile.method = data["Method"] as! String
            profile.password = data["Password"] as! String
            if let remark = data["Remark"] {
                profile.remark = remark as! String
            }
            if let ota = data["OTA"] {
                profile.ota = ota as! Bool
            }
            if let enabledKcptun = data["EnabledKcptun"] {
                profile.enabledKcptun = enabledKcptun as! Bool
            }
            if let kcptunData = data["KcptunProfile"] {
                profile.kcptunProfile =  KcptunProfile.fromDictionary(kcptunData as! [String:Any?])
            }
            if let ping = data["Ping"] as? NSNumber {
                profile.ping = ping.intValue
            }
        }

        if let id = data["Id"] as? String {
            let profile = ServerProfile(uuid: id)
            cp(profile)
            return profile
        } else {
            let profile = ServerProfile()
            cp(profile)
            return profile
        }
    }

    func toDictionary() -> [String:AnyObject] {
        var d = [String:AnyObject]()
        d["Id"] = uuid as AnyObject?
        d["ServerHost"] = serverHost as AnyObject?
        d["ServerPort"] = NSNumber(value: serverPort as UInt16)
        d["Method"] = method as AnyObject?
        d["Password"] = password as AnyObject?
        d["Remark"] = remark as AnyObject?
        d["OTA"] = ota as AnyObject?
        d["EnabledKcptun"] = NSNumber(value: enabledKcptun)
        d["KcptunProfile"] = kcptunProfile.toDictionary() as AnyObject
        d["Ping"] = NSNumber(value: ping)
        return d
    }

    func toJsonConfig() -> [String: AnyObject] {
        var conf: [String: AnyObject] = ["password": password as AnyObject,
                                         "method": method as AnyObject,]
        
        let defaults = UserDefaults.standard
        conf["local_port"] = NSNumber(value: UInt16(defaults.integer(forKey: "LocalSocks5.ListenPort")) as UInt16)
        conf["local_address"] = defaults.string(forKey: "LocalSocks5.ListenAddress") as AnyObject?
        conf["timeout"] = NSNumber(value: UInt32(defaults.integer(forKey: "LocalSocks5.Timeout")) as UInt32)
        if ota {
            conf["auth"] = NSNumber(value: ota as Bool)
        }
        
        if enabledKcptun {
            let localHost = defaults.string(forKey: "Kcptun.LocalHost")
            let localPort = uint16(defaults.integer(forKey: "Kcptun.LocalPort"))
            
            conf["server"] = localHost as AnyObject
            conf["server_port"] = NSNumber(value: localPort as UInt16)
        } else {
            conf["server"] = serverHost as AnyObject
            conf["server_port"] = NSNumber(value: serverPort as UInt16)
        }

        return conf
    }
    
    func toKcptunJsonConfig() -> [String: AnyObject] {
        var conf = kcptunProfile.toJsonConfig()
        if serverHost.contains(Character(":")) {
            conf["remoteaddr"] = "[\(serverHost)]:\(serverPort)" as AnyObject
        } else {
            conf["remoteaddr"] = "\(serverHost):\(serverPort)" as AnyObject
        }

        return conf
    }

    func isValid() -> Bool {
        func validateIpAddress(_ ipToValidate: String) -> Bool {

            var sin = sockaddr_in()
            var sin6 = sockaddr_in6()

            if ipToValidate.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
                // IPv6 peer.
                return true
            }
            else if ipToValidate.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
                // IPv4 peer.
                return true
            }

            return false;
        }

        func validateDomainName(_ value: String) -> Bool {
            let validHostnameRegex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"

            if (value.range(of: validHostnameRegex, options: .regularExpression) != nil) {
                return true
            } else {
                return false
            }
        }

        if !(validateIpAddress(serverHost) || validateDomainName(serverHost)){
            return false
        }

        if password.isEmpty {
            return false
        }

        return true
    }

    private func makeLegacyURL() -> URL? {
        var url = URLComponents()

        url.host = serverHost
        url.user = method
        url.password = password
        url.port = Int(serverPort)

        url.queryItems = [URLQueryItem(name: "Remark", value: remark),
                          URLQueryItem(name: "OTA", value: ota.description)]
        if enabledKcptun {
            url.queryItems?.append(contentsOf: [
                URLQueryItem(name: "Kcptun", value: enabledKcptun.description),
                ])
            url.queryItems?.append(contentsOf: kcptunProfile.urlQueryItems())
        }

        let parts = url.string?.replacingOccurrences(
            of: "//", with: "",
            options: String.CompareOptions.anchored, range: nil)

        let base64String = parts?.data(using: String.Encoding.utf8)?
            .base64EncodedString(options: Data.Base64EncodingOptions())
        if var s = base64String {
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "="))
            return Foundation.URL(string: "ss://\(s)")
        }
        return nil
    }

    func URL(legacy: Bool = false) -> URL? {
        // If you want the URL from <= 1.5.1
        if (legacy) {
            return self.makeLegacyURL()
        }

        guard let rawUserInfo = "\(method):\(password)".data(using: .utf8) else {
            return nil
        }
        let paddings = CharacterSet(charactersIn: "=")
        let userInfo = rawUserInfo.base64EncodedString().trimmingCharacters(in: paddings)

        var items = [URLQueryItem(name: "OTA", value: ota.description)]
        if enabledKcptun {
            items.append(URLQueryItem(name: "Kcptun", value: enabledKcptun.description))
            items.append(contentsOf: kcptunProfile.urlQueryItems())
        }

        var comps = URLComponents()

        comps.scheme = "ss"
        comps.host = serverHost
        comps.port = Int(serverPort)
        comps.user = userInfo
        comps.path = "/"  // This is required by SIP0002 for URLs with fragment or query
        comps.fragment = remark
        comps.queryItems = items

        let url = try? comps.asURL()

        return url
    }
    
    func title() -> String {
        var ping = self.ping == 0 ? "" : "(\(self.ping)ms)"
        if self.ping == -1 {
            ping = "(\("Timeout".localized))"
        }
        if remark.isEmpty {
            return "\(serverHost):\(serverPort)\(ping)"
        } else {
            return "\(remark) (\(serverHost):\(serverPort))\(ping)"
        }
    }
    
    func refreshPing() {
        PingUtil.pingHost(serverHost, success: { (ping) in
            self.ping = ping
        }, failure: {
            NSLog("Ping %@ fail", self.serverHost)
        })
    }
}
