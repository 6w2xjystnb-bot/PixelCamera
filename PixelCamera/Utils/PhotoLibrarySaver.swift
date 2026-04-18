import Foundation
import Photos
import UIKit
import CoreImage
import CoreLocation

actor PhotoLibrarySaver {
    nonisolated(unsafe) static let shared = PhotoLibrarySaver()
    
    enum SaveError: Error {
        case creationFailed
        case saveFailed(Error)
        case invalidImage
        case noData
    }
    
    func save(image: UIImage, location: CLLocation? = nil) async throws {
        try await requestAddPermissionIfNeeded()
        
        return try await withCheckedThrowingContinuation { continuation in
            var creationRequest: PHAssetCreationRequest?
            PHPhotoLibrary.shared().performChanges({
                creationRequest = PHAssetCreationRequest.forAsset()
                if let location = location {
                    creationRequest?.location = location
                }
                if let jpegData = image.jpegData(compressionQuality: 0.95) {
                    creationRequest?.addResource(with: .photo, data: jpegData, options: nil)
                }
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: SaveError.saveFailed(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.creationFailed)
                }
            }
        }
    }
    
    func save(ciImage: CIImage, location: CLLocation? = nil) async throws {
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            throw SaveError.invalidImage
        }
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        try await save(image: uiImage, location: location)
    }
    
    func save(pixelBuffer: CVPixelBuffer, location: CLLocation? = nil) async throws {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        try await save(ciImage: ciImage, location: location)
    }
    
    func save(videoURL: URL, location: CLLocation? = nil) async throws {
        try await requestAddPermissionIfNeeded()
        
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                if let location = location {
                    request.location = location
                }
                request.addResource(with: .video, fileURL: videoURL, options: nil)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: SaveError.saveFailed(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.creationFailed)
                }
            }
        }
    }
    
    private func requestAddPermissionIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard result == .authorized || result == .limited else {
                throw SaveError.saveFailed(NSError(domain: "PhotoLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]))
            }
        }
    }
    
    func fetchLastThumbnail(targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = fetchResult.firstObject else { return nil }
        
        return await withCheckedContinuation { continuation in
            let imageManager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
