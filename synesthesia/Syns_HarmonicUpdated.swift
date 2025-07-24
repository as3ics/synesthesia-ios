
//
//  Syns.swift (Harmonic-Integrated)
//  synesthesia
//
//  Enhanced with real-time harmonic FFT response.
//

import UIKit
import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Audio and FFT Globals

var fft_buffer: [Float] = Array(repeating: 0.0, count: 1024)
var fft_max: Float = 1.0
var fftSize: Int = 1024
var fftSetup: FFTSetup?

// MARK: - Macros

func getNow() -> UInt64 {
    return DispatchTime.now().uptimeNanoseconds
}

func getScreenFrame() -> CGRect {
    return UIScreen.main.bounds
}

func startAudioInput() {
    let engine = AVAudioEngine()
    let input = engine.inputNode

    let format = input.outputFormat(forBus: 0)
    let bufferSize = AVAudioFrameCount(fftSize)

    input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
        let result = computeFFT(buffer: buffer, M: Int(log2(Double(fftSize))))
        fft_buffer = result
    }

    try? engine.start()
}

func stopAudioInput() {
    let engine = AVAudioEngine()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
}

func computeFFT(buffer: AVAudioPCMBuffer, M: Int) -> [Float] {
    let frameLength = Int(buffer.frameLength)
    guard let channelData = buffer.floatChannelData?[0] else {
        return []
    }

    var real = [Float](repeating: 0.0, count: frameLength)
    var imag = [Float](repeating: 0.0, count: frameLength)
    let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameLength, isHalfWindow: false)
    let channelBuffer = UnsafeBufferPointer(start: channelData, count: frameLength)
    vDSP.multiply(channelBuffer, window, result: &real)


    var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
    let log2n = vDSP_Length(M)
    fftSetup = fftSetup ?? vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

    real.withUnsafeMutableBufferPointer { realPtr in
        imag.withUnsafeMutableBufferPointer { imagPtr in
            var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
            vDSP_fft_zip(fftSetup!, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        }
    }

    var magnitudes = [Float](repeating: 0.0, count: frameLength / 2)
    vDSP.squareMagnitudes(splitComplex, result: &magnitudes)

    var normalized = [Float](repeating: 0.0, count: magnitudes.count)
    var maxMag: Float = 1.0
    vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(magnitudes.count))
    vDSP_vsdiv(magnitudes, 1, &maxMag, &normalized, 1, vDSP_Length(magnitudes.count))

    fft_max = maxMag
    return Array(normalized[0..<normalized.count/2])
}

// MARK: - Syns UIView (Harmonic Integration)

class Syns: UIView {
    private var startTime: UInt64 = getNow()
    private var timer: DispatchSourceTimer?

    // Configurable parameters
    var baseFrequency: Double = 133.33
    var harmonics: [Double] = [1.0, 2.0, 3.0, 4.0]
    var harmonicWeight: Double = 0.33
    var harmonicAmplitudeBoost: Double = 1.5
    var slope: Double = 7.5
    var limiter: Double = 0.9
    var slices: Int = 1000
    var amplitude: Double = 1.0
    var speed: Double = 5.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black
        setupTapGesture()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        self.addGestureRecognizer(tap)
    }

    @objc func tapped() {
        print("Screen tapped!")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let width = rect.width
        let height = rect.height
        let midY = height / 2.0
        let elapsed = Double(getNow() - startTime) / 1_000_000_000.0

        ctx.setFillColor(red: 0.0, green: 39.0/255.0, blue: 76.0/255.0, alpha: 1.0)
        ctx.fill(rect)

        ctx.setLineWidth(0.5)
        ctx.setLineCap(.round)

        for i in 0..<slices {
            let x = CGFloat(i) * width / CGFloat(slices)
            var y = 0.0

            for harmonic in harmonics {
                let bin = Int(harmonic * Double(fft_buffer.count) / (baseFrequency * 4))
                let index = min(fft_buffer.count - 1, bin)
                let influence = Double(fft_buffer[index]) * harmonicWeight * harmonicAmplitudeBoost
                y += influence * sin(harmonic * (elapsed * speed + Double(i)) / baseFrequency)
            }

            y *= amplitude
            y = midY + CGFloat(y * limiter * midY)

            ctx.setStrokeColor(UIColor(red: 255/255, green: 203/255, blue: 5/255, alpha: 0.75).cgColor)
            ctx.move(to: CGPoint(x: x, y: midY))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.strokePath()
        }
    }

    func start() {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer?.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer?.setEventHandler { [weak self] in self?.setNeedsDisplay() }
        timer?.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - SwiftUI Bridge

struct SynesthesiaWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> Syns {
        let view = Syns(frame: UIScreen.main.bounds)
        view.start()
        startAudioInput()
        return view
    }

    func updateUIView(_ uiView: Syns, context: Context) {}
}
