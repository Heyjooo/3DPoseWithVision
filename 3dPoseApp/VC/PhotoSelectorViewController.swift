//
//  PhotoSelectorViewController.swift
//  3dPoseApp
//
//  Created by 변희주 on 6/5/24.
//

import UIKit
import Combine
import PhotosUI

// MARK: - 사진을 선택하고 선택한 사진에서 3D 인체 자세를 감지
class PhotoSelectorViewController: UIViewController {
    private let poseViewModel = HumanBodyPoseImageModel() // 이미지를 처리하고 3D 인체 자세 감지 결과를 관리하는 모델
    private let skeletonModel = HumanBodyPose3DDetector() // 3D 스켈레톤을 감지하고 관리하는 모델
    
    private let imageView = UIImageView()
    private let selectPhotoButton = UIButton(type: .system)
    private let showSkeletonButton = UIButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        // 컴포넌트 설정
        setupImageView()
        setupSelectPhotoButton()
        setupShowSkeletonButton()
        
        // 사진 라이브러리 접근 권한 요청
        requestAuthorization()
    }

    private func setupImageView() {
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.systemGray

        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            imageView.widthAnchor.constraint(equalToConstant: 300),
            imageView.heightAnchor.constraint(equalToConstant: 500)
        ])
    }

    private func setupSelectPhotoButton() {
        selectPhotoButton.setTitle("Select Photo", for: .normal)
        selectPhotoButton.addTarget(self, action: #selector(selectPhoto), for: .touchUpInside)

        selectPhotoButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectPhotoButton)
        NSLayoutConstraint.activate([
            selectPhotoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectPhotoButton.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20)
        ])
    }

    private func setupShowSkeletonButton() {
        showSkeletonButton.setTitle("Show 3D Skeleton", for: .normal)
        showSkeletonButton.addTarget(self, action: #selector(showSkeleton), for: .touchUpInside)
        showSkeletonButton.setTitleColor(.white, for: .normal)
        showSkeletonButton.backgroundColor = .systemBlue
        showSkeletonButton.layer.cornerRadius = 8
        showSkeletonButton.layer.masksToBounds = true

        showSkeletonButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(showSkeletonButton)
        NSLayoutConstraint.activate([
            showSkeletonButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            showSkeletonButton.topAnchor.constraint(equalTo: selectPhotoButton.bottomAnchor, constant: 20),
            showSkeletonButton.widthAnchor.constraint(equalToConstant: 180),
            showSkeletonButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func selectPhoto() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }

    private func requestAuthorization() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { code in
                if code == .authorized {
                    print("Photos Permissions granted.")
                }
            }
        case .restricted, .denied:
            print("Please allow access to Photos to use the app.")
        case .authorized:
            print("Authorized for Photos access.")
        case .limited:
            print("Limited Photos access.")
        @unknown default:
            print("Unable to access Photos.")
        }
    }

    @objc private func showSkeleton() {
        let skeletonSceneVC = SkeletonSceneViewController()
        skeletonSceneVC.viewModel = skeletonModel
        skeletonSceneVC.viewModel.fileURL = poseViewModel.fileURL
        navigationController?.pushViewController(skeletonSceneVC, animated: true)
    }

    private var cancellables = Set<AnyCancellable>()
}

extension PhotoSelectorViewController: PHPickerViewControllerDelegate {
    // 사용자가 사진을 선택했을 때 호출되는 델리게이트 메서드
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let result = results.first else {
            return
        }

        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
            if let image = image as? UIImage {
                DispatchQueue.main.async {
                    self?.imageView.image = image // 선택한 이미지를 imageView에 표시
                }

                // 임시 디렉토리에 저장한 후 poseViewModel의 fileURL을 업데이트
                if let data = image.jpegData(compressionQuality: 1.0) {
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let tempFileURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")

                    do {
                        try data.write(to: tempFileURL)
                        DispatchQueue.main.async {
                            self?.poseViewModel.fileURL = tempFileURL
                        }
                    } catch {
                        print("Error saving image to temporary directory: \(error)")
                    }
                }
                
            }
        }
    }
}
