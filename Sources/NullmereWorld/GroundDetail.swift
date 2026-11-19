import Foundation

/// The ground's detail close to, as one small picture laid over the land
/// again and again (the shaders' `NM_DETAIL`): in its red, the clumps of a
/// meadow's grass, bright where they stand and dark in the gaps between; in
/// its green, the grit and pebbles of bare earth, sand and stone; in its
/// blue, a mottle across the whole. Each of those channels' mean is a half,
/// so laid over a colour as a swing about one it changes no mean; and drawn
/// far off, its smaller levels, each the mean of four of the larger, leave
/// the mean alone. In its alpha, a dry salt pan's crust: polygons, their
/// rims raised and bright, their floors dark, read by the shaders' salt
/// only. It tiles: its right edge runs on into its left and its foot into
/// its head. The same every time.
public enum GroundDetail {
    /// Its pixels across, and down.
    public static let side = 128
    /// How many times it is laid across a unit of the land.
    public static let perUnit: Float = 2

    /// Its pixels, four bytes each (red, green, blue, and the crust in its
    /// alpha), row by row.
    public static let pixels: [UInt8] = make()

    /// Its levels for drawing far off: itself, then each half the side of
    /// the one before, to a single pixel.
    public static let levels: [[UInt8]] = mips(of: pixels, side: side)

    /// Of the grass, the clumps a tile holds across, two layers of them.
    static let clumps = (coarse: 6, fine: 13)
    /// Of the grit, the stones a tile holds across.
    static let stones = 16
    /// How far each channel swings about its mean.
    static let swing: Float = 0.18
    /// Of the salt's crust, the polygons' middles a tile holds across, and
    /// how far either side of an edge between two its rim reaches, in
    /// cells.
    static let crust = 4
    static let rimWidth: Float = 0.035

    static func make() -> [UInt8] {
        let n = side
        var red = [Float](repeating: 0, count: n * n)
        var green = [Float](repeating: 0, count: n * n)
        var blue = [Float](repeating: 0, count: n * n)
        var alpha = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let u = (Float(x) + 0.5) / Float(n), v = (Float(y) + 0.5) / Float(n)
                let i = y * n + x
                red[i] = 0.62 * clump(u, v, cells: clumps.coarse, seed: 11) + 0.38 * clump(u, v, cells: clumps.fine, seed: 23)
                green[i] = 0.8 * pebble(u, v, cells: stones, seed: 37) + 0.2 * value(u, v, lattice: 32, seed: 41)
                blue[i] = 0.5 * value(u, v, lattice: 4, seed: 53) + 0.3 * value(u, v, lattice: 8, seed: 59) + 0.2 * value(u, v, lattice: 16, seed: 61)
                alpha[i] = UInt8(min(max(rim(u, v, cells: crust, seed: 71), 0), 1) * 255 + 0.5)
            }
        }
        let r = levelled(red), g = levelled(green), b = levelled(blue)
        var out = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            out[i * 4] = r[i]
            out[i * 4 + 1] = g[i]
            out[i * 4 + 2] = b[i]
            out[i * 4 + 3] = alpha[i]
        }
        return out
    }

    /// A channel set about a half, swinging `swing` either way at one
    /// spread of its own.
    static func levelled(_ values: [Float]) -> [UInt8] {
        let count = Float(values.count)
        let mean = values.reduce(Float(0), +) / count
        let spread = (values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / count).squareRoot()
        return values.map { value in
            let level = 0.5 + (value - mean) / max(spread, 1e-6) * swing
            return UInt8(min(max(level, 0), 1) * 255 + 0.5)
        }
    }

    /// A number from 0 to 1 for a cell of a lattice wrapped every `period`
    /// cells, the same every time.
    static func hash(_ x: Int, _ y: Int, period: Int, seed: UInt32) -> Float {
        let wx = UInt32(truncatingIfNeeded: ((x % period) + period) % period)
        let wy = UInt32(truncatingIfNeeded: ((y % period) + period) % period)
        var h = wx &* 374_761_393 &+ wy &* 668_265_263 &+ seed &* 2_654_435_761
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    /// Smooth noise over a lattice of `lattice` cells across the tile,
    /// wrapping with it.
    static func value(_ u: Float, _ v: Float, lattice: Int, seed: UInt32) -> Float {
        let x = u * Float(lattice), y = v * Float(lattice)
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Float(x0), fy = y - Float(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(x0, y0, period: lattice, seed: seed), b = hash(x0 + 1, y0, period: lattice, seed: seed)
        let c = hash(x0, y0 + 1, period: lattice, seed: seed), d = hash(x0 + 1, y0 + 1, period: lattice, seed: seed)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    /// How near a point is to the middle of the nearest of the features
    /// scattered one to a cell over `cells` cells across, wrapping: 0 at a
    /// middle, near 1 between, in cells; and that feature's own number.
    static func nearest(_ u: Float, _ v: Float, cells: Int, seed: UInt32) -> (distance: Float, which: Float) {
        let x = u * Float(cells), y = v * Float(cells)
        let cx = Int(x.rounded(.down)), cy = Int(y.rounded(.down))
        var best: (distance: Float, which: Float) = (.infinity, 0)
        for dy in -1...1 {
            for dx in -1...1 {
                let gx = cx + dx, gy = cy + dy
                let px = Float(gx) + 0.05 + 0.9 * hash(gx, gy, period: cells, seed: seed)
                let py = Float(gy) + 0.05 + 0.9 * hash(gx, gy, period: cells, seed: seed &+ 7)
                let d = ((x - px) * (x - px) + (y - py) * (y - py)).squareRoot()
                if d < best.distance { best = (d, hash(gx, gy, period: cells, seed: seed &+ 13)) }
            }
        }
        return best
    }

    /// Clumps of grass: each bright and full at its middle, falling away to
    /// the dark gaps between, some taller and lighter than others.
    static func clump(_ u: Float, _ v: Float, cells: Int, seed: UInt32) -> Float {
        let (d, which) = nearest(u, v, cells: cells, seed: seed)
        let radius: Float = 0.42 + 0.2 * which
        let t = min(d / radius, 1)
        return (1 - t * t) * (0.7 + 0.3 * which)
    }

    /// Pebbles: each a small rounded stone, its own shade, the grit between.
    static func pebble(_ u: Float, _ v: Float, cells: Int, seed: UInt32) -> Float {
        let (d, which) = nearest(u, v, cells: cells, seed: seed)
        let stone: Float = 1 - min(max((d - 0.18) / 0.12, 0), 1)
        return stone * (0.55 + 0.45 * which)
    }

    /// How far a point lies from the nearest edge of the polygon it is in,
    /// the polygons each about the middle nearest them of those scattered
    /// one to a cell over `cells` cells across, wrapping; in cells. Measured
    /// to the line halfway between its own middle and each other's, so where
    /// two middles lie close together only the line between them is near.
    static func border(_ u: Float, _ v: Float, cells: Int, seed: UInt32) -> Float {
        let x = u * Float(cells), y = v * Float(cells)
        let cx = Int(x.rounded(.down)), cy = Int(y.rounded(.down))
        var middles: [SIMD2<Float>] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let gx = cx + dx, gy = cy + dy
                middles.append(SIMD2(Float(gx) + 0.05 + 0.9 * hash(gx, gy, period: cells, seed: seed),
                                     Float(gy) + 0.05 + 0.9 * hash(gx, gy, period: cells, seed: seed &+ 7)))
            }
        }
        let point = SIMD2(x, y)
        func squared(_ d: SIMD2<Float>) -> Float { d.x * d.x + d.y * d.y }
        let own = middles.min { squared($0 - point) < squared($1 - point) }!
        var nearest = Float.infinity
        for other in middles {
            let across = other - own
            let length = squared(across).squareRoot()
            guard length > 1e-6 else { continue }
            let halfway = (own + other) * 0.5 - point
            nearest = min(nearest, (halfway.x * across.x + halfway.y * across.y) / length)
        }
        return nearest
    }

    /// A salt pan's crust: full on its polygons' edges, falling away either
    /// side within `rimWidth`, nothing on their floors.
    static func rim(_ u: Float, _ v: Float, cells: Int, seed: UInt32) -> Float {
        let edge = border(u, v, cells: cells, seed: seed) / rimWidth
        return Float(exp(Double(-edge * edge)))
    }

    /// Each level half the side of the one before, each pixel the mean of
    /// the four it covers, to a single pixel.
    static func mips(of base: [UInt8], side: Int) -> [[UInt8]] {
        var levels = [base]
        var current = base, size = side
        while size > 1 {
            let half = size / 2
            var next = [UInt8](repeating: 0, count: half * half * 4)
            for y in 0..<half {
                for x in 0..<half {
                    for channel in 0..<4 {
                        let a = Int(current[((2 * y) * size + 2 * x) * 4 + channel])
                        let b = Int(current[((2 * y) * size + 2 * x + 1) * 4 + channel])
                        let c = Int(current[((2 * y + 1) * size + 2 * x) * 4 + channel])
                        let d = Int(current[((2 * y + 1) * size + 2 * x + 1) * 4 + channel])
                        next[(y * half + x) * 4 + channel] = UInt8((a + b + c + d + 2) / 4)
                    }
                }
            }
            levels.append(next)
            current = next
            size = half
        }
        return levels
    }
}
