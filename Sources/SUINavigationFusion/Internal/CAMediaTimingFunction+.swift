import QuartzCore

extension CAMediaTimingFunction {
    /// Returns the y-value of this timing function evaluated at `t` in [0…1].
    ///
    /// Internally, UIKit's named curves are usually cubic Béziers where the x-axis
    /// represents time and the y-axis represents the easing value. We do a simple
    /// binary search on the x-coordinates of the curve until we find the point that
    /// corresponds to `t`, then return its y.
    func value(at t: CGFloat) -> CGFloat {
        let x = Float(t)
        // Solve for the param in the cubic Bézier that yields x:
        let param = solve(forX: x)
        // Once we have that param, get the actual (x,y) point on the curve:
        let point = point(for: param)
        return CGFloat(point.y)
    }
    
    /// Performs a binary search to find the param `u` in [0…1] where the curve's x ≈ `xTarget`.
    private func solve(forX xTarget: Float, epsilon: Float = 1e-5) -> Float {
        var lower: Float = 0
        var upper: Float = 1
        var mid:   Float = 0
        
        while lower < upper {
            mid = (lower + upper) * 0.5
            let xVal = point(for: mid).x
            if abs(xVal - xTarget) < epsilon {
                return mid
            }
            if xVal < xTarget {
                lower = mid
            } else {
                upper = mid
            }
        }
        return mid
    }
    
    /// Returns the (x,y) point on the curve for param `u` in [0…1].
    private func point(for u: Float) -> (x: Float, y: Float) {
        // Retrieve the 4 control points: p0, p1, p2, p3
        // Typically p0 = (0,0), p3 = (1,1), p1/p2 are the named curve's control points.
        var c0 = [Float](repeating: 0, count: 2)
        var c1 = [Float](repeating: 0, count: 2)
        var c2 = [Float](repeating: 0, count: 2)
        var c3 = [Float](repeating: 0, count: 2)
        
        getControlPoint(at: 0, values: &c0)
        getControlPoint(at: 1, values: &c1)
        getControlPoint(at: 2, values: &c2)
        getControlPoint(at: 3, values: &c3)
        
        let x = cubicBezier(u, c0[0], c1[0], c2[0], c3[0])
        let y = cubicBezier(u, c0[1], c1[1], c2[1], c3[1])
        return (x, y)
    }
    
    /// A standard cubic Bézier: B(u) = (1−u)³ p0 + 3(1−u)² u p1 + 3(1−u) u² p2 + u³ p3
    private func cubicBezier(
        _ u: Float,
        _ p0: Float,
        _ p1: Float,
        _ p2: Float,
        _ p3: Float
    ) -> Float {
        let oneMinusU = 1 - u
        return  oneMinusU * oneMinusU * oneMinusU * p0
        + 3 * oneMinusU * oneMinusU * u      * p1
        + 3 * oneMinusU * u * u              * p2
        + u * u * u                          * p3
    }
}
