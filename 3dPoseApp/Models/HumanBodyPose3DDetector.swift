/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The detector serves as the view model for the scene and interfaces with the Vision framework to run the request and related  calculations.
*/

import Foundation
import Vision
import AVFoundation
import Photos
import simd
import UIKit


// MARK: - Vision 프레임워크를 사용하여 인체 자세를 감지하고, 그 결과를 저장하는 뷰 모델의 역할을 하는 클래스
class HumanBodyPose3DDetector: NSObject, ObservableObject {

    @Published var humanObservation: VNHumanBodyPose3DObservation? = nil // 3D 인체 자세 감지 결과를 저장하는 속성
    var fileURL: URL? = URL(string: "") // 이미지 파일의 URL을 저장하는 속성

    public func calculateLocalAngleToParent(joint: VNHumanBodyPose3DObservation.JointName) -> simd_float3 { // 지정된 관절에서 부모 관절까지의 로컬 각도를 계산하는 메서드
        var angleVector: simd_float3 = simd_float3()
        do {
            if let observation = self.humanObservation {
                let recognizedPoint = try observation.recognizedPoint(joint)
                let childPosition = recognizedPoint.localPosition
                let translationC = simd_float3(childPosition.columns.3.x, childPosition.columns.3.y, childPosition.columns.3.z)
                // The rotation for x, y, z.
                // Rotate 90 degrees from the default orientation of the node. Add yaw and pitch, and connect the child to the parent.
                let pitch = (Float.pi / 2)
                let yaw = acos(translationC.z / simd_length(translationC))
                let roll = atan2((translationC.y), (translationC.x))
                angleVector = simd_float3(pitch, yaw, roll)
            }
        } catch {
            print("Unable to return point: \(error).")
        }
        return angleVector
    }

    // MARK: - Create and run the request on the asset URL.
    public func runHumanBodyPose3DRequestOnImage() async { // 이미지 파일 URL에서 3D 인체 자세를 감지하는 메서드
        await Task(priority: .userInitiated) { // 비동기적으로 동작
            guard let assetURL = self.fileURL else { return }

            // Check if the file exists and is accessible
            if !FileManager.default.fileExists(atPath: assetURL.path) {
                print("File does not exist at path: \(assetURL.path)")
                return
            }

            // Load the image to check if it's valid
            guard let image = UIImage(contentsOfFile: assetURL.path), image.size.width > 0, image.size.height > 0 else {
                print("Invalid image or image has zero dimensions.")
                return
            }
            
            // asset URL에 대한 요청을 생성하고 실행
            let request = VNDetectHumanBodyPose3DRequest()
            let requestHandler = VNImageRequestHandler(url: assetURL)
            do {
                try requestHandler.perform([request])
                if let returnedObservation = request.results?.first {
                    Task { @MainActor in
                        self.humanObservation = returnedObservation
                    }
                }
            } catch {
                print("Unable to perform the request: \(error).")
            }
        }.value
    }
}
