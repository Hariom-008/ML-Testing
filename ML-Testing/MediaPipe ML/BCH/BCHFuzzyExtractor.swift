// BCHFuzzyExtractor.swift

import Foundation

final class BCHFuzzyExtractor {
    struct Layout {
        let m: Int
        let n: Int
        let t: Int
        let requestedBits: Int        // = distanceCount * bitsPerDistance (1088)
        let bchDataBits: Int          // = n - m * t (1479 for your params)
        let eccBits: Int              // = m * t (2616)
        var errlocSlots: Int { t + 2 }
    }

    private(set) var layout: Layout
    private var ctx: UnsafeMutablePointer<bch_control>?

    /// distanceCount = 136, bitsPerDistance = 8, errorRate = 0.21 (same as JS)
    ///  101 * 8 = 808
    ///    80%
    ///    0.21
    ///    out of 808 - 169 or 170
    init?(distanceCount: Int,
          bitsPerDistance: Int,
          errorRate: Double = 0.21,
          primPoly: UInt32 = 0) {

        let requestedBits = distanceCount * bitsPerDistance
        let minErrors = max(1, Int(ceil(Double(requestedBits) * errorRate)))

        var chosen: Layout? = nil

        for m in 5...15 {
            let n = (1 << m) - 1
            let maxT = (n - requestedBits) / m
            if maxT < minErrors { continue }

            let t = minErrors
            let bchDataBits = n - m * t
            let eccBits = m * t
            if bchDataBits <= 0 { continue }

            chosen = Layout(
                m: m,
                n: n,
                t: t,
                requestedBits: requestedBits,
                bchDataBits: bchDataBits,
                eccBits: eccBits
            )
            break
        }

        guard let layout = chosen else {
            print("❌ BCHFuzzyExtractor: no valid layout for requestedBits=\(requestedBits)")
            return nil
        }

        guard let c = init_bch(Int32(layout.m), Int32(layout.t), primPoly) else {
            print("❌ init_bch failed")
            return nil
        }

        self.layout = layout
        self.ctx = c

        print("✅ BCH layout: m=\(layout.m), n=\(layout.n), t=\(layout.t), " +
              "requestedBits=\(layout.requestedBits), bchDataBits=\(layout.bchDataBits), eccBits=\(layout.eccBits)")
    }

    deinit {
        if let c = ctx {
            free_bch(c)
        }
    }

    var dataBits: Int { layout.requestedBits }  // 1088
    var eccBits: Int { layout.eccBits }        // 2616

    /// Encode requestedBits bits (0/1 per element) → eccBits bits.
    func encodeBits(sourceBits: [UInt8]) -> [UInt8]? {
        guard let ctx = ctx else { return nil }
        guard sourceBits.count == layout.requestedBits else {
            print("❌ encodeBits: expected \(layout.requestedBits) bits, got \(sourceBits.count)")
            return nil
        }

        // Internal BCH buffer (n - eccBits) bits
        var dataBuf = [UInt8](repeating: 0, count: layout.bchDataBits)
        dataBuf.replaceSubrange(0..<sourceBits.count, with: sourceBits)

        var eccBuf = [UInt8](repeating: 0, count: layout.eccBits)

        dataBuf.withUnsafeMutableBytes { dataPtr in
            eccBuf.withUnsafeMutableBytes { eccPtr in
                encodebits_bch(
                    ctx,
                    dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    eccPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        return eccBuf
    }

    /// Optional: decode + correct if you need reproduce() in Swift later.
    func decodeBits(dataBits: [UInt8],
                    eccBits: [UInt8]) -> (errorCount: Int, correctedData: [UInt8])? {
        guard let ctx = ctx else { return nil }
        guard dataBits.count == layout.requestedBits,
              eccBits.count == layout.eccBits else {
            print("❌ decodeBits length mismatch")
            return nil
        }

        var dataBuf = [UInt8](repeating: 0, count: layout.bchDataBits)
        dataBuf.replaceSubrange(0..<dataBits.count, with: dataBits)
        var eccBuf = eccBits
        var errloc = [UInt32](repeating: 0, count: layout.errlocSlots)

        let errCount: Int32 = dataBuf.withUnsafeMutableBytes { dataPtr in
            eccBuf.withUnsafeMutableBytes { eccPtr in
                errloc.withUnsafeMutableBufferPointer { errPtr in
                    decodebits_bch(
                        ctx,
                        dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        eccPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        errPtr.baseAddress!
                    )
                }
            }
        }

        if errCount >= 0 && errCount <= Int32(layout.errlocSlots) {
            if errCount > 0 {
                dataBuf.withUnsafeMutableBytes { dataPtr in
                    errloc.withUnsafeMutableBufferPointer { errPtr in
                        correctbits_bch(
                            ctx,
                            dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            errPtr.baseAddress!,
                            errCount
                        )
                    }
                }
            }
            let corrected = Array(dataBuf[0..<layout.requestedBits])
            return (Int(errCount), corrected)
        } else {
            return (Int(errCount), dataBits)
        }
    }
}
