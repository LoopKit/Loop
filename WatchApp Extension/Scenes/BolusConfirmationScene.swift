

import SpriteKit


class BolusConfirmationScene: SKScene {

    struct Configuration {
        var arrow = BolusArrow.Configuration()
        var backgroundColor: UIColor = .black
        var checkmarkRect = CGRect(origin: .zero, size: CGSize(width: 22.5, height: 21.5))
        var checkmarkLineWidth: CGFloat = 5
        var checkmarkTint: UIColor = .white
    }

    enum State {
        case initialized
        case loaded
        case finished
    }

    let configuration: Configuration

    private(set) var arrow: BolusArrow!
    private(set) var circle: SKShapeNode!
    private(set) var checkmark: SKShapeNode!

    init(configuration: Configuration) {
        self.configuration = configuration

        super.init(size: .zero)

        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)

        guard case .loaded = state else {
            return
        }

        circle.position = CGPoint(x: 0, y: (size.height - circle.calculateAccumulatedFrame().size.height) / 2)
        arrow.position = circle.position
        checkmark.position = circle.position
    }

    override func sceneDidLoad() {
        arrow = BolusArrow(configuration: configuration.arrow)

        let arrowHeight = arrow.calculateAccumulatedFrame().size.height
        let circleHeight = arrowHeight + 20

        circle = SKShapeNode(circleOfRadius: circleHeight / 2)
        circle.fillColor = configuration.backgroundColor
        circle.lineWidth = 0

        checkmark = .checkmark(of: .checkmark(in: configuration.checkmarkRect), lineWidth: configuration.checkmarkLineWidth, strokeColor: configuration.checkmarkTint)
        checkmark.alpha = 0

        addChild(circle)
        addChild(checkmark)
        addChild(arrow)

        let arrowBody = SKPhysicsBody(rectangleOf: CGSize(width: 1, height: 1))
        arrowBody.affectedByGravity = false
        arrow.physicsBody = arrowBody

        // Slow down the force animation
        scene?.physicsWorld.gravity.dy = -5.0

        state = .loaded
    }

    private(set) var state: State = .initialized

    var progress: CGFloat {
        return arrow.progress
    }

    func setProgress(_ progress: CGFloat, animationDuration: TimeInterval = 0) {
        precondition(state != .initialized)

        arrow.setProgress(progress, animationDuration: animationDuration)
    }

    func setFinished(animationDuration: TimeInterval = 0.40) {
        precondition(state != .finished)
        state = .finished

        arrow.isFinished = true
        checkmark.run(.fadeIn(withDuration: animationDuration / 2))
        circle.run(.fadeOut(withDuration: animationDuration))
    }
}

// MARK: - Nodes

// Triangle node with separate stroke & fill children
class Arrow: SKNode {
    let fill: SKShapeNode
    let stroke: SKShapeNode

    private init(fill: SKShapeNode, stroke: SKShapeNode) {
        self.fill = fill
        self.stroke = stroke

        super.init()

        addChild(stroke)
        addChild(fill)
    }

    init(path: CGPath, lineWidth: CGFloat, tintColor: UIColor, backgroundColor: UIColor = .black) {
        fill = SKShapeNode.fillTriangle(of: path, fillColor: tintColor)
        stroke = SKShapeNode.strokedTriangle(of: path, lineWidth: lineWidth, strokeColor: tintColor, fillColor: backgroundColor)

        super.init()

        addChild(stroke)
        addChild(fill)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        return Arrow(fill: self.fill.copy(with: zone) as! SKShapeNode, stroke: self.stroke.copy(with: zone) as! SKShapeNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func removeAllActions() {
        super.removeAllActions()

        fill.removeAllActions()
        stroke.removeAllActions()
    }
}


class BolusArrow: SKNode {
    struct Configuration {
        var triangleSize = CGSize(width: 31, height: 25)
        var lineWidth: CGFloat = 3
        var triangleOffsetY: CGFloat = 17
        var tintColor: UIColor = .white
    }

    let top: Arrow
    let bottom: Arrow

    let topRestPosition: CGPoint
    let bottomRestPosition: CGPoint

    init(configuration: BolusArrow.Configuration) {
        let path = CGPath.triangle(in: CGRect(origin: .zero, size: configuration.triangleSize))

        top = Arrow(path: path, lineWidth: configuration.lineWidth, tintColor: configuration.tintColor)
        bottom = top.copy() as! Arrow

        let height = 2 * (configuration.triangleSize.height + configuration.lineWidth) - configuration.triangleOffsetY

        top.position = CGPoint(x: 0, y: (height - configuration.triangleSize.height - configuration.lineWidth) / 2)
        bottom.position = CGPoint(x: 0, y: top.position.y - configuration.triangleOffsetY)

        topRestPosition = top.position
        bottomRestPosition = bottom.position

        super.init()

        addChild(bottom)
        addChild(top)
    }

    override func removeAllActions() {
        super.removeAllActions()

        bottom.removeAllActions()
        top.removeAllActions()
    }

    // MARK: - State

    var isFinished = false {
        didSet {
            physicsBody?.affectedByGravity = true
        }
    }

    private(set) var progress: CGFloat = 0

    func setProgress(_ progress: CGFloat, animationDuration: TimeInterval = 0) {
        guard !isFinished else {
            return
        }

        self.progress = progress

        let bottomPosition = self.bottomPositionY(atProgress: progress)
        let topPosition = self.topPositionY(atProgress: progress)
        let alpha = fillAlpha(atProgress: progress)

        if animationDuration > 0 {
            bottom.run(.moveTo(y: bottomPosition, duration: animationDuration))
            top.run(.moveTo(y: topPosition, duration: animationDuration))
            bottom.fill.run(.fadeAlpha(to: alpha, duration: animationDuration))
            top.fill.run(.fadeAlpha(to: alpha, duration: animationDuration))
        } else {
            bottom.position.y = bottomPosition
            top.position.y = topPosition
            bottom.fill.alpha = alpha
            top.fill.alpha = alpha
        }
    }

    // MARK: - Animation

    private func topPositionY(atProgress progress: CGFloat) -> CGFloat {
        return topRestPosition.y - min(1.0, progress) * (topRestPosition.y - bottomRestPosition.y) / 2
    }

    private func bottomPositionY(atProgress progress: CGFloat) -> CGFloat {
        return bottomRestPosition.y + min(1.0, progress) * (topRestPosition.y - bottomRestPosition.y) / 2
    }

    private func fillAlpha(atProgress progress: CGFloat) -> CGFloat {
        return progress
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        fatalError("copy(with:) has not been implemented")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Extensions

fileprivate extension CGPath {
    // Draws a triangle along the maxY edge of the rect
    static func triangle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.closeSubpath()

        return path
    }

    // Draws a triangle to fill the given rect, based on unit ratios of:
    // {0, 20} -> {17, 0} -> {45, 43}
    static func checkmark(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 20 / 43 * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + 17 / 45 * rect.width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

fileprivate extension SKShapeNode {
    static func strokedTriangle(of path: CGPath, lineWidth: CGFloat, strokeColor: UIColor, fillColor: UIColor) -> SKShapeNode {
        let stroke = SKShapeNode(path: path, centered: true)
        stroke.lineWidth = lineWidth
        stroke.strokeColor = strokeColor
        stroke.lineJoin = .miter
        stroke.lineCap = .square
        stroke.isAntialiased = true
        stroke.fillColor = fillColor
        return stroke
    }

    static func fillTriangle(of path: CGPath, fillColor: UIColor) -> SKShapeNode {
        let fill = SKShapeNode(path: path, centered: true)
        fill.fillColor = fillColor
        fill.alpha = 0
        fill.isAntialiased = false
        fill.lineWidth = 0
        return fill
    }

    static func checkmark(of path: CGPath, lineWidth: CGFloat, strokeColor: UIColor) -> SKShapeNode {
        let stroke = SKShapeNode(path: path, centered: true)
        stroke.lineWidth = lineWidth
        stroke.strokeColor = strokeColor
        stroke.lineJoin = .round
        stroke.lineCap = .round
        stroke.isAntialiased = true
        return stroke
    }
}
