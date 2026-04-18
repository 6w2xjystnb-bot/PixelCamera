import Foundation
import AVFoundation

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    typealias CompletionHandler = (Result<AVCapturePhoto, Error>) -> Void
    
    private let completion: CompletionHandler
    private let burstCompletion: ((Result<[AVCapturePhoto], Error>) -> Void)?
    private var photos: [AVCapturePhoto] = []
    private let expectedCount: Int
    
    init(expectedCount: Int = 1, completion: @escaping CompletionHandler, burstCompletion: ((Result<[AVCapturePhoto], Error>) -> Void)? = nil) {
        self.expectedCount = expectedCount
        self.completion = completion
        self.burstCompletion = burstCompletion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }
        
        if expectedCount > 1 {
            photos.append(photo)
            if photos.count >= expectedCount {
                burstCompletion?(.success(photos))
            }
        } else {
            completion(.success(photo))
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            if expectedCount == 1 {
                completion(.failure(error))
            } else {
                burstCompletion?(.failure(error))
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {}
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {}
}

final class DepthPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    typealias CompletionHandler = (Result<(photo: AVCapturePhoto, depthData: AVDepthData?), Error>) -> Void
    
    private let completion: CompletionHandler
    
    init(completion: @escaping CompletionHandler) {
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }
        
        let depthData = photo.depthData
        completion(.success((photo, depthData)))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            completion(.failure(error))
        }
    }
}
