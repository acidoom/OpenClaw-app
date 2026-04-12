//
//  PDFCacheManager.swift
//  OpenClaw
//
//  Manages PDF file download from Zotero API and local caching
//

import Foundation

enum PDFCacheError: Error, LocalizedError {
    case notAPDF
    
    var errorDescription: String? {
        switch self {
        case .notAPDF:
            return "The downloaded file is not a valid PDF. The attachment may be a linked file not stored on Zotero servers."
        }
    }
}

actor PDFCacheManager {
    static let shared = PDFCacheManager()
    
    private let fileManager = FileManager.default
    
    private var cacheDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ZoteroPDFs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private init() {}
    
    // MARK: - Cache Check
    
    func cachedFileURL(for itemKey: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(itemKey).pdf")
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
    
    func isCached(itemKey: String) -> Bool {
        cachedFileURL(for: itemKey) != nil
    }
    
    // MARK: - Download and Cache
    
    func downloadAndCache(itemKey: String) async throws -> URL {
        // Check cache first
        if let cached = cachedFileURL(for: itemKey) {
            print("[PDFCache] Cache hit for \(itemKey)")
            return cached
        }
        
        print("[PDFCache] Cache miss, downloading \(itemKey)")
        
        let data = try await ZoteroService.shared.downloadPDFFile(key: itemKey)
        
        // Validate PDF magic bytes (%PDF)
        let pdfMagic: [UInt8] = [0x25, 0x50, 0x44, 0x46] // %PDF
        let headerBytes = [UInt8](data.prefix(4))
        guard headerBytes == pdfMagic else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "binary data"
            print("[PDFCache] Downloaded data is not a PDF. First bytes: \(headerBytes). Preview: \(preview)")
            throw PDFCacheError.notAPDF
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(itemKey).pdf")
        try data.write(to: fileURL)
        
        print("[PDFCache] Cached \(data.count) bytes to \(fileURL.lastPathComponent)")
        return fileURL
    }
    
    // MARK: - Cache Management
    
    func deleteCachedPDF(itemKey: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(itemKey).pdf")
        try? fileManager.removeItem(at: fileURL)
        print("[PDFCache] Deleted cache for \(itemKey)")
    }
    
    func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("[PDFCache] Cache cleared")
    }
    
    var formattedCacheSize: String {
        let bytes = cacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
