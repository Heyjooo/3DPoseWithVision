import Foundation
import PhotosUI
import CoreTransferable
import UIKit
import Vision

// MARK: - 선택된 이미지의 상태를 관리하며, 선택된 이미지의 원본 파일 URL을 가져오는 기능을 제공하는 클래스
class HumanBodyPoseImageModel: NSObject, ObservableObject {

    enum ImageState { // 이미지 현재 상태
        case noneselected // 선택된 이미지 X
        case loading(Progress) // 이미지 로드 중
        case success(UIImage) // 이미지 성공적으로 로드
        case failure(Error) // 이미지 로드 실패
    }

    enum TransferError: Error {
        case importFailed // 이미지 가져오기 실패 오류
    }

    struct HumanBodyPoseImage: Transferable { // Transferable 프로토콜을 채택하여 이미지 데이터를 가져옴
        let image: UIImage

        static var transferRepresentation: some TransferRepresentation { // 데이터 가져오는 방법 정의
            DataRepresentation(importedContentType: .image) { data in
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                return HumanBodyPoseImage(image: uiImage)
            }
        }
    }

    var selectedAsset: PHAsset? = nil // 선택된 PHAsset 저장하는 변수
    @Published private(set) var imageState: ImageState = .noneselected // 현재 이미지 상태를 나타내는 @Published 속성
    var imageSelection: PHPickerResult? = nil { // 선택된 이미지 저장하는 변수, 설정될 때마다 이미지 로드
        didSet {
            if let imageSelection = imageSelection {
                let progress = loadTransferable(from: imageSelection)
                imageState = .loading(progress)
            } else {
                imageState = .noneselected
            }
        }
    }

    @Published var fileURL: URL? = nil // 선택된 이미지 파일의 URL을 저장하는 @Published 속성

    func loadOriginalFileURL(asset: PHAsset) { // PHAsset에서 원본 파일 URL을 로드하는 메서드
        self.getAssetFileURL(asset: asset) { url in
            guard let originalFileURL = url else {
                return
            }
            self.fileURL = originalFileURL
        }
    }

    // Determine the original file URL.
    private func getAssetFileURL(asset: PHAsset, completionHandler: @escaping (URL?) -> Void) { // 원본 파일 URL을 가져오는 메서드
        let option = PHContentEditingInputRequestOptions() // PHContentEditingInputRequestOptions를 사용하여 요청, 완료 핸들러를 사용하여 URL을 반환
        asset.requestContentEditingInput(with: option) { contentEditingInput, _ in
            completionHandler(contentEditingInput?.fullSizeImageURL)
        }
    }

    private func loadAssetFromID(identifier: String?) -> PHAsset? { // 로컬 식별자를 사용하여 PHAsset을 가져오는 메서드
        if let identifier {
            let result = PHAsset.fetchAssets( // PHAsset.fetchAssets를 사용하여 식별자로 자산을 가져옴
                withLocalIdentifiers: [identifier],
                options: nil
            )
            if let asset = result.firstObject {
                return asset
            }
        } else {
            print("No identifier on item.")
        }
        return nil
    }

    private func loadTransferable(from imageSelection: PHPickerResult) -> Progress { // 이미지 선택에서 Transferable을 로드하는 메서드
        return imageSelection.itemProvider.loadTransferable(type: HumanBodyPoseImage.self) { (result: Result<HumanBodyPoseImage, Error>) in
            // itemProvider.loadTransferable을 사용하여 데이터를 로드하고 결과를 처리
            DispatchQueue.main.async {
                switch result {
                case .success(let humanBodyImage): // 성공 시 이미지 상태를 업데이트하고 PHAsset을 로드
                    self.imageState = .success(humanBodyImage.image)
                    self.selectedAsset = self.loadAssetFromID(identifier: imageSelection.assetIdentifier)
                    if let asset = self.selectedAsset {
                        self.loadOriginalFileURL(asset: asset)
                    } else {
                        print("Asset not found.")
                    }
                case .failure(let error): // 실패 시 오류 상태로 imageState 업데이트
                    self.imageState = .failure(error)
                }
            }
        }
    }
}
