//
//  CoverImageView.swift
//  OpenClaw
//
//  Authenticated cover image view for audiobooks
//

import SwiftUI

struct CoverImageView: View {
    let coverUrl: String?
    let cornerRadius: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false
    
    init(coverUrl: String?, cornerRadius: CGFloat = 12) {
        self.coverUrl = coverUrl
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                placeholder
                    .overlay(ProgressView().tint(Color.anthropicCoral))
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: coverUrl) {
            await loadImage()
        }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.surfaceSecondary)
            .overlay(
                Image(systemName: "headphones")
                    .font(.title2)
                    .foregroundStyle(Color.textTertiary)
            )
    }
    
    private func loadImage() async {
        guard let coverUrl, !coverUrl.isEmpty else {
            print("[CoverImage] No coverUrl provided")
            isLoading = false
            return
        }
        
        print("[CoverImage] Loading: \(coverUrl)")
        
        // Check cache first
        if let cached = CoverImageCache.shared.get(coverUrl) {
            image = cached
            isLoading = false
            return
        }
        
        isLoading = true
        hasFailed = false
        
        // If it's an absolute URL (Libro.fm covers), fetch without auth
        if coverUrl.hasPrefix("http") {
            do {
                let (data, response) = try await URLSession.shared.data(from: URL(string: coverUrl)!)
                let httpResponse = response as? HTTPURLResponse
                print("[CoverImage] HTTP \(httpResponse?.statusCode ?? 0) for \(coverUrl), data size: \(data.count)")
                if let uiImage = UIImage(data: data) {
                    CoverImageCache.shared.set(coverUrl, image: uiImage)
                    image = uiImage
                } else {
                    print("[CoverImage] Failed to decode image data")
                    hasFailed = true
                }
            } catch {
                print("[CoverImage] Fetch error: \(error)")
                hasFailed = true
            }
            isLoading = false
            return
        }
        
        // Relative path — fetch with auth via LibroAIService
        do {
            let data = try await LibroAIService.shared.fetchCoverImageData(coverPath: coverUrl)
            print("[CoverImage] Auth fetch got \(data.count) bytes for \(coverUrl)")
            if let uiImage = UIImage(data: data) {
                CoverImageCache.shared.set(coverUrl, image: uiImage)
                image = uiImage
            } else {
                print("[CoverImage] Failed to decode image data from auth fetch")
                hasFailed = true
            }
        } catch {
            print("[CoverImage] Auth fetch error for \(coverUrl): \(error)")
            hasFailed = true
        }
        isLoading = false
    }
}

// MARK: - Image Cache

final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 50
    }
    
    func get(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func set(_ key: String, image: UIImage) {
        cache.setObject(image, forKey: key as NSString)
    }
}
