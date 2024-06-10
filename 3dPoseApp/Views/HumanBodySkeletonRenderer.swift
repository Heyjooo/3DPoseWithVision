/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Provides methods to draw SceneKit nodes from VNHumanBodyPose3DObservation to use in the scene of SkeletonSceneView.
*/

import Foundation
import SceneKit
import Vision
import UIKit
import CoreGraphics

// MARK: - SceneKit을 사용하여 VNHumanBodyPose3DObservation에서 인식된 관절을 시각화하는 데 사용되는 메서드를 제공하는 클래스
class HumanBodySkeletonRenderer: NSObject {
    
    public var nodeJointDict: [VNHumanBodyPose3DObservation.JointName: SCNNode] = [:]
    public var imageNodeSize = CGSize(width: 1.8, height: 1.8)
    public var inputImageAlpa: CGFloat = 0.85
    public var cameraNodeAlpa: CGFloat = 0.6
    public var cameraPyramidGeometry = SCNPyramid(width: 0.25, height: 0.25, length: 0.25)

    // MARK: - The input image plane node.
    // Get the distance between two known joints in 3D, see what proportion of the 2D image they cover, and
    // increase the size of the plane as necessary. Then shift after this is done, and
    // ensure that the image node side is correct.
    
    // 관절 및 이미지 시각화에 필요한 여러 메서드를 제공
    
    func relate3DSkeletonProportionToImagePlane(observation: VNHumanBodyPose3DObservation) -> Float { // 관찰된 관절 간의 3D 거리를 기반으로 2D 이미지에서의 관절 위치를 계산하는 메서드

        var returnScale: Float = 1.0

        guard
            let centerShoulderNode = self.nodeJointDict[.centerShoulder],
            let spineNode = self.nodeJointDict[.spine]
        else {
            return returnScale
        }

        let distance3D = simd_distance(
            simd_float2(
                x: Float(centerShoulderNode.simdPosition.x) / Float(self.imageNodeSize.width),
                y: Float(centerShoulderNode.simdPosition.y) / Float(self.imageNodeSize.height)
            ),
            simd_float2(
                x: Float(spineNode.simdPosition.x) / Float(self.imageNodeSize.width),
                y: Float(spineNode.simdPosition.y) / Float(self.imageNodeSize.height)
            )
        )

        do {
            let pointCenterShoulder2D = try observation.pointInImage(.centerShoulder)
            let pointSpine2D = try observation.pointInImage(.spine)
            let distance = simd_distance(
                simd_float2(
                    x: Float(pointCenterShoulder2D.x),
                    y: Float(pointCenterShoulder2D.y)
                ),
                simd_float2(
                    x: Float(pointSpine2D.x),
                    y: Float(pointSpine2D.y)
                )
            )
            returnScale = Float(distance3D / distance)
        } catch {
            print("Unable to return point: \(error).")
        }
        return returnScale
    }

    // Use the pointInImage API to determine the translation of the root joint.
    func computeOffsetOfRoot(observation: VNHumanBodyPose3DObservation) -> CGPoint { // 관찰된 관절의 뿌리 관절(루트 관절)의 이미지에서의 위치를 계산하는 메서드
        var returnPoint = CGPoint(x: 0, y: 0)
        do {
            let point = try observation.pointInImage(.root)
            // Change to image scale.
            var xShift = Double(point.x * imageNodeSize.width)
            // Recenter origin - translation shift left.
            xShift -= imageNodeSize.width / 2
            // Change to image scale.
            var yShift = Double(point.y * imageNodeSize.height)
            // Recenter origin - translation shift down.
            yShift -= imageNodeSize.height / 2
            returnPoint = CGPoint(x: Double(xShift), y: Double(yShift))
        } catch {
            print("Unable to return point: \(error).")
        }
        return returnPoint
    }

    // Draw the 2D image plane into the scene.
    func createInputImage2DNode(image: UIImage?) -> SCNNode { // 이미지를 SceneKit 노드로 만드는 메서드, 이미지를 SCNPlane 지오메트리에 매핑하여 2D 이미지를 3D 공간에 투영
        // The SceneKit nodes.
        let imageProjectionNode = SCNNode(
            geometry: SCNPlane(
                width: imageNodeSize.width,
                height: imageNodeSize.height
            )
        )
        imageProjectionNode.position = SCNVector3(0, 0, 0)

        if let inputImage = image {
            let orientedImage = imageWithExifOrientationApplied(inputImage)
            imageProjectionNode.geometry?.firstMaterial?.diffuse.contents = orientedImage
        }
        imageProjectionNode.opacity = inputImageAlpa
        return imageProjectionNode
    }

    // Apply the exif orientation to the image before setting as the material's contents
    func imageWithExifOrientationApplied(_ image: UIImage) -> UIImage {
        UIGraphicsBeginImageContext(image.size)
        image.draw(at: .zero)
        let orientedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return orientedImage ?? image
    }
    
    // Create the 2D image plane at an appropriate size in meters for the scene.
    func createInputImage2DNode(url: URL, observation: VNHumanBodyPose3DObservation) -> SCNNode {
        if let image = UIImage(contentsOfFile: url.path()) {
            // Adjust the size of the plane based on the aspect ratio from the default height.
            let aspectRatioW = image.size.width / image.size.height
            self.imageNodeSize.height = self.imageNodeSize.height
            self.imageNodeSize.width = self.imageNodeSize.height * aspectRatioW

            // Create the image node at (0 0 0).
            let imageNode = createInputImage2DNode(image: image)

            // The rotation needs to match the camera rotation.
            var corrected = observation.cameraOriginMatrix
            corrected.columns.3 = simd_float4(0, 0, 0, 1)
            imageNode.simdTransform = corrected.inverse
            return imageNode
        }
        return createInputImage2DNode(image: nil)
    }

    // MARK: - Camera nodes
    //  The location and rotation of the camera.
    // 카메라를 나타내는 SceneKit 노드를 생성하는 메서드, 이 노드들은 관찰된 관절의 카메라 원점 위치와 방향을 시각화
    func createCameraPyramidNode(observation: VNHumanBodyPose3DObservation) -> SCNNode {
        var originCameraNode = SCNNode()
        originCameraNode = createNodeForRecognizedPoint(
            point3D: simd_float3(x: 0, y: 0, z: 0),
            jointGeometry: cameraPyramidGeometry
        )
        originCameraNode.opacity = cameraNodeAlpa
        originCameraNode.geometry?.firstMaterial?.diffuse.contents = UIColor(.black)
        originCameraNode.simdPivot = cameraRepresentationPivotTransform(observation: observation)
        return originCameraNode
    }

    func cameraRepresentationPivotTransform(observation: VNHumanBodyPose3DObservation) -> simd_float4x4 {
        // Rotate back 90 degrees because the default position of the pyramid is facing down.
        let rotX90: simd_float4x4 = simd_float4x4(rotationX: -Float.pi / 2)
        return simd_mul(rotX90, observation.cameraOriginMatrix)
    }

    func createCameraNode(observation: VNHumanBodyPose3DObservation) -> SCNNode {
        // Set the default camera to this view.
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPivot = observation.cameraOriginMatrix
        return cameraNode
    }

    // MARK: - Skeleton nodes
    // Creates SceneKit nodes from the points in the observation.
    // VNHumanBodyPose3DObservation에서 관찰된 관절들을 SceneKit 노드로 만드는 메서드, 각 관절은 SCNBox와 같은 기하 모양으로 표현됨
    func createSkeletonNodes(
        observation: VNHumanBodyPose3DObservation
    ) -> [VNHumanBodyPose3DObservation.JointName: SCNNode] {

        var nodeJointDict = [VNHumanBodyPose3DObservation.JointName: SCNNode]()
        let skeletonJoints = observation.availableJointNames
        for jointName in skeletonJoints {
            do {
                let recognizedPoint = try observation.recognizedPoint(jointName)
                let pointFloat3 = recognizedPoint.position.translationVector
                
                let node = createNodeForRecognizedPoint(
                    point3D: pointFloat3,
                    jointGeometry: defaultNodeGeometry()
                )
                nodeJointDict.updateValue(node, forKey: jointName)
            } catch {
                print("Unable to return point: \(error).")
            }
        }
        self.nodeJointDict = nodeJointDict
        return nodeJointDict
    }

    // Create SceneKit nodes for the recognized points.
    private func createNodeForRecognizedPoint(
        point3D: simd_float3,
        jointGeometry: SCNGeometry
    ) -> SCNNode {
        // The joint node.
        let jointNode = SCNNode(geometry: jointGeometry)
        jointNode.simdPosition = simd_float3(
            x: point3D.x,
            y: point3D.y,
            z: point3D.z
        )
        return jointNode
    }

    // The default keypoint geometry.
    private func defaultNodeGeometry() -> SCNGeometry {
        return SCNBox(
            width: 0.05,
            height: 0.05,
            length: 0.05,
            chamferRadius: 0.05
        )
    }
}

// MARK: - Utilities for the rotation of simd_float4x4.
extension simd_float4x4 { // 4x4 행렬의 회전 및 변환에 대한 유틸리티 함수를 제공, 이 함수들은 X, Y, Z 축 주위의 회전 및 변환을 계산

    public init(rotationX angle: Float) {
        let matrix = float4x4(
            [1, 0, 0, 0],
            [0, cos(angle), sin(angle), 0],
            [0, -sin(angle), cos(angle), 0],
            [0, 0, 0, 1]
        )
        self = matrix
    }

    public init(rotationY angle: Float) {
        let matrix = float4x4(
            [cos(angle), 0, -sin(angle), 0],
            [0, 1, 0, 0],
            [sin(angle), 0, cos(angle), 0],
            [0, 0, 0, 1]
        )
        self = matrix
    }

    public init(rotationZ angle: Float) {
        let matrix = float4x4(
            [ cos(angle), sin(angle), 0, 0],
            [-sin(angle), cos(angle), 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        )
        self = matrix
    }
    
    var translationVector: simd_float3 {
        simd_make_float3(
            columns.3[0],
            columns.3[1],
            columns.3[2])
    }
}
