import Foundation
import Security

// MARK: - Models (minimal fields we need from Blogger)

struct BloggerBlog: Decodable {
	let feed: BloggerFeed
}

struct BloggerFeed: Decodable {
    let entry: [BloggerEntry]?
}

struct BloggerEntry: Decodable {
    struct WrappedString: Decodable {
        let t: String
        private enum CodingKeys: String, CodingKey { case t = "$t" }
    }
    struct Link: Decodable {
        let rel: String
        let type: String?
        let href: String
        let title: String?
    }
    let id: WrappedString
    let published: WrappedString
    let updated: WrappedString
    let title: WrappedString?
    let content: Content?
    let link: [Link]?
    let author: [Author]?
    let media$thumbnail: MediaThumb?
    let thr$total: WrappedString?

    struct Content: Decodable {
        let type: String?
        let t: String
        private enum CodingKeys: String, CodingKey { case type, t = "$t" }
    }
    struct Author: Decodable {
        struct Name: Decodable { let t: String; private enum CodingKeys: String, CodingKey { case t = "$t" } }
        let name: Name
    }
    struct MediaThumb: Decodable {
        let url: String
        let height: String?
        let width: String?
    }
}

// MARK: - Ghost post (matches your sample keys)

struct GhostPosts: Encodable {
    var posts: [GhostPost]
}

struct GhostPost: Encodable {
    let id: String
    let uuid: String
    let title: String
    let slug: String
    let mobiledoc: String?
    let lexical: String?
    let html: String
    let comment_id: String
    let plaintext: String
    let feature_image: String?
    let feature_image_caption: String?
    let featured: Int
    let type: String
    let status: String
    let locale: String?
    let visibility: String
    let email_recipient_filter: String
    let created_at: String
    let updated_at: String
    let published_at: String
    let custom_excerpt: String?
    let codeinjection_head: String?
    let codeinjection_foot: String?
    let custom_template: String?
    let canonical_url: String?
    let newsletter_id: String?
    let show_title_and_feature_image: Int
}

// MARK: - Utilities

enum AppError: Error, CustomStringConvertible {
    case usage
    case readInput(String)
    case parseInput(String)
    case noEntries
    case writeOutput(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: blogger2ghost <input.json> [-o output.json]"
        case .readInput(let p):
            return "Failed to read input file: \(p)"
        case .parseInput(let why):
            return "Failed to parse Blogger JSON: \(why)"
        case .noEntries:
            return "No entries found in Blogger JSON."
        case .writeOutput(let why):
            return "Failed to write output: \(why)"
        }
    }
}

func readFile(path: String) throws -> Data {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else { throw AppError.readInput(path) }
    return data
}

func writeFile(path: String, data: Data) throws {
    let url = URL(fileURLWithPath: path)
    do {
        try data.write(to: url)
    } catch {
        throw AppError.writeOutput(error.localizedDescription)
    }
}

func iso8601ZString(from bloggerTimestamp: String) -> String {
    // Blogger example: 2025-11-05T09:43:27.720-05:00  or 2016-02-24T16:39:00.000-05:00
    let fmts = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ"
    ]
    let inFmt = DateFormatter()
    inFmt.locale = Locale(identifier: "en_US_POSIX")
    var date: Date?
    for f in fmts {
        inFmt.dateFormat = f
        if let d = inFmt.date(from: bloggerTimestamp) { date = d; break }
    }
    let outFmt = ISO8601DateFormatter()
    outFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return outFmt.string(from: date ?? Date())
}

func stripBloggerFooterAndScripts(html: String) -> String {
    var s = html

    // Remove Blogger "blogger-post-footer" blocks
    let footerPattern = #"<div[^>]*class="blogger-post-footer"[^>]*>.*?</div>"#
    s = s.replacingOccurrences(of: footerPattern,
                               with: "",
                               options: [.regularExpression, .caseInsensitive])

    // Remove any <script>...</script> across newlines (no .dotMatchesLineSeparators; use [\s\S])
    let scriptPattern = #"<script\b[^>]*>[\s\S]*?</script>"#
    s = s.replacingOccurrences(of: scriptPattern,
                               with: "",
                               options: [.regularExpression, .caseInsensitive])

    // Trim residual empty centers/paras
    s = s.replacingOccurrences(of: #"<center>\s*</center>"#,
                               with: "",
                               options: [.regularExpression])
    s = s.replacingOccurrences(of: #"<p>\s*&nbsp;\s*</p>"#,
                               with: "",
                               options: [.regularExpression])

    return s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}

// Minimal HTML entity decoding (decimal, hex, and common named entities).
func decodeHTMLEntities(_ s: String) -> String {
    var out = s
    // Named entities
    let named: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " "
    ]
    for (name, repl) in named {
        out = out.replacingOccurrences(of: "&\(name);", with: repl)
    }
    // Decimal numeric entities &#1234;
    if let reDec = try? NSRegularExpression(pattern: #"&#(\d+);"#, options: []) {
        let m = reDec.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
        for match in m {
            if match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: out),
               let code = Int(out[r]), let scalar = UnicodeScalar(code) {
                out.replaceSubrange(Range(match.range, in: out)!, with: String(scalar))
            }
        }
    }
    // Hex numeric entities &#x1F4A9;
    if let reHex = try? NSRegularExpression(pattern: #"&#x([0-9a-fA-F]+);"#, options: []) {
        let m = reHex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
        for match in m {
            if match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: out),
               let code = UInt32(out[r], radix: 16), let scalar = UnicodeScalar(code) {
                out.replaceSubrange(Range(match.range, in: out)!, with: String(scalar))
            }
        }
    }
    return out
}

func htmlToPlaintext(_ html: String) -> String {
    // Strip tags, then decode entities.
    let noTags = html.replacingOccurrences(of: "<[^>]+>",
                                           with: "",
                                           options: .regularExpression)
    let decoded = decodeHTMLEntities(noTags)
    return decoded.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}

func random24Hex() -> String {
    var bytes = [UInt8](repeating: 0, count: 12)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}

func slugify(_ s: String) -> String {
    let lower = s.lowercased()
    // Strip trailing ".html" if present
    let withoutExt = lower.hasSuffix(".html") ? String(lower.dropLast(5)) : lower
    let replaced = withoutExt.replacingOccurrences(of: #"[^a-z0-9]+"#,
                                                   with: "-",
                                                   options: .regularExpression)
    let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "untitled" : trimmed
}

func titleFrom(_ entry: BloggerEntry) -> String {
    let t = entry.title?.t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    if !t.isEmpty { return t }
    if let alt = entry.link?.first(where: { $0.rel == "alternate" })?.href,
       let last = URL(string: alt)?.lastPathComponent, !last.isEmpty {
        let byDashes = last.replacingOccurrences(of: "-", with: " ")
        let decoded = byDashes.removingPercentEncoding ?? byDashes
        let words = decoded.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !words.isEmpty { return words }
    }
    return "Post \(entry.published.t.prefix(10))"
}

func slugFrom(_ entry: BloggerEntry, title: String) -> String {
    if let alt = entry.link?.first(where: { $0.rel == "alternate" })?.href,
       let last = URL(string: alt)?.lastPathComponent, !last.isEmpty {
        return slugify(last)
    }
    return slugify(title)
}

func buildGhostPost(from entry: BloggerEntry) -> GhostPost {
    let title = titleFrom(entry)
    let slug = slugFrom(entry, title: title)
    let htmlRaw = entry.content?.t ?? ""
	let cleanedHTML = stripBloggerFooterAndScripts(html: htmlRaw)
	let simplifiedImagesHTML = replaceBloggerTablesWithFilenameAndCaption(in: cleanedHTML)
	let plaintext = htmlToPlaintext(simplifiedImagesHTML)

    let createdAt = iso8601ZString(from: entry.published.t)
    let updatedAt = iso8601ZString(from: entry.updated.t)
    let publishedAt = createdAt

    let id = random24Hex()
    let uuid = UUID().uuidString.lowercased()

	let featurePath: String
	if 
		let mediaUrl = entry.media$thumbnail?.url,
		let featureName = URL(string: mediaUrl)?.lastPathComponent, 
		featureName.isEmpty == false 
	{
		featurePath = "__GHOST_URL__/content/images/2025/10/" + featureName
	}
	else {
		featurePath = ""
	}
	
    return GhostPost(
        id: id,
        uuid: uuid,
        title: title,
        slug: slug,
        mobiledoc: nil,
        lexical: nil,
        html: simplifiedImagesHTML,
        comment_id: id,
        plaintext: plaintext,
        feature_image: featurePath,
        feature_image_caption: "",
        featured: 0,
        type: "post",
        status: "draft", // "published"
        locale: nil,
        visibility: "public",
        email_recipient_filter: "all",
        created_at: createdAt,
        updated_at: updatedAt,
        published_at: publishedAt,
        custom_excerpt: nil,
        codeinjection_head: nil,
        codeinjection_foot: nil,
        custom_template: nil,
        canonical_url: nil,
        newsletter_id: nil,
        show_title_and_feature_image: 1
    )
}

// Replace Blogger <table class="tr-caption-container">...</table>
// with the two-line Ghost import format:
// // <filename>
// <caption>
func replaceBloggerTablesWithFilenameAndCaption(in html: String) -> String {
    var out = html

    // Find each caption-table block
//    let tableRe = try! NSRegularExpression(
//        pattern: #"<table[^>]*class="tr-caption-container"[^>]*>[\s\S]*?</table>"#,
//        options: [.caseInsensitive]
//    )
	let tableRe = try! NSRegularExpression(
		pattern: #"<table\b[^>]*\bclass\s*=\s*\"tr-caption-container\"[^>]*>(?:(?!<table\b)[\s\S])*?</table>"#,
		options: [.caseInsensitive]
	)

    while true {
        guard let m = tableRe.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)) else { break }
        let r = Range(m.range, in: out)!
        let tableHTML = String(out[r])

        var filename: String?
        
        // Extract the first blogger image URL (from href or img src)
        if 
        	let urlRe = try? NSRegularExpression(pattern: #"https://blogger\.googleusercontent\.com/[^\s"']+"#),
			let um = urlRe.firstMatch(in: tableHTML, range: NSRange(tableHTML.startIndex..., in: tableHTML)),
			let ur = Range(um.range, in: tableHTML) 
		{
            let urlStr = String(tableHTML[ur])
            if let u = URL(string: urlStr) {
                filename = u.lastPathComponent
            } 
            else {
                filename = urlStr.split(separator: "/").last.map(String.init) ?? filename
            }
        }
        else if
			let urlRe = try? NSRegularExpression(pattern: #"http://curtisjones.us/[^\s"']+"#),
			let um = urlRe.firstMatch(in: tableHTML, range: NSRange(tableHTML.startIndex..., in: tableHTML)),
			let ur = Range(um.range, in: tableHTML) 
		{
            let urlStr = String(tableHTML[ur])
            if let u = URL(string: urlStr) {
                filename = u.absoluteString // u.lastPathComponent
            } 
            else {
                filename = urlStr.split(separator: "/").last.map(String.init) ?? filename
            }
		}
        else if
			let urlRe = try? NSRegularExpression(pattern: #"https://curtisjones.us/[^\s"']+"#),
			let um = urlRe.firstMatch(in: tableHTML, range: NSRange(tableHTML.startIndex..., in: tableHTML)),
			let ur = Range(um.range, in: tableHTML) 
		{
            let urlStr = String(tableHTML[ur])
            if let u = URL(string: urlStr) {
                filename = u.absoluteString // u.lastPathComponent
            } 
            else {
                filename = urlStr.split(separator: "/").last.map(String.init) ?? filename
            }
		}

		guard let filename = filename else {
			// Swift.print("********** Skipping this table because we could not parse a file name for: \(tableHTML)")
			out.replaceSubrange(r, with: "")
			continue
		}

		// Swift.print("Parsed file name = \(filename)")		
		
        // Extract caption HTML and turn into plain text
        var caption = ""
        if let capRe = try? NSRegularExpression(
            pattern: #"<td[^>]*class="tr-caption"[^>]*>([\s\S]*?)</td>"#,
            options: [.caseInsensitive]
        ),
        let cm = capRe.firstMatch(in: tableHTML, range: NSRange(tableHTML.startIndex..., in: tableHTML)),
        cm.numberOfRanges >= 2,
        let cr = Range(cm.range(at: 1), in: tableHTML) {
            let capHTML = String(tableHTML[cr])
            caption = htmlToPlaintext(capHTML)
        }

		let imgsrc: String
		
		if filename.hasPrefix("http") {
			imgsrc = filename
		}
		else {
			imgsrc = "__GHOST_URL__/content/images/2025/10/\(filename)"
		}
		
		let replacement = """
		<figure class="kg-card kg-image-card kg-card-hascaption">
			<img 
				src="\(imgsrc)" 
				class="kg-image" 
				alt="" 
				loading="lazy" 
				srcset="\(imgsrc)" 
				sizes="(min-width: 720px) 720px">
			<figcaption>
			<span style="white-space: pre-wrap;">\(caption)</span>
			</figcaption>
		</figure>
		"""
		
//      let replacement = "\n// \(filename)\n// \(caption)\n\n"
        out.replaceSubrange(r, with: replacement)
    }

    return out
}

// MARK: - Main

struct CLI {
    let inputPath: String
    let outputPath: String?

    static func parseArgs() throws -> CLI {
        var args = CommandLine.arguments.dropFirst()
        guard let input = args.first else { throw AppError.usage }
        args = args.dropFirst()

        var output: String? = nil
        while let a = args.first {
            if a == "-o" || a == "--output" {
                args = args.dropFirst()
                guard let p = args.first else { throw AppError.usage }
                output = p
                args = args.dropFirst()
            } else {
                throw AppError.usage
            }
        }
        return CLI(inputPath: input, outputPath: output)
    }
}

do {
    let cli = try CLI.parseArgs()
    let data = try readFile(path: cli.inputPath)

    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .useDefaultKeys

    let blog = try dec.decode(BloggerBlog.self, from: data)
    guard let entries = blog.feed.entry, !entries.isEmpty else { throw AppError.noEntries }

    let posts = entries.map(buildGhostPost)
    let out = GhostPosts(posts: posts)

    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let outData = try enc.encode(out)

    if let outPath = cli.outputPath {
        try writeFile(path: outPath, data: outData)
    } else {
        if let s = String(data: outData, encoding: .utf8) {
            FileHandle.standardOutput.write(s.data(using: .utf8)!)
        } else {
            FileHandle.standardOutput.write(outData)
        }
    }
} catch let e as AppError {
    fputs("Error: \(e.description)\n", stderr)
    exit(1)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
