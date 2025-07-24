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
let M: Int = 9
var samples_buffer: [Float] = []
var fft_buffer: [Float] = []
var amplitude: Float = 0.0
var fft_max: Float = 0.0
var peak_frequency: Float = 0.0
var listening: Bool = false
var sampling_rate: Double = 44100.0

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
            peak_frequency = getPeakFrequency(from: fft_buffer, M: M, sampleRate: 44100.0)
            
            print(String(format: "fft max: %.2f", fft_max))
            print(String(format: "amplitude: %.2f", amplitude))
            print(String(format: "peak frequency: %.2f\n", peak_frequency))
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
    fft_max = 0.0
    amplitude = 0.0
    peak_frequency = 0.0
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
func computeFFT(buffer: AVAudioPCMBuffer, M: Int, half: Bool = false) -> [Float] {
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
    
    if(half) {
        return Array(normalizedMagnitudes[0..<2 * normalizedMagnitudes.count / 4])
    } else {
        return normalizedMagnitudes
    }
    
    
}

/// Returns the frequency (in Hz) of the peak magnitude in the FFT buffer.
/// - Parameters:
///   - fft: The FFT magnitudes array (e.g., `fft_buffer`)
///   - M: The power-of-2 used for FFT size
///   - sampleRate: The audio sample rate (e.g., 44100.0)
/// - Returns: The frequency (Hz) of the peak bin
func getPeakFrequency(from fft: [Float], M: Int, sampleRate: Double) -> Float {
    guard !fft.isEmpty else { return 0.0 }

    // Find index of max magnitude
    var maxIndex: vDSP_Length = 0
    var maxValue: Float = 0.0
    vDSP_maxvi(fft, 1, &maxValue, &maxIndex, vDSP_Length(fft.count))

    let binIndex = Int(maxIndex)
    let fftSize = 1 << M
    let frequencyResolution = sampleRate / Double(fftSize)

    let peakFrequency = Double(binIndex) * frequencyResolution
    return Float(peakFrequency)
}

/// Returns the max frequency (in Hz) in the FFT buffer.
/// - Parameters:
///   - fft: The FFT magnitudes array (e.g., `fft_buffer`)
///   - M: The power-of-2 used for FFT size
///   - sampleRate: The audio sample rate (e.g., 44100.0)
/// - Returns: The frequency (Hz) of the peak bin
func getMaxFrequency(from fft: [Float], M: Int, sampleRate: Double) -> Float {
    guard !fft.isEmpty else { return 0.0 }

    // Find index of max magnitude
    var maxIndex: Int = fft.count - 1

    let binIndex = maxIndex
    let fftSize = 1 << M
    let frequencyResolution = sampleRate / Double(fftSize)

    let maxFrequency = Double(binIndex) * frequencyResolution
    return Float(maxFrequency)
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
