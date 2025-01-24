import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, UIGestureRecognizerDelegate {

    @IBOutlet weak var arscnView: ARSCNView!
    
    private var mostRecentAnchor: ARAnchor? // Store the most recent plane anchor
    private var binturongCount = 0
    private let maxBinturongs = 10
    
    // Track whichever node is currently selected for gestures
    private var selectedNode: SCNNode?
    // Track the initial touch points to distinguish between one-finger and two-finger gestures if needed
    private var trackedFingerCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        arscnView.automaticallyUpdatesLighting = true
        arscnView.autoenablesDefaultLighting = true
        arscnView.scene = SCNScene()
        arscnView.delegate = self
        
        // Set up gesture recognizers for tapping, panning (move), and rotating
        setupGestures()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arscnView.session.run(config)
        arscnView.debugOptions = [.showFeaturePoints] // For debugging
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arscnView.session.pause()
    }
    
    // MARK: - Spawn Binturong
    @IBAction func SpawnCreatureBtn(sender: UIButton) {
        if binturongCount >= maxBinturongs {
            print("Maximum binturongs reached!")
            return
        }

        guard let anchor = mostRecentAnchor else {
            print("No plane detected yet. Cannot spawn binturong.")
            return
        }
        placeModel(on: anchor)
        binturongCount += 1
    }
    
    private func placeModel(on anchor: ARAnchor) {
        guard let binturongScene = SCNScene(named: "scene.scnassets/binturong.scn") else {
            print("Failed to load binturong.scn")
            return
        }
        
        let binturongNode = binturongScene.rootNode.clone()
        binturongNode.simdTransform = anchor.transform
        // Raise it slightly above the plane
        binturongNode.position.y += 0.05
        
        // Add node to the scene
        arscnView.scene.rootNode.addChildNode(binturongNode)
        
        // Select the newly spawned node for manipulating via gestures
        selectedNode = binturongNode
    }
    
    // MARK: - Gesture Setup
    private func setupGestures() {
        // One-finger tap to select / place the node
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arscnView.addGestureRecognizer(tapGesture)
        
        // Pan gesture (use either one or two fingers) to move the selected node
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        arscnView.addGestureRecognizer(panGesture)
        
        // Two-finger rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        arscnView.addGestureRecognizer(rotationGesture)
    }
    
    // MARK: - Tap Gesture
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let touchLocation = gesture.location(in: arscnView)
        
        // SceneKit hitTest for nodes
        let hitTestResults = arscnView.hitTest(touchLocation, options: nil)
        
        if let hit = hitTestResults.first {
            // If a node is tapped, select it
            selectedNode = hit.node
            print("Selected existing binturong node for gestures.")
        } else if let node = selectedNode {
            // Move the selected node to the plane location if tapped on empty space
            moveNodeToTapLocation(node, at: touchLocation)
        }
    }
    
    private func moveNodeToTapLocation(_ node: SCNNode, at screenPos: CGPoint) {
        // Instead of using hitTest(_:types:), we switch to ARView’s raycast-based approach
        guard let raycastQuery = arscnView.raycastQuery(from: screenPos,
                                                        allowing: .existingPlaneGeometry,
                                                        alignment: .horizontal) else {
            return
        }
        
        let raycastResults = arscnView.session.raycast(raycastQuery)
        if let firstResult = raycastResults.first {
            // Retrieve and apply the new transform from the raycast
            var newTransform = node.simdTransform
            newTransform.columns.3 = firstResult.worldTransform.columns.3
            
            // Slightly raise above plane
            newTransform.columns.3.y += 0.05
            node.simdTransform = newTransform
        }
    }
    
    // MARK: - Pan Gesture
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let node = selectedNode else { return }
        
        // Track how many fingers are used to pan
        trackedFingerCount = gesture.numberOfTouches
        
        switch gesture.state {
        case .changed:
            // For planar movement: adjust node's position in x/z based on pan translation
            let translation = gesture.translation(in: arscnView)
            let deltaX = Float(translation.x) * 0.0005
            let deltaZ = Float(translation.y) * 0.0005
            
            node.position.x += deltaX
            node.position.z += deltaZ
            
            // Reset translation so changes are incremental
            gesture.setTranslation(.zero, in: arscnView)
        default:
            break
        }
    }
    
    // MARK: - Rotation Gesture
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .changed, let node = selectedNode, trackedFingerCount >= 2 else { return }
        
        // Rotate around the node’s y-axis
        node.eulerAngles.y -= Float(gesture.rotation)
        
        // Reset rotation so subsequent changes are incremental
        gesture.rotation = 0
    }
    
    // MARK: - UIGestureRecognizerDelegate
    // Note: Do not mark this method as "override" because it is from a protocol, not a superclass
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        mostRecentAnchor = planeAnchor
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        if let currentAnchor = mostRecentAnchor as? ARPlaneAnchor,
           currentAnchor.identifier == planeAnchor.identifier {
            mostRecentAnchor = planeAnchor
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        arscnView.scene.rootNode.childNodes.forEach { childNode in
            if childNode.simdTransform == anchor.transform {
                childNode.removeFromParentNode()
                binturongCount -= 1
            }
        }
    }
}
