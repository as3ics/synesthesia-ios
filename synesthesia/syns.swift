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
var stats: Bool = true

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
    var slices: Double { _slices ?? 2222.0 }
    var span: Double { _span ?? 3.0 * Double.pi }
    var power: Double { _power ?? 0.9 }
    var phase: Double { _phase ?? Double.pi }
    var linesWidth: Double { _linesWidth ?? 0.67 }

    // MARK: - Derived Values

    private var slice: Double { maxX / slices }
    private var lastTime: UInt64 { get { _lastTime ?? 0 } set { _lastTime = newValue } }
    private var thisTime: UInt64 { getNow() }
    private var period: UInt64 { thisTime - lastTime }
    private var periodSec: Double? { Double(period) / 1000000000.0 }
    private var framerate: Double { 1.0 / (periodSec ?? 1.0) }
    private var startTime: UInt64 = 0
    private var runSec: Double { Double(getNow() - startTime) / 1000000000.0 }

    // MARK: - Colors

    var blueColor: CIColor { CIColor(red: 0.0, green: 56.0 / 255.0, blue: 184.0 / 255.0, alpha: 1.0) }
    var yellowColor: CIColor { CIColor(red: 255.0 / 255.0, green: 203.0 / 255.0, blue: 5.0 / 255.0, alpha: 0.7) }
    var whiteColor: CIColor { CIColor(red: 255.0 / 255.0 , green: 255.0 / 255.0 , blue: 255.0 / 255.0, alpha: 0.8) }
    var tintedColor: CIColor {  CIColor(red: 255.0 / 255.0 , green: 203.0 / 255.0 , blue: 5.0 / 255.0, alpha: 0.1)}

    // MARK: - Geometry

    var midX: Double { getScreenFrame().width / 2.0 }
    var midY: Double { getScreenFrame().height / 2.0 }
    var maxX: Double { getScreenFrame().width }
    var maxY: Double { getScreenFrame().height }

    var axisLeft: CGPoint { CGPoint(x: 0.0, y: midY) }
    var axisRight: CGPoint { CGPoint(x: maxX, y: midY) }
    
    private let tuning_variable_1 = 122.2                   // white line length
    private let tuning_variable_2 = 0.001                   // yellow line width by peak frequency
    private let tuning_variable_3 = 0.4                     // slanted white line alpha
    
    // Harmonic gain multipliers (can be adjusted in real-time)
    private let harmonic3Gain: Double = 0.0011
    private let harmonic5Gain: Double = Double(peak_frequency) * 0.000001
    private let harmonic7Gain: Double = 0.0011
    private let harmonic9Gain: Double =  Double(peak_frequency) * 0.000001
    private let harmonic11Gain: Double = 0.0011
    private let harmonic13Gain: Double =  Double(peak_frequency) * 0.000001
    private let harmonic15Gain: Double = 0.0
    
    private let wobbleSpeed: Double = 22.2       // Frequency of wobble (Hz)
    private let wobbleAmount: Double = 11.1     // Max phase offset
    
    private var as3sixButton: UIButton!
    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        let time = thisTime
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // Draw Background
        
        ctx.setFillColor(red: blueColor.red, green: blueColor.green, blue: blueColor.blue, alpha: blueColor.alpha)
        ctx.fill(rect)
        
        // Draw Labels
        
        if(listening && stats) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor(ciColor: whiteColor)
            ]
            
            let text = String(format: "fps: %0.2f", framerate)
            let origin = CGPoint(x: maxX - 95, y: maxY - 20)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            
            let text2 = String(format: "fft max: %.2f", fft_max)
            let origin2 = CGPoint(x: 25, y: maxY - 20)
            (text2 as NSString).draw(at: origin2, withAttributes: attributes)
            
            let text3 = String(format: "amplitude: %.2f", amplitude)
            let origin3 = CGPoint(x: 25, y: maxY - 35)
            (text3 as NSString).draw(at: origin3, withAttributes: attributes)
            
            let text4 = String(format: "peak frequency: %.2f\n", peak_frequency)
            let origin4 = CGPoint(x: 25, y: maxY - 50)
            (text4 as NSString).draw(at: origin4, withAttributes: attributes)
        }
        
        for i in 0..<fft_buffer.count {
            let alpha = pow(0.2 * fft_buffer[i] / fft_max, 1.2)
            ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: CGFloat(alpha)))
            ctx.setLineWidth((CGFloat(maxX) * 0.8 / CGFloat(max(fft_buffer.count, 1))))
            ctx.setLineCap(.round)
            
            let lineLength = tuning_variable_1 * Double(fft_buffer[i] / fft_max)
            let x1 = CGFloat(maxX * Double(i) / Double(fft_buffer.count))
            let y1 = CGFloat(midY)
            
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
            
            let x1 = CGFloat(maxX * Double(i) / Double(fft_buffer.count))
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
        
        // Draw the horizontal axis
        
        ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: whiteColor.alpha / 2.0))
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.square)
        
        let one = CGPoint(x: 0.0, y: midY)
        let two = CGPoint(x: maxX, y: midY)
        
        if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
            ctx.move(to: one)
            ctx.addLine(to: two)
            ctx.strokePath()
        }
        
        // Draw Sinusoids
        
        let wobblePhase = sin(runSec * wobbleSpeed) * wobbleAmount
        let max_possible_frequency = Double(getMaxFrequency(from: fft_buffer, M: M, sampleRate: sampling_rate))
        
        // Target color components when boosted (e.g. white or anything else)
        let shiftRed: CGFloat = tintedColor.red
        let shiftGreen: CGFloat = tintedColor.green
        let shiftBlue: CGFloat = tintedColor.blue
        let shiftAlpha: CGFloat = tintedColor.alpha
        
        let tuning_blend_boost = 2.2  // ← Tweak this to exaggerate the shift
        let freqRatio = min(Double(peak_frequency) / max_possible_frequency, 1.0)
        let ampRatio = min(Double(amplitude) / 0.5, 1.0)
        let rawBlend = (freqRatio + ampRatio) / 2.0
        let boostedBlend = min(rawBlend * tuning_blend_boost, 1.0)
        
        // Interpolate from yellowColor → shiftColor
        var red   = yellowColor.red   * (1.0 - boostedBlend) + shiftRed   * boostedBlend
        var green = yellowColor.green * (1.0 - boostedBlend) + shiftGreen * boostedBlend
        var blue  = yellowColor.blue  * (1.0 - boostedBlend) + shiftBlue  * boostedBlend
        var alpha = yellowColor.alpha * (1.0 - boostedBlend) + shiftAlpha * boostedBlend
        
        if(red.isNaN == true) { red = yellowColor.red }
        if(green.isNaN == true) { green = yellowColor.green }
        if(blue.isNaN == true) { blue = yellowColor.blue }
        if(alpha.isNaN == true) { alpha = yellowColor.red }
        
        
        print(String(format: "color> r: %0.4f, g: %0.4f, b: %0.4f, a: %0.4f\n", red, green, blue, alpha))
        
        let width = max(linesWidth * Double(amplitude) * tuning_variable_2 * Double(peak_frequency), linesWidth)
                            
        // Draw Yellow Lines
        ctx.setStrokeColor(CGColor(red: red, green: green, blue: blue,alpha: alpha))
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)

        let numSlices = slices
        let sliceWidth = (maxX / CGFloat(numSlices)) * expander
        
        var connectors: [CGPoint] = []
        
        for i in 0..<Int(numSlices) {
            let x1 = CGFloat(i) * sliceWidth - xoffset
            let baseAngle = Double(runSec * speed + x1 + phase)

            // You can scale up the amplitude to exaggerate the harmonic wobble effect
            let scaledAmp = pow(Double(amplitude) * 88.8,  1.4)// ← You can tweak this multiplier live

            // Base wave with wobble
            var y1 = sin((baseAngle + wobblePhase) / frequency)

            // Harmonics with wobble phase
            y1 += harmonic3Gain * scaledAmp * sin((baseAngle + wobblePhase) / (frequency / 3.0))
            y1 += harmonic5Gain * scaledAmp * sin((baseAngle + wobblePhase * 1.5) / (frequency / 5.0))
            y1 += harmonic7Gain * scaledAmp * sin((baseAngle + wobblePhase * 2.0) / (frequency / 7.0))
            y1 += harmonic9Gain * scaledAmp * sin((baseAngle + wobblePhase * 2.5) / (frequency / 9.0))
            y1 += harmonic11Gain * scaledAmp * sin((baseAngle + wobblePhase * 3.0) / (frequency / 11.0))
            y1 += harmonic13Gain * scaledAmp * sin((baseAngle + wobblePhase * 3.5) / (frequency / 13.0))
            y1 += harmonic15Gain * scaledAmp * sin((baseAngle + wobblePhase * 4.0) / (frequency / 15.0))



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
        
        // Draw white line over sinusoidal
        
        ctx.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: 1.0))
        ctx.setLineWidth(max(linesWidth * Double(amplitude) * tuning_variable_2 * Double(peak_frequency), linesWidth * 3.0))
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
        setupButton()
    }

    private func setupButton() {
        as3sixButton = UIButton(type: .system)

        // Set PDF image
        let image = UIImage(named: "as3six_icon")
        as3sixButton.setImage(image, for: .normal)
        as3sixButton.tintColor = .white // optional, for template rendering

        // Set button frame (top-right corner)
        let size: CGFloat = 35.0
        as3sixButton.frame = CGRect(x: maxX - size - 20, y: 20, width: size, height: size)

        // Optional style
        as3sixButton.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        as3sixButton.layer.cornerRadius = size / 2

        // Add action
        as3sixButton.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)

        // Add to view
        self.addSubview(as3sixButton)
    }
    
    @objc private func buttonPressed() {
        print("Action button tapped!")
        // You can toggle state or trigger any action here
        toggleStats()  // Optionally reuse tap behavior
    }
    
    private func toggleStats() {
        stats = !stats
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
