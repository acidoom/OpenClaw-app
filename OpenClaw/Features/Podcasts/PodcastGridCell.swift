//
//  PodcastGridCell.swift
//  OpenClaw
//
//  Grid cell for displaying a subscribed podcast
//

import SwiftUI

struct PodcastGridCell: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork
            AsyncImage(url: URL(string: podcast.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                    )
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Title
            Text(podcast.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            
            // Author
            Text(podcast.author)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            
            // Episode count
            if let count = podcast.episodeCount {
                Text("\(count) episodes")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}
