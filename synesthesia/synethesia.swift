
//
//  CombinedSyns.swift
//  synesthesia
//
//  This file combines Syns.swift and macros.swift without changing functionality.
//  Syns logic + microphone + FFT + utility macros in one.
//
//  Created by as3six on 7/23/25.
//

// MARK: - Imports

import UIKit
import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Macros.swift content

//
//  microphone.swift
//  synesthesia
//
//  Created by as3six on 7/23/25.
//

import Foundation
import AVFoundation
import UIKit
import Accelerate

let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
let M: Int = 8
var samples_buffer: [Float] = []
var fft_buffer: [Float] = []
var amplitude: Float = 0.0
var fft_max: Float = 0.0
var listening: Bool = false

func startAudioInput() {
    listening = true
    
    let format = inputNode.outputFormat(forBus: 0)
    let bufferSize: AVAudioFrameCount = AVAudioFrameCount(pow(2.0, Double(M)))
    
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
        
        if(listening) {
            samples_buffer = bufferToFloatArrayAllChannels(buffer)
            fft_buffer = computeFFT(buffer: buffer, M: M)
            
            var max_sample: Float = 0.0
            var max_fft: Float = 0.0
            for i in samples_buffer {
                if(abs(i) > max_sample) {
                    max_sample = abs(i)
                }
            }
            
            for i in fft_buffer {
                if(abs(i) > max_fft) {
                    max_fft = abs(i)
                }
            }
            
            amplitude = max_sample
            fft_max = max_fft
            
            print(String(format: "fft max: %.2f", fft_max))
            print(String(format: "amplitude: %.2f\n", amplitude))
        } else {
            stopAudioInput()
        }
    }
    
    print("Audio Engine Starting:")
    
    do {
        try audioEngine.start()
    } catch {
        print("Audio Engine Error: \(error)")
    }
}

func stopAudioInput() {
    listening = false
    
    inputNode.removeTap(onBus: 0)
    
    if audioEngine.isRunning {
        audioEngine.stop()
        print("Audio input stopped.")
    } else {
        print("Audio engine was not running.")
    }
    
    fft_buffer = []
    samples_buffer = []
}


func bufferToFloatArrayAllChannels(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let floatChannelData = buffer.floatChannelData else {
        return []
    }

    let frameLength = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var result = [Float]()

    for c in 0..<channelCount {
        let channel = floatChannelData[c]
        result.append(contentsOf: UnsafeBufferPointer(start: channel, count: frameLength))
    }

    return result
}


/// Computes FFT magnitudes from an AVAudioPCMBuffer for a given power-of-two length M.
/// - Parameters:
///   - buffer: The audio buffer to analyze (mono or first channel only).
///   - M: The log2 of the FFT size (i.e., for 1024 samples, M = 10).
/// - Returns: An array of normalized magnitudes (linear scale).
func computeFFT(buffer: AVAudioPCMBuffer, M: Int) -> [Float] {
    let N = 1 << M
    guard let channelData = buffer.floatChannelData?[0] else {
        fatalError("Failed to access channel data.")
    }

    let frameLength = Int(buffer.frameLength)
    precondition(frameLength >= N, "Buffer must contain at least \(N) samples (2^\(M)).")

    // Extract samples from first channel
    let samples = Array(UnsafeBufferPointer(start: channelData, count: N))

    // Apply Hann window
    var window = [Float](repeating: 0.0, count: N)
    vDSP_hann_window(&window, vDSP_Length(N), Int32(vDSP_HANN_NORM))

    var windowedSamples = [Float](repeating: 0.0, count: N)
    vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(N))

    // Create FFT setup
    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(M), FFTRadix(kFFTRadix2)) else {
        fatalError("Failed to create FFT setup.")
    }

    // Allocate split-complex memory
    var real = [Float](repeating: 0.0, count: N / 2)
    var imag = [Float](repeating: 0.0, count: N / 2)

    windowedSamples.withUnsafeBufferPointer { inputPtr in
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Convert interleaved real input to split-complex
                inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: N / 2) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(N / 2))
                }

                // Perform FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(M), FFTDirection(FFT_FORWARD))
                splitComplex.imagp[0] = 0.0 // Remove DC imaginary
            }
        }
    }

    // Compute magnitudes from real/imag
    var magnitudes = [Float](repeating: 0.0, count: N / 2)
    real.withUnsafeMutableBufferPointer { realPtr in
        imag.withUnsafeMutableBufferPointer { imagPtr in
            var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
            vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(N / 2))
        }
    }

    // Normalize and convert to linear magnitude
    var normalizedMagnitudes = [Float](repeating: 0.0, count: N / 2)
    var scale: Float = 1.0 / Float(N)

    vDSP_vsmul(sqrtArray(magnitudes), 1, &scale, &normalizedMagnitudes, 1, vDSP_Length(N / 2))
    vDSP_destroy_fftsetup(fftSetup)
    
//    return Array(normalizedMagnitudes[0..<normalizedMagnitudes.count / 2])
    return normalizedMagnitudes
}


/// Computes square roots of an array of Floats.
private func sqrtArray(_ input: [Float]) -> [Float] {
    var output = [Float](repeating: 0.0, count: input.count)
    vvsqrtf(&output, input, [Int32(input.count)])
    return output
}


func getScreenFrame() -> CGRect {
    return UIScreen.main.bounds
}

func getNow() -> UInt64 {
    return DispatchTime.now().uptimeNanoseconds
}

// MARK: - Syns.swift content

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

    // MARK: - Public Computed Properties

    var desiredfr: Double { _framerate ?? 10.0 }
    var delay: Double { 1.0 / desiredfr }
    var limiter: Double { _limiter ?? 0.9 }
    var fft_limiter: Double { _fft_limiter ?? 0.1 }
    var slope: Double { _slope ?? 7.5 }
    var speed: Double { _speed ?? 122.22 } // span / sec
    var xoffset: Double { maxY * 0.1 }
    var expander: Double { _expander ?? 1.5 }
    var frequency: Double { _frequency ?? 133.33 }
    var slices: Double { _slices ?? 5000.0 }
    var span: Double { _span ?? 24.0 * Double.pi }
    var power: Double { _power ?? 0.9 }
    var phase: Double { _phase ?? Double.pi }

    // MARK: - Derived Values

    private var slice: Double { maxX / slices }
    private var lastTime: UInt64 { get { _lastTime ?? 0 } set { _lastTime = newValue } }
    private var thisTime: UInt64 { getNow() }
    private var period: UInt64 { thisTime - lastTime }
    private var periodSec: Double? { Double(period) / 1000000000.0 }
    var framerate: Double { 1.0 / (periodSec ?? 1.0) }
    private var startTime: UInt64 = 0
    private var runSec: Double { Double(getNow() - startTime) / 1000000000.0 }
    var linesWidth: Double { _linesWidth ?? 0.1 }

    // MARK: - Colors

    var blueColor: CIColor { CIColor(red: 0.0, green: 39.0 / 255.0, blue: 76.0 / 255.0, alpha: 1.0) }
    var yellowColor: CIColor { CIColor(red: 255.0 / 255.0, green: 203.0 / 255.0, blue: 5.0 / 255.0, alpha: 0.76) }
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
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(red: blueColor.red, green: blueColor.green, blue: blueColor.blue, alpha: blueColor.alpha)
        ctx.fill(rect)

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

        for i in 0..<Int(numSlices) {
            let x1 = CGFloat(i) * sliceWidth - xoffset
            let y1 = midY + limiter * midY * CGFloat(sin(Double(runSec * speed + x1 + phase) / frequency))
            let x2 = pow(x1 + (Double(i) / Double(slices)) * span * slope, power)
            let y2 = midY

            let one = CGPoint(x: x1, y: y1)
            let two = CGPoint(x: x2, y: y2)

            if one.x.isFinite && one.y.isFinite && two.x.isFinite && two.y.isFinite {
                ctx.move(to: one)
                ctx.addLine(to: two)
                ctx.strokePath()
            }
        }

        guard let ctx2 = UIGraphicsGetCurrentContext() else { return }

        let n = fft_buffer.count
        var maxFFT: Float = 0.0
        for i in fft_buffer {
            if abs(i) > maxFFT {
                maxFFT = abs(i)
            }
        }

        let tuning_variable_1 = 100.0
        for i in 0..<fft_buffer.count {
            ctx2.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: 0.7))
            ctx2.setLineWidth(CGFloat(maxX) * 0.98 / CGFloat(fft_buffer.count))
            ctx2.setLineCap(.square)

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

        for i in 0..<fft_buffer.count {
            let alpha = pow(0.4 * fft_buffer[i] / fft_max, 1.2)
            ctx2.setStrokeColor(CGColor(red: whiteColor.red, green: whiteColor.green, blue: whiteColor.blue, alpha: CGFloat(alpha)))
            ctx2.setLineWidth((CGFloat(maxX) * 0.9 / CGFloat(max(n, 1))))
            ctx2.setLineCap(.butt)

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
                ctx2.move(to: one)
                ctx2.addLine(to: two)
                ctx2.strokePath()
            }
        }

    // ... [rest of file unchanged] ...

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
