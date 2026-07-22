import Foundation

enum NGAForumBrowseTarget: Equatable {
    case fid(Int)
    case stid(Int)

    var value: Int {
        switch self {
        case let .fid(value), let .stid(value): value
        }
    }

    var stableKey: String {
        switch self {
        case let .fid(value): "fid:\(value)"
        case let .stid(value): "stid:\(value)"
        }
    }

    func channel(title: String) -> ForumChannel {
        ForumChannel(id: value, title: title, nativeKey: stableKey)
    }
}

struct NGAAuthoritativeChildForum: Equatable {
    let target: NGAForumBrowseTarget
    let title: String
    let detail: String
    let filterID: Int
    let attributes: Int

    var stableKey: String { target.stableKey }
    var channel: ForumChannel { target.channel(title: title) }
}

struct NGAAuthoritativeChildForumDirectory: Equatable {
    let parentFID: Int
    let parentName: String
    let children: [NGAAuthoritativeChildForum]
}

enum NGAAuthoritativeChildForumParserError: Error, Equatable {
    case invalidXML
    case missingForumMetadata
    case missingParentIdentity
    case parentMismatch
    case missingChildForumContainer
    case invalidChildForumRecord
    case unknownChildForumNode(String)
    case duplicateStableKey(String)
}

struct NGAAuthoritativeChildForumParser {
    static func parse(
        data: Data,
        expectedParent: ForumChannel
    ) throws -> NGAAuthoritativeChildForumDirectory {
        let document = NGAMinimalXMLDocumentParser.parse(data: data)
        guard let root = document else {
            throw NGAAuthoritativeChildForumParserError.invalidXML
        }
        guard let forum = root.onlyChild(named: "__F") else {
            throw NGAAuthoritativeChildForumParserError.missingForumMetadata
        }
        guard let fidText = forum.onlyChild(named: "fid")?.leafText,
              let parentFID = Int(fidText),
              let parentName = forum.onlyChild(named: "name")?.leafText,
              !parentName.isEmpty
        else {
            throw NGAAuthoritativeChildForumParserError.missingParentIdentity
        }
        guard parentFID == expectedParent.id,
              parentName == expectedParent.title
        else {
            throw NGAAuthoritativeChildForumParserError.parentMismatch
        }
        guard let container = forum.onlyChild(named: "sub_forums") else {
            throw NGAAuthoritativeChildForumParserError.missingChildForumContainer
        }

        var children: [NGAAuthoritativeChildForum] = []
        var stableKeys = Set<String>()
        for node in container.children {
            let targetKind: (Int) -> NGAForumBrowseTarget
            let taggedID: Int?
            if node.name == "item" {
                targetKind = NGAForumBrowseTarget.fid
                taggedID = nil
            } else if node.name.first == "t",
                      let value = Int(node.name.dropFirst()) {
                targetKind = NGAForumBrowseTarget.stid
                taggedID = value
            } else {
                throw NGAAuthoritativeChildForumParserError.unknownChildForumNode(node.name)
            }

            guard node.hasOnlyWhitespaceText,
                  node.children.count == 5,
                  node.children.allSatisfy({ $0.name == "item" && $0.children.isEmpty }),
                  let browseText = node.children[0].leafText,
                  let browseID = Int(browseText),
                  taggedID == nil || taggedID == browseID,
                  let title = node.children[1].leafText,
                  !title.isEmpty,
                  let detail = node.children[2].leafText,
                  let filterText = node.children[3].leafText,
                  let filterID = Int(filterText),
                  let attributesText = node.children[4].leafText,
                  let attributes = Int(attributesText)
            else {
                throw NGAAuthoritativeChildForumParserError.invalidChildForumRecord
            }

            let child = NGAAuthoritativeChildForum(
                target: targetKind(browseID),
                title: title,
                detail: detail,
                filterID: filterID,
                attributes: attributes
            )
            guard stableKeys.insert(child.stableKey).inserted else {
                throw NGAAuthoritativeChildForumParserError.duplicateStableKey(child.stableKey)
            }
            children.append(child)
        }

        return NGAAuthoritativeChildForumDirectory(
            parentFID: parentFID,
            parentName: parentName,
            children: children
        )
    }
}

private final class NGAMinimalXMLNode {
    let name: String
    var text = ""
    var children: [NGAMinimalXMLNode] = []

    init(name: String) {
        self.name = name
    }

    var hasOnlyWhitespaceText: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var leafText: String? {
        guard children.isEmpty else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func onlyChild(named name: String) -> NGAMinimalXMLNode? {
        let matches = children.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }
}

private final class NGAMinimalXMLDocumentParser: NSObject, XMLParserDelegate {
    private var stack: [NGAMinimalXMLNode] = []
    private var root: NGAMinimalXMLNode?
    private var encounteredError = false

    static func parse(data: Data) -> NGAMinimalXMLNode? {
        let delegate = NGAMinimalXMLDocumentParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.encounteredError else { return nil }
        return delegate.root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard attributeDict.isEmpty else {
            encounteredError = true
            parser.abortParsing()
            return
        }
        let node = NGAMinimalXMLNode(name: elementName)
        if let parent = stack.last {
            parent.children.append(node)
        } else if root == nil {
            root = node
        } else {
            encounteredError = true
            parser.abortParsing()
            return
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard stack.last?.name == elementName else {
            encounteredError = true
            parser.abortParsing()
            return
        }
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        encounteredError = true
    }
}
