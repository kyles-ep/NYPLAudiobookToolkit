import CommonCrypto

class FeedbookDRMProcessor {
    class func processManifest(_ manifest: [String: Any], drmData: inout [String: Any]) -> Bool {
        guard let metadata = manifest["metadata"] as? [String: Any] else {
            ATLog(.info, "[FeedbookDRMProcessor] no metadata in manifest")
            return true
        }
        
        // Perform Feedbooks DRM rights check
        if let feedbooksRights = metadata["http://www.feedbooks.com/audiobooks/rights"] as? [String: Any] {
            if let startDate = DateUtils.parseDate((feedbooksRights["start"] as? String) ?? "") {
                if Date() < startDate {
                    ATLog(.error, "Feedbook DRM rights start date is in the future!")
                    return false
                }
            }
            if let endDate = DateUtils.parseDate((feedbooksRights["end"] as? String) ?? "") {
                if Date() > endDate {
                    ATLog(.error, "Feedbook DRM rights end date is expired!")
                    return false
                }
            }
        }
        
        // Perform Feedbooks DRM license status check
        let licenseCheckUrl: URL?
        if let links = manifest["links"] as? [[String: Any]] {
            var href = ""
            var found = false
            for link in links {
                if (link["rel"] as? String) == "license" {
                    if found {
                        ATLog(.warn, "[Feedbook License Status Check] More than one license status link found?! href:\(link["href"] ?? "") type:\(link["type"] ?? "")")
                        continue
                    }
                    found = true
                    href = (link["href"] as? String) ?? ""
                }
            }
            licenseCheckUrl = URL(string: href)
            drmData["status"] = DrmStatus.processing
        } else {
            licenseCheckUrl = nil
        }
        if licenseCheckUrl != nil {
            drmData["licenseCheckUrl"] = licenseCheckUrl!
        }
        
        // Perform Feedbooks manifest validation
        // TODO:
        
        return true
    }
    
    class func performAsyncDrm(book: OpenAccessAudiobook, drmData: [String: Any]) {
        if let licenseCheckUrl = drmData["licenseCheckUrl"] as? URL {
            weak var weakBook = book
            URLSession.shared.dataTask(with: licenseCheckUrl) { (data, response, error) in
                // Errors automatically mean success
                if error != nil {
                    weakBook?.drmStatus = .succeeded
                    ATLog(.debug, "feedbooks::performAsyncDrm licenseCheck skip due to error: \(error!)")
                    return
                }
                
                // Explicitly check status value
                if data != nil {
                    if let jsonObj = try? JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions()) as? [String: Any],
                        let statusString = jsonObj?["status"] as? String {
                        if statusString != "ready" && statusString != "active" {
                            ATLog(.debug, "feedbooks::performAsyncDrm licenseCheck failed: \((try? JSONUtils.canonicalize(jsonObj: jsonObj) as String) ?? "")")
                            weakBook?.drmStatus = .failed
                            return
                        }
                    }
                }

                // Fallthrough on all other cases
                weakBook?.drmStatus = .succeeded
                ATLog(.debug, "feedbooks::performAsyncDrm licenseCheck fallthrough")
            }
        } else {
            book.drmStatus = .succeeded
            ATLog(.debug, "feedbooks::performAsyncDrm licenseCheck not needed")
        }
    }
    
    class func getFeedbookSecret(profile: String) -> String {
        let tag = "feedbook_drm_profile_\(profile)"
        let tagData = tag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecReturnData as String: true
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess {
            if item == nil {
                ATLog(.error, "Keychain item is nil for profile: \(profile)")
            } else if let sItem = item as? String {
                return sItem
            } else if let dItem = item as? Data {
                ATLog(.warn, "Keychain item was data instead of string for profile: \(profile)")
                return String.init(data: dItem, encoding: .utf8) ?? ""
            } else {
                ATLog(.error, "Keychain item unknown error for profile: \(profile)")
            }
        } else {
            ATLog(.error, "Could not fetch keychain item for profile: \(profile)")
        }
        return ""
    }
    
    class func getJWTToken(profile: String, resourceUri: String) -> String {
        let headerObj = [
            "alg" : "HS256",
            "typ" : "JWT"
        ]
        guard let headerJSON = try? JSONUtils.canonicalize(jsonObj: headerObj) else {
            return ""
        }
        let claimsObj = [
            "iss" : "https://librarysimplified.org/products/SimplyE",
            "sub" : resourceUri,
            "jti" : UUID.init().uuidString
        ]
        guard let claimsJSON = try? JSONUtils.canonicalize(jsonObj: claimsObj) else {
            return ""
        }
        let header = headerJSON.data(using: .utf8)!.urlSafeBase64(padding: false)
        let claims = claimsJSON.data(using: .utf8)!.urlSafeBase64(padding: false)
        let preSigned = "\(header).\(claims)"
        
        let signed = preSigned.hmac(algorithm: .sha256, key: Data.init(base64Encoded: getFeedbookSecret(profile: profile)) ?? Data()).urlSafeBase64(padding: false)
        return "\(header).\(claims).\(signed)"
    }
}