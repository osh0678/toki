#!/usr/bin/env swift

// Creates the Ed25519 release signing key.
//
// Run once, ever:
//
//     swift scripts/make-release-key.swift
//
// The private key is written to ~/.toki/release.key and never enters this repository.
// The public key is printed as hex, to be pasted into
// `UpdateInstaller.releasePublicKeyHex`. Only the public half is compiled into the app,
// so shipping Toki gives away nothing that can sign a release.
//
// Losing this key is not recoverable: copies of Toki already carrying the old public key
// will reject anything signed with a new one, and those installs fall back to the manual
// browser download until they are updated by hand once.

import CryptoKit
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser
let directory = home.appending(path: ".toki")
let keyFile = directory.appending(path: "release.key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// Refuse rather than overwrite. Regenerating on top of an existing key would silently
// invalidate every release signed with it, and there is no undo.
if FileManager.default.fileExists(atPath: keyFile.path) {
    fail("""
    \(keyFile.path) already exists.
    Delete it deliberately if you really mean to retire the current release key.
    """)
}

let privateKey = Curve25519.Signing.PrivateKey()
let privateHex = privateKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
let publicHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

do {
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        // Owner-only from the moment it exists, rather than created wide and narrowed
        // afterwards — the gap between those two would be a world-readable private key.
        attributes: [.posixPermissions: 0o700]
    )
    try Data(privateHex.utf8).write(to: keyFile, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
} catch {
    fail("could not write \(keyFile.path): \(error.localizedDescription)")
}

print("""
release key created

  private  \(keyFile.path)  (mode 0600 — never commit, never copy into the repo)
  public   \(publicHex)

Next: paste the public key into Sources/Toki/Providers/UpdateInstaller.swift

    static let releasePublicKeyHex = "\(publicHex)"

Until that line is filled in, automatic installation stays switched off and the update
card falls back to the manual browser download.
""")
