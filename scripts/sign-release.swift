#!/usr/bin/env swift

// Signs a release archive with the Ed25519 key made by make-release-key.swift.
//
//     swift scripts/sign-release.swift dist/Toki.aar
//
// Writes dist/Toki.aar.sig — exactly 64 raw bytes, the length `UpdateInstaller` insists
// on. Both files must be attached to the GitHub release; the app refuses to install
// without a signature it can verify.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: swift scripts/sign-release.swift <file>")
}

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let keyFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".toki/release.key")

guard let keyText = try? String(contentsOf: keyFile, encoding: .utf8) else {
    fail("no release key at \(keyFile.path) — run: swift scripts/make-release-key.swift")
}

let hex = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
var keyBytes = [UInt8]()
var index = hex.startIndex
while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
    guard let byte = UInt8(hex[index ..< next], radix: 16) else { fail("release key is not hex") }
    keyBytes.append(byte)
    index = next
}

guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: Data(keyBytes)) else {
    fail("release key is not a valid Ed25519 private key")
}

// Mapped rather than read whole: the archive is small today, but signing should not
// depend on the entire release fitting in memory.
guard let payload = try? Data(contentsOf: target, options: .mappedIfSafe) else {
    fail("could not read \(target.path)")
}

guard let signature = try? privateKey.signature(for: payload) else {
    fail("signing failed")
}

// Verify with the public half before writing anything out. A signature that does not
// verify here fails silently in the app, where the only symptom is an update that never
// installs and no visible reason why.
guard privateKey.publicKey.isValidSignature(signature, for: payload) else {
    fail("signature did not verify against its own public key — refusing to write it")
}

let output = URL(fileURLWithPath: target.path + ".sig")
do {
    try signature.write(to: output, options: [.atomic])
} catch {
    fail("could not write \(output.path): \(error.localizedDescription)")
}

let publicHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
print("""
signed \(target.lastPathComponent)

  signature  \(output.path)  (\(signature.count) bytes)
  public key \(publicHex)

The public key above must match `UpdateInstaller.releasePublicKeyHex` in the build being
released, or installed copies will reject this archive.
""")
