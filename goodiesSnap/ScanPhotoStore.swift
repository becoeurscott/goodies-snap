import UIKit

/// Keeps the frames people snap, so a recipe written from a scan can carry the photo of the
/// actual plate instead of a stock shot.
///
/// Files live in Application Support (not Documents — these are app data, not user documents,
/// and Documents is visible in Files when file sharing is on) and are excluded from backup:
/// they are re-creatable, and a library of full-size JPEGs has no business in iCloud.
enum ScanPhotoStore {
    private static let folderName = "ScanPhotos"

    private static var folder: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Writes `image` as a JPEG and returns its file URL string, or nil if there's nothing to
    /// save. Downscaled first: a recipe thumbnail never needs a 12-megapixel original.
    static func save(_ image: UIImage?) -> String? {
        guard let image, let folder else { return nil }
        guard let data = downscaled(image, maxEdge: 1200).jpegData(compressionQuality: 0.82) else { return nil }
        let url = folder.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            var mutable = url
            try? mutable.setResourceValues(resource)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    /// Deletes a stored scan photo. Called when the recipe that owned it goes away.
    static func remove(_ urlString: String) {
        guard let url = URL(string: urlString), url.isFileURL,
              url.path.contains(folderName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
