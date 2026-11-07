import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/SensorsMath.js" as SM

// The card that drops down from ResourceIndicator.qml, redesigned to sit with
// the other bar popups (Battery, Weather, Calendar): the shared SekaiPopup
// frame, two SekaiPlates with sticker numerals, and the load drawn as the same
// ten slanted segments the battery uses. Bar.qml feeds it the four numbers
// from ResourceSource.qml, as before; the frame, focus grab, pop-in and
// swallow come from SekaiPopup.qml.
//
//   The plates    CPU and RAM side by side, each a big sticker number. A plate
//                 wears the colour of the load: the accent gradient while it is
//                 calm, then yellow, pink and red-pink as it climbs. Poke one
//                 for a puff of diamonds.
//   The gauges    one block per figure: a section tab, a judgement stamp (CHILL
//                 / STEADY / BUSY / HEAVY / MAXED) and ten slanted segments
//                 that fill in one after another when the card opens. A load
//                 of 90 or more shakes its gauge once, the same line the bar's
//                 own glyph turns red at.
//   The keys      the memory in use, "6.1 of 16.0 GB", on two keycaps like the
//                 battery's time.
//   The sensors   under those, when this machine has them: the CPU and GPU temperatures and the
//                 disks' fill, one thin bar each (StatBar.qml), from SensorsService.qml. A row
//                 the machine can't read is simply not there.
SekaiPopup {
    id: root

    property real cpuPercent: 0
    property real memPercent: 0
    property string memUsedLabel: "--"
    property string memTotalLabel: "--"

    readonly property int pad: 16
    readonly property int innerW: 304
    readonly property real halfW: (root.innerW - 10) / 2

    contentWidth: root.innerW + 2 * root.pad
    contentHeight: stack.implicitHeight + 2 * root.pad - 2

    // ===== the judgement for a load =====
    // 0 CHILL  1 STEADY  2 BUSY  3 HEAVY  4 MAXED. 90 matches the point where
    // the bar's CPU / RAM glyph turns red (ResourceIndicator cpuHot / memHot).
    function tierOf(p) {
        if (p >= 90) return 4
        if (p >= 75) return 3
        if (p >= 50) return 2
        if (p >= 20) return 1
        return 0
    }

    readonly property var words: ["CHILL", "STEADY", "BUSY", "HEAVY", "MAXED"]
    // The calm tiers (0, 1) keep the accent gradient; the rest take a colour.
    readonly property var tierFill: [mt.accentMint, mt.accentMint, "#FFE066", "#FF9ECB", "#e0575b"]

    readonly property int cpuTier: root.tierOf(root.cpuPercent)
    readonly property int memTier: root.tierOf(root.memPercent)
    readonly property bool cpuHot: root.cpuTier === 4
    readonly property bool memHot: root.memTier === 4

    // The CPU glyph steps like the bar's (ResourceIndicator.cpuGlyphName).
    readonly property string cpuGlyph: {
        var p = root.cpuPercent
        if (p < 15) return "clock_loader_10"
        if (p < 30) return "clock_loader_20"
        if (p < 50) return "clock_loader_40"
        if (p < 70) return "clock_loader_60"
        if (p < 85) return "clock_loader_80"
        return "clock_loader_90"
    }

    function plateTop(tier) {
        return tier <= 1 ? mt.accentMint : Qt.lighter(root.tierFill[tier], 1.16)
    }

    function plateBottom(tier) {
        return tier <= 1 ? mt.accentCyan : root.tierFill[tier]
    }

    // The ink on a plate: dark, except on the red MAXED plate.
    function plateInkFor(tier) {
        return tier === 4 ? mt.textWhite : mt.colBorder
    }

    // ===== the open choreography =====
    property real fillWave: 1
    property real shakeX: 0

    NumberAnimation {
        id: fillAnim
        target: root
        property: "fillWave"
        from: 0
        to: 1
        duration: 650
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 6; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: -4; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 3; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60 }
    }

    onOpenChanged: {
        // Pressed again while the card was still going away: it turns round
        // instead of replaying the fill-in.
        if (open && root.reveal < 0.35) {
            fillAnim.restart()
            if (root.cpuHot || root.memHot)
                shakeAnim.restart()
        }
    }

    Column {
        id: stack
        x: root.pad
        y: root.pad - 2
        width: root.innerW
        spacing: 10

        // ===== the plates =====
        Row {
            width: root.innerW
            spacing: 10

            LoadPlate {
                width: root.halfW
                label: "CPU"
                glyph: root.cpuGlyph
                pct: root.cpuPercent
                colorTop: root.plateTop(root.cpuTier)
                colorBottom: root.plateBottom(root.cpuTier)
                ink: root.plateInkFor(root.cpuTier)
            }

            LoadPlate {
                width: root.halfW
                label: "RAM"
                glyph: "memory"
                pct: root.memPercent
                colorTop: root.plateTop(root.memTier)
                colorBottom: root.plateBottom(root.memTier)
                ink: root.plateInkFor(root.memTier)
            }
        }

        // ===== the gauges =====
        LoadGauge {
            width: root.innerW
            title: "Processor"
            pct: root.cpuPercent
            word: root.words[root.cpuTier]
            tint: root.tierFill[root.cpuTier]
            plain: root.cpuTier >= 2
            hot: root.cpuHot
            wave: root.fillWave
            shake: root.cpuHot ? root.shakeX : 0
        }

        LoadGauge {
            width: root.innerW
            title: "Memory"
            pct: root.memPercent
            word: root.words[root.memTier]
            tint: root.tierFill[root.memTier]
            plain: root.memTier >= 2
            hot: root.memHot
            wave: root.fillWave
            shake: root.memHot ? root.shakeX : 0
        }

        // ===== the memory in use, on two keycaps =====
        Item {
            id: readout
            width: root.innerW
            height: 50

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Pill {
                    width: Math.max(52, usedText.implicitWidth + 26)
                    height: 46
                    shadowDy: 4
                    cornerRadius: 14
                    ringWidth: 4
                    fillGradient: Gradient {
                        GradientStop { position: 0.0; color: mt.accentMint }
                        GradientStop { position: 1.0; color: mt.accentCyan }
                    }

                    Text {
                        id: usedText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        text: root.memUsedLabel
                        color: mt.colBorder
                        font.family: mt.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -2
                    text: "of"
                    color: mt.inkSub
                    font.family: mt.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                    font.styleName: mt.fontStyleBold
                }

                Pill {
                    width: Math.max(52, totalText.implicitWidth + 26)
                    height: 46
                    shadowDy: 4
                    cornerRadius: 14
                    ringWidth: 4
                    fillColor: mt.chipFill

                    Text {
                        id: totalText
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        text: root.memTotalLabel
                        color: mt.chipInk
                        font.family: mt.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -2
                    leftPadding: 6
                    spacing: 1

                    Text {
                        text: "GB in use"
                        color: mt.ink
                        font.family: mt.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.ExtraBold
                        font.styleName: mt.fontStyleBold
                    }
                    Text {
                        text: "right now"
                        color: mt.inkSub
                        font.family: mt.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ===== the sensors =====
        SectionTab {
            visible: SensorsService.cpuTemp !== null || SensorsService.gpuTemp !== null
            text: "Temperatures"
        }

        StatBar {
            visible: SensorsService.cpuTemp !== null
            width: root.innerW
            label: "CPU"
            valueText: SM.tempText(SensorsService.cpuTemp) + " · " + SM.tempWord(SensorsService.cpuTemp)
            frac: SM.tempFrac(SensorsService.cpuTemp)
            hot: SM.tempHot(SensorsService.cpuTemp)
            wave: root.fillWave
        }

        StatBar {
            visible: SensorsService.gpuTemp !== null
            width: root.innerW
            label: "GPU"
            valueText: SM.tempText(SensorsService.gpuTemp) + " · " + SM.tempWord(SensorsService.gpuTemp)
            frac: SM.tempFrac(SensorsService.gpuTemp)
            hot: SM.tempHot(SensorsService.gpuTemp)
            wave: root.fillWave
        }

        SectionTab {
            visible: SensorsService.disks.length > 0
            text: "Disks"
        }

        Repeater {
            model: SensorsService.disks

            StatBar {
                required property var modelData
                width: root.innerW
                label: modelData.name
                valueText: SM.diskText(modelData)
                frac: SM.diskFrac(modelData)
                hot: SM.diskFull(modelData)
                wave: root.fillWave
            }
        }
    }
}
