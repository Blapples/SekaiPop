import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The password block of the Custom lockscreen, the one thing on it that is never optional:
// the white "Password" pill (the typed dots in its dark well, the keyboard layout tag, the
// fingerprint prompt) and the mint "Unlock" pill, the same pills as the Gacha look's, and the
// pink callout that says why a try failed.
//
// It is the canvas's only way to unlock. LockCanvas.qml always builds it, on top of every
// widget, and LockCanvasModel.js keeps it on the screen (it can be moved a little, never
// hidden or scaled). Pure UI over the shared LockContext: what is typed, whether PAM is
// thinking and why a try failed all live there, and the keys are caught by the canvas.
//
//   LockCore { context: root.context; overlay: root; u: root.u; onRefocus: root.forceActiveFocus() }
Item {
    id: root

    // The shared LockContext.
    required property var context
    // The look's root item: the layout tag's list opens in it (a lock surface can not host
    // a popup window).
    required property Item overlay
    // The screen's scale, as in the other looks (1 at 1080 p tall).
    property real u: 1

    function px(n) {
        return Math.round(n * root.u)
    }

    // The tag or the Unlock pill was clicked: the keyboard goes back to the look.
    signal refocus()

    readonly property int maxDots: 16
    readonly property bool failed: root.context.failureText !== ""
    // Kept after the failure clears so the callout can fade out with its words still in it.
    property string lastFailure: ""

    readonly property int pillH: root.px(122)
    readonly property int pwW: root.px(560)
    readonly property int unW: root.px(330)
    readonly property int gap: root.px(26)

    implicitWidth: root.pwW + root.gap + root.unW
    implicitHeight: root.pillH
    width: root.implicitWidth
    height: root.implicitHeight

    Connections {
        target: root.context

        function onFailureCountChanged() {
            shakeAnim.restart()
        }
        function onFailureTextChanged() {
            if (root.context.failureText !== "")
                root.lastFailure = root.context.failureText
        }
    }

    // The white "Password" pill (shakes when a try fails).
    Item {
        id: pwGroup
        width: root.pwW
        height: root.pillH
        transform: Translate { id: shake; x: 0 }

        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shake; property: "x"; to: -root.px(16); duration: 55 }
            NumberAnimation { target: shake; property: "x"; to: root.px(14); duration: 70 }
            NumberAnimation { target: shake; property: "x"; to: -root.px(9); duration: 70 }
            NumberAnimation { target: shake; property: "x"; to: root.px(5); duration: 60 }
            NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
        }

        Rectangle {
            y: root.px(6)
            width: parent.width
            height: parent.height
            radius: height * 0.42
            color: LockPalette.shadow
        }

        Rectangle {
            anchors.fill: parent
            radius: height * 0.42
            color: LockPalette.paper
            border.width: root.failed ? root.px(4) : 0
            border.color: LockPalette.pink

            Behavior on border.width {
                NumberAnimation { duration: 120 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Leaves the same room on both sides for the layout tag, so the
                // text stays centred.
                width: parent.width - 2 * (layoutTag.visible ? layoutTag.width + root.px(28) : root.px(24))
                y: root.px(12)
                height: Math.max(0, well.y - y - root.px(6))
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: root.context.fprintListening ? root.context.fprintMessage
                      : (root.context.unlockInProgress ? "Checking…" : "Password")
                color: root.context.fprintMessageIsError ? LockPalette.pink : LockPalette.cBorder
                font.family: Theme.fontFamily
                font.pixelSize: root.px(34)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: root.px(22)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            // The keyboard layout, a tag on the corner like the Unlock pill's "Enter".
            LockLayoutTag {
                id: layoutTag
                overlay: root.overlay
                panelColor: LockPalette.paper
                inkColor: LockPalette.cBorder
                accentColor: LockPalette.mint
                shadowColor: LockPalette.shadow
                shadowDy: root.px(6)
                panelRadius: root.px(26)
                x: parent.width - width - root.px(14)
                y: root.px(8)
                fillColor: LockPalette.mint
                textColor: LockPalette.cBorder
                fontPixelSize: root.px(18)
                tagHeight: root.px(30)
                sidePadding: root.px(26)
                onActivated: root.refocus()
            }

            // The dark well: the typed dots sit in here.
            Rectangle {
                id: well
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.px(14)
                width: parent.width - root.px(64)
                height: root.px(48)
                radius: height / 2
                color: LockPalette.well

                // Ctrl+A: the selection behind the dots.
                Rectangle {
                    anchors.centerIn: dots
                    width: dots.width + root.px(24)
                    height: root.px(34)
                    radius: height / 2
                    color: Qt.rgba(0.30, 0.82, 1, 0.45)
                    border.width: root.px(2)
                    border.color: Qt.rgba(1, 1, 1, 0.8)
                    visible: root.context.allSelected && dots.shown > 0
                }

                Row {
                    id: dots
                    anchors.centerIn: parent
                    spacing: root.px(9)
                    opacity: root.context.unlockInProgress ? 0.45 : 1

                    readonly property int shown: Math.min(root.context.currentText.length, root.maxDots)

                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    Repeater {
                        model: dots.shown

                        delegate: Rectangle {
                            required property int index

                            width: root.px(22)
                            height: width
                            radius: width / 2
                            antialiasing: true
                            // Colour follows the character's place in the
                            // password, so it doesn't flicker as the row
                            // stops growing past maxDots.
                            color: Theme.attributeColors[(root.context.currentText.length - dots.shown + index) % Theme.attributeColors.length]

                            // Pops in when typed.
                            NumberAnimation on scale {
                                from: 0.3
                                to: 1
                                duration: 150
                                easing.type: Easing.OutBack
                                easing.overshoot: 2.5
                            }
                        }
                    }
                }
            }
        }

        // The pink callout: why the last try failed.
        Item {
            id: bubble
            x: root.px(34)
            y: -height - root.px(18)
            width: Math.min(bubbleText.implicitWidth + root.px(52), root.px(640))
            height: root.px(58)
            opacity: root.failed ? 1 : 0
            scale: root.failed ? 1 : 0.85
            transformOrigin: Item.BottomLeft

            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }
            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.px(14)
                color: LockPalette.pink
            }

            // The little tail, pointing down at the pill.
            Rectangle {
                x: root.px(40)
                y: parent.height - root.px(13)
                width: root.px(24)
                height: width
                rotation: 45
                color: LockPalette.pink
            }

            Text {
                id: bubbleText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, bubble.width - root.px(52))
                elide: Text.ElideRight
                text: root.lastFailure
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(26)
                font.weight: Font.Bold
                font.styleName: Theme.fontStyleBold
            }
        }
    }

    // The mint "Unlock" pill.
    Item {
        id: unlockPill
        x: root.pwW + root.gap
        width: root.unW
        height: root.pillH
        scale: unlockArea.pressed ? 0.97 : 1

        Behavior on scale {
            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
        }

        Rectangle {
            y: root.px(6)
            width: parent.width
            height: parent.height
            radius: height * 0.42
            color: LockPalette.shadow
        }

        Rectangle {
            anchors.fill: parent
            radius: height * 0.42
            color: LockPalette.mint

            Text {
                id: unlockLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.px(30)
                y: root.px(12)
                text: "Unlock"
                color: LockPalette.cBorder
                font.family: Theme.fontFamily
                font.pixelSize: root.px(34)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.px(14)
                width: parent.width - root.px(64)
                height: root.px(48)
                radius: height / 2
                color: LockPalette.well

                Row {
                    anchors.centerIn: parent
                    visible: !root.context.unlockInProgress
                    spacing: root.px(10)

                    // Shown alongside the arrow after PAM reports a fingerprint prompt.
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.context.fprintListening
                        name: "fingerprint"
                        size: root.px(26)
                        weight: 600
                        color: root.failed ? LockPalette.pink : LockPalette.mint

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow_forward"
                        size: root.px(28)
                        weight: 600
                        color: LockPalette.mint
                    }
                }

                MaterialIcon {
                    id: spinner
                    anchors.centerIn: parent
                    visible: root.context.unlockInProgress
                    name: "progress_activity"
                    size: root.px(28)
                    weight: 600
                    color: LockPalette.mint

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: spinner.visible
                    }
                }
            }
        }

        // Align the shortcut text to Unlock's baseline, with an optical adjustment.
        Rectangle {
            x: root.px(32)
            y: unlockLabel.parent.y + unlockLabel.y + unlockLabel.baselineOffset
               - hint.y - hint.baselineOffset - root.px(8)
            width: hint.implicitWidth + root.px(26)
            height: root.px(30)
            radius: height / 2
            color: LockPalette.pink

            Text {
                id: hint
                anchors.centerIn: parent
                text: "Enter"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: root.px(18)
                font.weight: Font.ExtraBold
                font.styleName: Theme.fontStyleBold
            }
        }

        MouseArea {
            id: unlockArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.refocus()
                root.context.tryUnlock()
            }
        }
    }
}
