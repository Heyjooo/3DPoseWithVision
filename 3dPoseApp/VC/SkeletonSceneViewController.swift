//
//  SkeletonSceneViewController.swift
//  3dPoseApp
//
//  Created by 변희주 on 6/5/24.
//

import UIKit
import SceneKit
import Vision

// MARK: - 3D 인체 자세를 시각화
class SkeletonSceneViewController: UIViewController {
    private var sceneView: SCNView! // 3D 장면을 표시하는 SceneKit 뷰
    var viewModel: HumanBodyPose3DDetector! // 3D 인체 자세 감지를 관리하는 모델
    private var showCamera = false // 현재 카메라 노드를 표시할지 여부를 나타내는 플래그
    private let button = UIButton(type: .system) // 관점을 전환하는 버튼

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .white

        // 컴포넌트 설정
        setupSceneView()
        setupButton()
        
        // viewModel 사용하여 3D 인체 감지 요청 실행하고 완료되면 updateScene 호출하여 장면 업데이트
        Task {
            await viewModel.runHumanBodyPose3DRequestOnImage()
            self.updateScene()
        }
    }

    private func setupSceneView() {
        sceneView = SCNView(frame: self.view.bounds)
        sceneView.autoenablesDefaultLighting = true // 기본 조명을 활성화
        sceneView.allowsCameraControl = true // 사용자가 카메라를 조작할 수 있도록 함
        self.view.addSubview(sceneView)
    }

    private func setupButton() {
        button.setTitle("Switch Perspective", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -70),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @objc private func buttonTapped() {
        showCamera.toggle()
        updateScene()
    }

    // 새로운 SceneKit 장면을 생성하고, 3D 인체 스켈레톤을 렌더링
    private func updateScene() {
        let scene = SCNScene()
        let renderer = HumanBodySkeletonRenderer()

        // humanObservation 사용하여 3D 인체 자세 감지
        guard let observation = viewModel.humanObservation else {
            sceneView.scene = scene
            return
        }

        var imageNode = SCNNode()
        
        // 이미지 노드 생성
        if let fileURL = viewModel.fileURL {
            imageNode = renderer.createInputImage2DNode(url: fileURL, observation: observation)
            scene.rootNode.addChildNode(imageNode)
        }

        let nodeDict = renderer.createSkeletonNodes(observation: observation)
        let imagePlaneScale = renderer.relate3DSkeletonProportionToImagePlane(observation: observation) // 스켈레톤 노드 생성
        renderer.imageNodeSize.width *= CGFloat(imagePlaneScale)
        renderer.imageNodeSize.height *= CGFloat(imagePlaneScale)

        let planeGeometry = SCNPlane(width: renderer.imageNodeSize.width, height: renderer.imageNodeSize.height)
        if let inputImage = imageNode.geometry?.firstMaterial?.diffuse.contents {
            planeGeometry.firstMaterial?.diffuse.contents = inputImage
            planeGeometry.firstMaterial?.isDoubleSided = true
        }
        imageNode.geometry = planeGeometry

        let point = renderer.computeOffsetOfRoot(observation: observation)
        imageNode.simdPosition = simd_float3(x: imageNode.simdPosition.x - Float(point.x),
                                             y: imageNode.simdPosition.y - Float(point.y),
                                             z: imageNode.simdPosition.z)

        if showCamera {
            // 카메라 노드 추가
            scene.rootNode.addChildNode(renderer.createCameraNode(observation: observation))
        } else {
            //피라미드 노드 추가
            scene.rootNode.addChildNode(renderer.createCameraPyramidNode(observation: observation))
        }

        let bodyAnchorNode = SCNNode()
        bodyAnchorNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(bodyAnchorNode)
        for jointName in nodeDict.keys {
            if let jointNode = nodeDict[jointName] {
                bodyAnchorNode.addChildNode(jointNode)
            }
        }

        if let topHead = nodeDict[.topHead], let centerHeadNode = nodeDict[.centerHead], let centerShoulderNode = nodeDict[.centerShoulder] {
            let headHight = CGFloat(topHead.position.y - centerShoulderNode.position.y)
            centerHeadNode.geometry = SCNBox(width: 0.2,
                                             height: headHight,
                                             length: 0.2,
                                             chamferRadius: 0.4)
            centerHeadNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGray
            topHead.isHidden = true
        }

        let jointOrderArray: [VNHumanBodyPose3DObservation.JointName] = [.leftWrist, .leftElbow, .leftShoulder,
                                                                         .rightWrist, .rightElbow, .rightShoulder,
                                                                         .centerShoulder, .spine, .rightAnkle,
                                                                         .rightKnee, .rightHip, .leftAnkle, .leftKnee, .leftHip]
        for jointName in jointOrderArray {
            connectNodeToParent(joint: jointName,
                                observation: observation,
                                nodeJointDict: nodeDict,
                                viewModel)
        }

        sceneView.scene = scene
    }

    // 각 관절을 부모 관절에 연결하는 메서드
    private func connectNodeToParent(joint: VNHumanBodyPose3DObservation.JointName,
                                     observation: VNHumanBodyPose3DObservation,
                                     nodeJointDict: [VNHumanBodyPose3DObservation.JointName: SCNNode],
                                     _ viewModel: HumanBodyPose3DDetector) {
        
        // 부모 관절이 존재하면 updateLineNode 메서드를 호출하여 연결선을 업데이트
        if let parentJointName = observation.parentJointName(joint), let node = nodeJointDict[joint] {
            guard let parentNode = nodeJointDict[parentJointName] else {
                return
            }
            updateLineNode(node: node,
                           joint: joint,
                           fromPoint: node.simdPosition,
                           toPoint: parentNode.simdPosition,
                           detector: viewModel)
        }
    }

    // 두 관절 사이의 연결선을 업데이트하는 메서드
    private func updateLineNode(node: SCNNode,
                                joint: VNHumanBodyPose3DObservation.JointName,
                                fromPoint: simd_float3,
                                toPoint: simd_float3,
                                originalCubeWidth: Float = 0.05,
                                detector: HumanBodyPose3DDetector) {
        // 연결선의 길이를 계산하고, 이를 기반으로 SCNBox 기하를 생성
        let length = max(simd_length(toPoint - fromPoint), 1E-5)
        let boxGeometry = SCNBox(width: CGFloat(originalCubeWidth),
                                 height: CGFloat(length),
                                 length: CGFloat(originalCubeWidth),
                                 chamferRadius: 0.05)
        node.geometry = boxGeometry
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGray
        
        // 연결선을 그리기 위해 노드의 위치와 각도를 설정
        node.simdPosition = (toPoint + fromPoint) / 2
        node.simdEulerAngles = detector.calculateLocalAngleToParent(joint: joint)
    }
}
