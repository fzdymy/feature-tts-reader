import Foundation
import CoreData
import os

final class PersistenceController: ObservableObject, @unchecked Sendable {
    static let shared = PersistenceController()

    private let log = OSLog(subsystem: "com.featurettsreader", category: "Persistence")
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = PersistenceController.makeModel()
        container = NSPersistentContainer(name: "FeatureTTSReader", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                os_log(.error, log: self.log, "无法载入 Core Data 存储: %{public}@", error.localizedDescription)
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let bookEntity = NSEntityDescription()
        bookEntity.name = "CDBook"
        bookEntity.managedObjectClassName = "NSManagedObject"
        bookEntity.properties = [
            attribute(name: "id", type: .stringAttributeType, isOptional: false),
            attribute(name: "title", type: .stringAttributeType, isOptional: false),
            attribute(name: "text", type: .stringAttributeType, isOptional: false),
            attribute(name: "importedAt", type: .dateAttributeType, isOptional: false)
        ]

        let bookmarkEntity = NSEntityDescription()
        bookmarkEntity.name = "CDBookmark"
        bookmarkEntity.managedObjectClassName = "NSManagedObject"
        bookmarkEntity.properties = [
            attribute(name: "id", type: .stringAttributeType, isOptional: false),
            attribute(name: "chapterID", type: .stringAttributeType, isOptional: false),
            attribute(name: "chapterTitle", type: .stringAttributeType, isOptional: false),
            attribute(name: "percent", type: .doubleAttributeType, isOptional: false),
            attribute(name: "note", type: .stringAttributeType, isOptional: true),
            attribute(name: "createdAt", type: .dateAttributeType, isOptional: false)
        ]

        let progressEntity = NSEntityDescription()
        progressEntity.name = "CDChapterProgress"
        progressEntity.managedObjectClassName = "NSManagedObject"
        progressEntity.properties = [
            attribute(name: "id", type: .stringAttributeType, isOptional: false),
            attribute(name: "bookID", type: .stringAttributeType, isOptional: true),
            attribute(name: "chapterID", type: .stringAttributeType, isOptional: false),
            attribute(name: "percent", type: .doubleAttributeType, isOptional: false)
        ]

        let lastReadEntity = NSEntityDescription()
        lastReadEntity.name = "CDLastReadChapter"
        lastReadEntity.managedObjectClassName = "NSManagedObject"
        lastReadEntity.properties = [
            attribute(name: "bookID", type: .stringAttributeType, isOptional: false),
            attribute(name: "chapterIndex", type: .integer16AttributeType, isOptional: false)
        ]

        model.entities = [bookEntity, bookmarkEntity, progressEntity, lastReadEntity]
        return model
    }

    private static func attribute(name: String, type: NSAttributeType, isOptional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }

    private func saveContext() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            os_log(.error, log: log, "Core Data 保存失败：%{public}@", error.localizedDescription)
        }
    }

    func fetchBooks() -> [Book] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDBook")
        request.sortDescriptors = [NSSortDescriptor(key: "importedAt", ascending: false)]
        guard let results = try? container.viewContext.fetch(request) else { return [] }
        return results.compactMap { object in
            guard
                let idString = object.value(forKey: "id") as? String,
                let id = UUID(uuidString: idString),
                let title = object.value(forKey: "title") as? String,
                let importedAt = object.value(forKey: "importedAt") as? Date
            else {
                return nil
            }
            let text = object.value(forKey: "text") as? String ?? ""
            return Book(id: id, title: title, text: text, importedAt: importedAt)
        }
    }

    func saveBooks(_ books: [Book]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDBook")
        if let existing = try? context.fetch(request) {
            existing.forEach { context.delete($0) }
        }
        for book in books {
            guard let entity = container.managedObjectModel.entitiesByName["CDBook"] else { continue }
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(book.id.uuidString, forKey: "id")
            object.setValue(book.title, forKey: "title")
            object.setValue(book.text, forKey: "text")
            object.setValue(book.importedAt, forKey: "importedAt")
        }
        saveContext()
    }

    func fetchBookmarks() -> [BookBookmark] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDBookmark")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let results = try? container.viewContext.fetch(request) else { return [] }
        return results.compactMap { object in
            guard
                let idString = object.value(forKey: "id") as? String,
                let id = UUID(uuidString: idString),
                let chapterIDString = object.value(forKey: "chapterID") as? String,
                let chapterID = UUID(uuidString: chapterIDString),
                let chapterTitle = object.value(forKey: "chapterTitle") as? String,
                let percent = object.value(forKey: "percent") as? Double,
                let createdAt = object.value(forKey: "createdAt") as? Date
            else {
                return nil
            }
            let note = object.value(forKey: "note") as? String ?? ""
            return BookBookmark(id: id, chapterID: chapterID, chapterTitle: chapterTitle, percent: percent, note: note, createdAt: createdAt)
        }
    }

    func saveBookmarks(_ bookmarks: [BookBookmark]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDBookmark")
        if let existing = try? context.fetch(request) {
            existing.forEach { context.delete($0) }
        }
        for bookmark in bookmarks {
            guard let entity = container.managedObjectModel.entitiesByName["CDBookmark"] else { continue }
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(bookmark.id.uuidString, forKey: "id")
            object.setValue(bookmark.chapterID.uuidString, forKey: "chapterID")
            object.setValue(bookmark.chapterTitle, forKey: "chapterTitle")
            object.setValue(bookmark.percent, forKey: "percent")
            object.setValue(bookmark.note, forKey: "note")
            object.setValue(bookmark.createdAt, forKey: "createdAt")
        }
        saveContext()
    }

    func fetchChapterProgress() -> [UUID: Double] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDChapterProgress")
        guard let results = try? container.viewContext.fetch(request) else { return [:] }
        var map: [UUID: Double] = [:]
        for object in results {
            if
                let chapterIDString = object.value(forKey: "chapterID") as? String,
                let chapterID = UUID(uuidString: chapterIDString),
                let percent = object.value(forKey: "percent") as? Double
            {
                map[chapterID] = percent
            }
        }
        return map
    }

    func saveChapterProgressMap(_ progress: [UUID: Double]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDChapterProgress")
        if let existing = try? context.fetch(request) {
            existing.forEach { context.delete($0) }
        }
        for (chapterID, percent) in progress {
            guard let entity = container.managedObjectModel.entitiesByName["CDChapterProgress"] else { continue }
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(chapterID.uuidString, forKey: "id")
            object.setValue(chapterID.uuidString, forKey: "chapterID")
            object.setValue(percent, forKey: "percent")
        }
        saveContext()
    }

    func fetchLastReadChapterIndexByBook() -> [UUID: Int] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDLastReadChapter")
        guard let results = try? container.viewContext.fetch(request) else { return [:] }
        var map: [UUID: Int] = [:]
        for object in results {
            if
                let bookIDString = object.value(forKey: "bookID") as? String,
                let bookID = UUID(uuidString: bookIDString),
                let chapterIndex = object.value(forKey: "chapterIndex") as? Int16
            {
                map[bookID] = Int(chapterIndex)
            }
        }
        return map
    }

    func saveLastReadChapterIndexMap(_ lastRead: [UUID: Int]) {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDLastReadChapter")
        if let existing = try? context.fetch(request) {
            existing.forEach { context.delete($0) }
        }
        for (bookID, chapterIndex) in lastRead {
            guard let entity = container.managedObjectModel.entitiesByName["CDLastReadChapter"] else { continue }
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(bookID.uuidString, forKey: "bookID")
            object.setValue(Int16(chapterIndex), forKey: "chapterIndex")
        }
        saveContext()
    }

    func clearLibrary() {
        let context = container.viewContext
        ["CDBook", "CDBookmark", "CDChapterProgress", "CDLastReadChapter"].forEach { entityName in
            let fetch = NSFetchRequest<NSManagedObject>(entityName: entityName)
            if let existing = try? context.fetch(fetch) {
                existing.forEach { context.delete($0) }
            }
        }
        saveContext()
    }
}
