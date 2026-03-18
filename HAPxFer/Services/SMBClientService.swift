import Foundation

// MARK: - Deprecated
// This file previously contained the SMBClient (SMB2+) implementation.
// It has been replaced by LibSMBClientService which uses libsmbclient (Samba)
// for SMB1 (NT1) protocol support required by the Sony HAP-Z1ES.
//
// The SMBServiceProtocol abstraction in SMBService.swift made this a
// drop-in replacement — only the AppState initializer line changed.
