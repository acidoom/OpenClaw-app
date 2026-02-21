//
//  ZoteroTypes.swift
//  OpenClaw
//
//  Models for Zotero library integration
//

import Foundation

// MARK: - Zotero Item Types

enum ZoteroItemType: String, Codable, CaseIterable {
    case journalArticle
    case book
    case bookSection
    case conferencePaper
    case thesis
    case report
    case webpage
    case note
    case attachment
    case document
    case presentation
    case videoRecording
    case audioRecording
    case podcast
    case blogPost
    case forumPost
    case email
    case letter
    case manuscript
    case patent
    case statute
    case bill
    case hearing
    case film
    case tvBroadcast
    case radioBroadcast
    case artwork
    case map
    case computerProgram
    case dictionaryEntry
    case encyclopediaArticle
    case interview
    case magazineArticle
    case newspaperArticle
    case preprint
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ZoteroItemType(rawValue: rawValue) ?? .unknown
    }
    
    var displayName: String {
        switch self {
        case .journalArticle: return "Journal Article"
        case .book: return "Book"
        case .bookSection: return "Book Section"
        case .conferencePaper: return "Conference Paper"
        case .thesis: return "Thesis"
        case .report: return "Report"
        case .webpage: return "Web Page"
        case .note: return "Note"
        case .attachment: return "Attachment"
        case .document: return "Document"
        case .presentation: return "Presentation"
        case .videoRecording: return "Video"
        case .audioRecording: return "Audio"
        case .podcast: return "Podcast"
        case .blogPost: return "Blog Post"
        case .forumPost: return "Forum Post"
        case .email: return "Email"
        case .letter: return "Letter"
        case .manuscript: return "Manuscript"
        case .patent: return "Patent"
        case .statute: return "Statute"
        case .bill: return "Bill"
        case .hearing: return "Hearing"
        case .film: return "Film"
        case .tvBroadcast: return "TV Broadcast"
        case .radioBroadcast: return "Radio Broadcast"
        case .artwork: return "Artwork"
        case .map: return "Map"
        case .computerProgram: return "Software"
        case .dictionaryEntry: return "Dictionary Entry"
        case .encyclopediaArticle: return "Encyclopedia Article"
        case .interview: return "Interview"
        case .magazineArticle: return "Magazine Article"
        case .newspaperArticle: return "Newspaper Article"
        case .preprint: return "Preprint"
        case .unknown: return "Item"
        }
    }
    
    var iconName: String {
        switch self {
        case .journalArticle, .magazineArticle, .newspaperArticle:
            return "doc.text"
        case .book, .bookSection:
            return "book.closed"
        case .conferencePaper, .presentation:
            return "person.3"
        case .thesis, .report, .document, .manuscript:
            return "doc"
        case .webpage, .blogPost, .forumPost:
            return "globe"
        case .note:
            return "note.text"
        case .attachment:
            return "paperclip"
        case .videoRecording, .film, .tvBroadcast:
            return "video"
        case .audioRecording, .podcast, .radioBroadcast:
            return "waveform"
        case .email, .letter:
            return "envelope"
        case .patent:
            return "seal"
        case .artwork:
            return "photo.artframe"
        case .map:
            return "map"
        case .computerProgram:
            return "desktopcomputer"
        case .preprint:
            return "doc.badge.clock"
        default:
            return "doc"
        }
    }
}

// MARK: - Zotero Creator

struct ZoteroCreator: Codable, Identifiable, Equatable {
    var id: String { "\(creatorType)-\(firstName ?? "")-\(lastName ?? "")" }
    
    let creatorType: String
    let firstName: String?
    let lastName: String?
    let name: String?
    
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        let first = firstName ?? ""
        let last = lastName ?? ""
        if first.isEmpty && last.isEmpty {
            return "Unknown"
        }
        return [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Zotero Tag

struct ZoteroTag: Codable, Identifiable, Equatable, Hashable {
    var id: String { tag }
    
    let tag: String
    let type: Int?
    
    init(tag: String, type: Int? = nil) {
        self.tag = tag
        self.type = type
    }
}

// MARK: - Zotero Item Data

struct ZoteroItemData: Codable, Equatable {
    let key: String
    let version: Int
    let itemType: ZoteroItemType
    let title: String?
    let abstractNote: String?
    let creators: [ZoteroCreator]?
    let tags: [ZoteroTag]?
    let date: String?
    let dateAdded: String?
    let dateModified: String?
    let url: String?
    let DOI: String?
    let publicationTitle: String?
    let volume: String?
    let issue: String?
    let pages: String?
    let publisher: String?
    let place: String?
    let note: String?
    let parentItem: String?
    let contentType: String?
    let filename: String?
    let linkMode: String?
    
    // Custom decoder to handle unknown fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        version = try container.decode(Int.self, forKey: .version)
        itemType = try container.decode(ZoteroItemType.self, forKey: .itemType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        abstractNote = try container.decodeIfPresent(String.self, forKey: .abstractNote)
        creators = try container.decodeIfPresent([ZoteroCreator].self, forKey: .creators)
        tags = try container.decodeIfPresent([ZoteroTag].self, forKey: .tags)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        dateAdded = try container.decodeIfPresent(String.self, forKey: .dateAdded)
        dateModified = try container.decodeIfPresent(String.self, forKey: .dateModified)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        DOI = try container.decodeIfPresent(String.self, forKey: .DOI)
        publicationTitle = try container.decodeIfPresent(String.self, forKey: .publicationTitle)
        volume = try container.decodeIfPresent(String.self, forKey: .volume)
        issue = try container.decodeIfPresent(String.self, forKey: .issue)
        pages = try container.decodeIfPresent(String.self, forKey: .pages)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        place = try container.decodeIfPresent(String.self, forKey: .place)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        parentItem = try container.decodeIfPresent(String.self, forKey: .parentItem)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        linkMode = try container.decodeIfPresent(String.self, forKey: .linkMode)
    }
    
    private enum CodingKeys: String, CodingKey {
        case key, version, itemType, title, abstractNote, creators, tags
        case date, dateAdded, dateModified, url, DOI, publicationTitle
        case volume, issue, pages, publisher, place, note, parentItem
        case contentType, filename, linkMode
    }
    
    init(key: String, version: Int, itemType: ZoteroItemType, title: String?, abstractNote: String?,
         creators: [ZoteroCreator]?, tags: [ZoteroTag]?, date: String?, dateAdded: String?,
         dateModified: String?, url: String?, DOI: String?, publicationTitle: String?,
         volume: String?, issue: String?, pages: String?, publisher: String?, place: String?,
         note: String?, parentItem: String?, contentType: String?, filename: String?, linkMode: String?) {
        self.key = key
        self.version = version
        self.itemType = itemType
        self.title = title
        self.abstractNote = abstractNote
        self.creators = creators
        self.tags = tags
        self.date = date
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.url = url
        self.DOI = DOI
        self.publicationTitle = publicationTitle
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.publisher = publisher
        self.place = place
        self.note = note
        self.parentItem = parentItem
        self.contentType = contentType
        self.filename = filename
        self.linkMode = linkMode
    }
    
    var displayTitle: String {
        title ?? filename ?? "Untitled"
    }
    
    var authorsString: String {
        guard let creators = creators else { return "" }
        let authors = creators.filter { $0.creatorType == "author" }
        if authors.isEmpty {
            return creators.first?.displayName ?? ""
        }
        if authors.count == 1 {
            return authors[0].displayName
        }
        if authors.count == 2 {
            return "\(authors[0].displayName) & \(authors[1].displayName)"
        }
        return "\(authors[0].displayName) et al."
    }
    
    var formattedDate: String? {
        guard let date = date, !date.isEmpty else { return nil }
        // Zotero dates can be various formats, try to parse year
        if let year = date.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first(where: { $0.count == 4 }) {
            return year
        }
        return date
    }
    
    var citation: String {
        var parts: [String] = []
        if !authorsString.isEmpty {
            parts.append(authorsString)
        }
        if let year = formattedDate {
            parts.append("(\(year))")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Zotero Item (Full Response)

struct ZoteroItem: Codable, Identifiable, Equatable {
    let key: String
    let version: Int
    let library: ZoteroLibrary
    let data: ZoteroItemData
    
    var id: String { key }
    
    struct ZoteroLibrary: Codable, Equatable {
        let type: String
        let id: Int
        let name: String
        
        // Handle additional fields gracefully
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
        }
        
        private enum CodingKeys: String, CodingKey {
            case type, id, name
        }
        
        init(type: String, id: Int, name: String) {
            self.type = type
            self.id = id
            self.name = name
        }
    }
    
    // Handle additional fields in response
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        version = try container.decode(Int.self, forKey: .version)
        library = try container.decode(ZoteroLibrary.self, forKey: .library)
        data = try container.decode(ZoteroItemData.self, forKey: .data)
    }
    
    private enum CodingKeys: String, CodingKey {
        case key, version, library, data
    }
    
    init(key: String, version: Int, library: ZoteroLibrary, data: ZoteroItemData) {
        self.key = key
        self.version = version
        self.library = library
        self.data = data
    }
}

// MARK: - Zotero Collection

struct ZoteroCollection: Codable, Identifiable, Equatable {
    let key: String
    let version: Int
    let data: ZoteroCollectionData
    
    var id: String { key }
    
    struct ZoteroCollectionData: Codable, Equatable {
        let key: String
        let name: String
        let parentCollection: String?
        let version: Int
        
        // Custom decoder to handle parentCollection being either String or false (bool)
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            name = try container.decode(String.self, forKey: .name)
            version = try container.decode(Int.self, forKey: .version)
            
            // parentCollection can be a String or false (boolean)
            if let stringValue = try? container.decode(String.self, forKey: .parentCollection) {
                parentCollection = stringValue
            } else {
                parentCollection = nil
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case key, name, parentCollection, version
        }
    }
    
    var name: String { data.name }
    var parentKey: String? { data.parentCollection }
}

// MARK: - Zotero Note (Child Item)

struct ZoteroNote: Identifiable, Equatable {
    let key: String
    let note: String
    let dateModified: String?
    
    var id: String { key }
    
    var plainTextNote: String {
        // Strip HTML tags from note
        note.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var previewText: String {
        let plain = plainTextNote
        if plain.count > 200 {
            return String(plain.prefix(200)) + "..."
        }
        return plain
    }
}

// MARK: - API Response Types

struct ZoteroItemsResponse: Codable {
    let items: [ZoteroItem]
    let totalResults: Int?
    let startIndex: Int?
}

// MARK: - Filter Options

enum ZoteroSortField: String, CaseIterable {
    case dateModified
    case dateAdded
    case title
    case creator
    case date
    
    var displayName: String {
        switch self {
        case .dateModified: return "Date Modified"
        case .dateAdded: return "Date Added"
        case .title: return "Title"
        case .creator: return "Author"
        case .date: return "Publication Date"
        }
    }
}

enum ZoteroSortDirection: String {
    case asc
    case desc
    
    var displayName: String {
        switch self {
        case .asc: return "Ascending"
        case .desc: return "Descending"
        }
    }
}
