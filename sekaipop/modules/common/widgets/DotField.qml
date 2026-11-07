import QtQuick

// A halftone: rows of dots that shrink away from one corner, the printed
// look that Project SEKAI's menus put behind their panels. Drawn once (and
// again if its size or colour changes), so it costs nothing while animating.
//
//   DotField { width: 300; height: 160; corner: "tr"; dotColor: "#dddddd" }
Canvas {
    id: cv

    property color dotColor: "#cccccc"
    property real spacing: 20
    property real maxRadius: 3.4
    // Where the dots are biggest: "tl", "tr", "bl" or "br".
    property string corner: "tr"
    // How much of the diagonal the dots take to fade out (1 = all of it).
    property real reach: 1.0
    // False while the size is being animated: the field is not painted again for every width it
    // passes through (a paint is a script loop and a texture upload), only once when it is true
    // again. The caller hides it meanwhile (a Canvas that changes size is cleared).
    property bool live: true

    onDotColorChanged: requestPaint()
    onSpacingChanged: requestPaint()
    onMaxRadiusChanged: requestPaint()
    onCornerChanged: requestPaint()
    onReachChanged: requestPaint()
    onWidthChanged: if (live) requestPaint()
    onHeightChanged: if (live) requestPaint()
    onLiveChanged: if (live) requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (width < 2 || height < 2)
            return
        ctx.fillStyle = cv.dotColor

        const cx = corner.indexOf("r") >= 0 ? width : 0
        const cy = corner.indexOf("b") >= 0 ? height : 0
        const diag = Math.sqrt(width * width + height * height) * reach

        let row = 0
        for (let y = spacing / 2; y < height; y += spacing * 0.866) {
            const off = (row % 2) * spacing / 2
            row++
            for (let x = spacing / 2 + off; x < width; x += spacing) {
                const t = 1 - Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / diag
                if (t <= 0)
                    continue
                const r = maxRadius * t
                if (r < 0.6)
                    continue
                ctx.beginPath()
                ctx.arc(x, y, r, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }
}
