import Foundation
import Security
import ShimaCore

/// Reads Shima.app's own code signature (local, no network). Called once, on the first settings refresh.
enum SigningInfo {
    static func read(bundleURL: URL = Bundle.main.bundleURL) -> SigningSummary {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return .unreadable }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return .unreadable }
        guard let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return .adHoc }
        let name = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "Unknown"
        return .certificate(commonName: name, notAfter: notAfter(leaf))
    }

    private static func notAfter(_ certificate: SecCertificate) -> Date? {
        if #available(macOS 15, *) {
            return SecCertificateCopyNotValidAfterDate(certificate) as Date?
        }
        let key = kSecOIDX509V1ValidityNotAfter
        guard let values = SecCertificateCopyValues(certificate, [key] as CFArray, nil) as? [String: Any],
              let entry = values[key as String] as? [String: Any],
              let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }
}
