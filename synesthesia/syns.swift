//
//  Syns.swift
//  synesthesia
//
//  Created by as3six on 7/23/25.
//

import UIKit
import SwiftUI

// MARK: - Syns

var started: Bool = true

class Syns: UIView {

    // MARK: - Private Config Variables
    
    private var _framerate: Double?
    private var _slices: Double?
    private var _movement: Double?
    private var _span: Double?
    private var _limiter: Double?
    private var _slope: Double?
    private var _lastTime: UInt64?
    private var _speed: Double?
    private var _linesWidth: Double?
    private var _expander: Double?
    private var _frequency: Double?
    private var _power: Double?
    private var _phase: Double?
    private var _fft_limiter: Double?
    
    // Harmonic configuration
    var baseFrequency: Double = 133.33       // Base cycle frequency
    var harmonics: [Double] = [1.0, 1.0, 1.0, 1.0]  // Harmonic multipliers
    var harmonicWeight: Double = 0.33        // Scaling factor per harmonic
    // MARK: - Public Computed Properties

    var desiredfr: Double { _framerate ?? 10.0 }
    var delay: Double { 1.0 / desiredfr }
    var limiter: Double { _limiter ?? 0.88 }
    var fft_limiter: Double { _fft_limiter ?? 0.1 }
    var slope: Double { _slope ?? 1000.0 }
    var speed: Double { _speed ?? 122.22 } // span / sec
    var xoffset: Double { maxY * 0.1 }
    var expander: Double { _expander ?? 2.5 }
    var frequency: Double { _frequency ?? 133.33 }
    var slices: Double { _slices ?? 2000.0 }
    var span: Double { _span ?? 3.0 * Double.pi }
    var power: Double { _power ?? 0.9 }
    var phase: Double { _phase ?? Double.pi }
    var linesWidth: Double { _linesWidth ?? 0.3 }

    // MARK: - Derived Values

    private var slice: Double { maxX / slices }
    private var lastTime: UInt64 { get { _lastTime ?? 0 } set { _lastTime = newValue } }
    private var thisTime: UInt64 { getNow() }
    private var period: UInt64 { thisTime - lastTime }
    private var periodSec: Double? { Double(period) / 1000000000.0 }
    var framerate: Double { 1.0 / (periodSec ?? 1.0) }
    private var startTime: UInt64 = 0
    private var runSec: Double { Double(getNow() - startTime) / 1000000000.0 }

    // MARK: - Colors

    var blueColor: CIColor { CIColor(red: 0.0, green: 39.0 / 255.0, blue: 76.0 / 255.0, alpha: 1.0) }
    var yellowColor: CIColor { CIColor(red: 255.0 / 255.0, green: 203.0 / 255.0, blue: 5.0 / 255.0, alpha: 0.86) }
    var whiteColor: CIColor { CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5) }
    var blackColor: CIColor { CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5) }

    // MARK: - Geometry

    var midX: Double { getScreenFrame().width / 2.0 }
    var midY: Double { getScreenFrame().height / 2.0 }
    var maxX: Double { getScreenFrame().width }
    var maxY: Double { getScreenFrame().height }

    var axisLeft: CGPoint { CGPoint(x: 0.0, y: midY) }
    var axisRight: CGPoint { CGPoint(x: maxX, y: midY) }

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        let time = thisTime
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(red: blueColor.red, green: blueColor.green, blue: blueColor.blue, alpha: blueColor.alpha)
        ctx.fill(rect)

        let n = fft_buffer.count
        var maxFFT: Float = 0.0
        for i in fft_buffer {
            if abs(i) > maxFFT {
                maxFFT = abs(i)
            }
        }

        let tuning_variable_1 = 66.7
        
        for i in 0..<fft_buffer.count {
            let alpha = pow(0.2 * fft_buffer[i] / fft_max, 1.2)
            ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: CGFloat(alpha)))
            ctx.setLineWidth((CGFloat(maxX) * 0.8 / CGFloat(max(n, 1))))
            ctx.setLineCap(.round)

            let lineLength = tuning_variable_1 * 0.4 * Double(fft_buffer[i] / fft_max)
            let x1 = CGFloat(maxX * Double(i) / Double(n))
            let y1 = CGFloat(midY)

            // ✅ Adjusted to ensure the lines are flush with the horizon
            // by capping y2 exactly at midY and using lineLength just for horizontal skew
            let x2 = x1 - CGFloat(lineLength * 0.5) // slight left slant
            let y2 = y1 + CGFloat(lineLength * 0.6) // fixed slope so it ends slightly below midY only based on magnitude

            let one = CGPoint(x: x1, y: y1)
            let two = CGPoint(x: x2, y: y2)

            if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
                ctx.move(to: one)
                ctx.addLine(to: two)
                ctx.strokePath()
            }
        }
        
        for i in 0..<fft_buffer.count {
            ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: whiteColor.alpha))
            ctx.setLineWidth(CGFloat(maxX) * 0.9 / CGFloat(fft_buffer.count))
            ctx.setLineCap(.square)

            let height = (Double(maxY) / 2.0) - tuning_variable_1 * Double(fft_buffer[i] / fft_max)

            let x1 = CGFloat(maxX * Double(i) / Double(n))
            let y1 = CGFloat(height)
            let x2 = x1
            let y2 = CGFloat(midY)

            let one = CGPoint(x: x1, y: y1)
            let two = CGPoint(x: x2, y: y2)

            if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
                ctx.move(to: one)
                ctx.addLine(to: two)
                ctx.strokePath()
            }
        }
        
        let text = String(format: "%0.2f", framerate)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor(ciColor: whiteColor)
        ]
        let origin = CGPoint(x: maxX - 75, y: maxY - 20)
        (text as NSString).draw(at: origin, withAttributes: attributes)

        let maxX = CGFloat(maxX)
        let maxY = CGFloat(maxY)
        let midY = maxY / 2.0

        ctx.setStrokeColor(CGColor(red: yellowColor.red, green: yellowColor.green, blue: yellowColor.blue, alpha: yellowColor.alpha))
        ctx.setLineWidth(linesWidth)
        ctx.setLineCap(.round)

        let numSlices = slices
        let sliceWidth = (maxX / CGFloat(numSlices)) * expander

        // Harmonic gain multipliers (can be adjusted in real-time)
        let harmonic3Gain: Double = 0.001
        let harmonic5Gain: Double = 0.0
        let harmonic7Gain: Double = 0.001
        let harmonic9Gain: Double = 0.0
        let harmonic11Gain: Double = 0.001
        let harmonic13Gain: Double = 0.0
        let harmonic15Gain: Double = 0.0
        
        var connectors: [CGPoint] = []
        
        for i in 0..<Int(numSlices) {
            let x1 = CGFloat(i) * sliceWidth - xoffset
            let baseAngle = Double(runSec * speed + x1 + phase)

            // You can scale up the amplitude to exaggerate the harmonic wobble effect
            let scaledAmp = pow(Double(amplitude) * 66.6,  1.4) // ← You can tweak this multiplier live

            // Base wave
            var y1 = sin(baseAngle / frequency)
            
            // Harmonics (add harmonic9Gain fix too)
            y1 += harmonic3Gain * scaledAmp * sin(baseAngle / (frequency / 3.0))
            y1 += harmonic5Gain * scaledAmp * sin(baseAngle / (frequency / 5.0))
            y1 += harmonic7Gain * scaledAmp * sin(baseAngle / (frequency / 7.0))
            y1 += harmonic9Gain * scaledAmp * sin(baseAngle / (frequency / 9.0))
            y1 += harmonic11Gain * scaledAmp * sin(baseAngle / (frequency / 11.0))
            y1 += harmonic13Gain * scaledAmp * sin(baseAngle / (frequency / 13.0))
            y1 += harmonic15Gain * scaledAmp * sin(baseAngle / (frequency / 15.0))


            // Total scaled y-value
            let y1Final = midY + limiter * midY * CGFloat(y1)

            let x2 = pow(x1 + (Double(i) / Double(slices)) * span * slope, power)
            let y2 = midY

            let one = CGPoint(x: x1, y: y1Final)
            let two = CGPoint(x: x2, y: y2)
            
            connectors.append(one)

            if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
                ctx.move(to: one)
                ctx.addLine(to: two)
                ctx.strokePath()
            }
        }
        
        ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: whiteColor.alpha))
        ctx.setLineWidth(linesWidth * 2)
        ctx.setLineCap(.round)
        
        for i in 1..<connectors.count {
            let one = connectors[i]
            let two = connectors[i-1]
            
            if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
                ctx.move(to: one)
                ctx.addLine(to: two)
                ctx.strokePath()
            }
            
        }
        
        lastTime = time
    }

    // MARK: - Timer and Line Management

    private var timer: DispatchSourceTimer?

    override init(frame: CGRect = getScreenFrame()) {
        super.init(frame: frame)
        self.startTime = getNow()
        backgroundColor = UIColor(ciColor: blueColor)
        setupTapGesture()
    }

    private func setupTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        print("Screen tapped!")
        tapped()
    }

    private func tapped() {
        started = !started

        if started {
            startAudioInput()
        } else {
            stopAudioInput()
        }
    }

    func tick() {
        DispatchQueue.main.async {
            self.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start() {
        started = true
        lastTime = DispatchTime.now().uptimeNanoseconds
        let queue = DispatchQueue(label: "my.timer.queue")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: delay)
        timer?.setEventHandler { [weak self] in
            self?.tick()
        }
        timer?.resume()
    }

    func stop() {
        started = false
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Preview

struct SynsPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> Syns {
        let view = Syns()
        view.backgroundColor = UIColor(ciColor: view.blueColor)
        return view
    }

    func updateUIView(_ uiView: Syns, context: Context) {
        // Optional: dynamically update lines here if needed
    }
}

struct Syns_Previews: PreviewProvider {
    static var previews: some View {
        SynsPreview()
            .frame(width: 400, height: 300)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Syns Axis Line")
    }
}

struct SynesthesiaWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> Syns {
        let view = Syns(frame: UIScreen.main.bounds)
        view.start()
        startAudioInput()
        return view
    }

    func updateUIView(_ uiView: Syns, context: Context) {
        // Update if needed
    }
}
