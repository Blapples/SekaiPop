import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The novel panel's AniList page: who is logged in, the "update as I read" switch, log in / out.
// What it tracks is novels only (see Novel.qml, novel_server/anilist.py).
//
// The login is shared with the manga reader: one AniList login serves both, and the manga
// backend is what runs it (AniList sends the browser back to a page of that backend, which keeps
// the token; the novel backend reads the same file). So the login part below borrows Manga's
// functions. It sits in a Loader on purpose: the manga backend is only started (a second Python
// process) when the page is opened to log in or out, never while you just read.
//
//   AniListSheet { id: sheet; anchors.fill: parent }
//   sheet.open()
Item {
    id: root

    signal closed()

    // Changing the client ID of an app that was already set up
    property bool editClient: false
    property bool loggingOut: false

    visible: false

    function open() {
        root.editClient = false
        root.loggingOut = false
        visible = true
        Novel.alRefresh()
    }

    function close() {
        visible = false
        root.closed()
    }

    // Swallows the clicks that would reach the page underneath
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 16 }
                spacing: 10

                ReaderKey {
                    icon: "close"
                    onClicked: root.close()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "AniList"
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    font.styleName: Theme.fontStyleBold
                    elide: Text.ElideRight
                }
            }
        }

        Divider { Layout.fillWidth: true }

        // ── Body ──────────────────────────────────────────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: page.implicitHeight + 40

            ScrollBar.vertical: StyledScrollBar {
            }

            ColumnLayout {
                id: page
                width: Math.min(flick.width - 48, 460)
                x: (flick.width - width) / 2
                y: 24
                spacing: 14

                // ── Logged in ─────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Novel.alLoggedIn
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        RoundClip {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radii: [20, 20, 20, 20]

                            Rectangle { anchors.fill: parent; color: Colors.surface_container_high }

                            Image {
                                anchors.fill: parent
                                source: Novel.alViewer && Novel.alViewer.avatar ? Novel.alViewer.avatar : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 104
                                sourceSize.height: 104
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                width: parent.width
                                text: Novel.alViewer && Novel.alViewer.name ? Novel.alViewer.name : "Logged in"
                                font.pixelSize: 16
                                font.weight: Font.ExtraBold
                                font.styleName: Theme.fontStyleBold
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: "Logged in to AniList"
                                color: Colors.on_surface_variant
                                font.pixelSize: 11
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Novels you read here are put on your AniList list: a novel is matched to its AniList entry by name (you can change the match on the novel's page), and finishing a chapter raises the number of chapters read, never lowers it. Only novels are tracked; manga stay with the manga reader."
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 10

                        // What is read goes on the list by itself
                        ReaderChip {
                            icon: Novel.trackAuto ? "check_read" : "eye_closed"
                            text: "Update as I read: " + (Novel.trackAuto ? "On" : "Off")
                            lit: Novel.trackAuto
                            onClicked: Novel.setTrackAuto(!Novel.trackAuto)
                        }

                        // A novel already begun on AniList opens with those chapters marked read
                        ReaderChip {
                            icon: Novel.trackAdopt ? "check_read" : "eye_closed"
                            text: "Mark read from AniList: " + (Novel.trackAdopt ? "On" : "Off")
                            lit: Novel.trackAdopt
                            onClicked: Novel.setTrackAdopt(!Novel.trackAdopt)
                        }

                        ReaderChip {
                            icon: "link"
                            text: "Open profile"
                            visible: Novel.alViewer !== null && (Novel.alViewer.siteUrl || "").length > 0
                            onClicked: Qt.openUrlExternally(Novel.alViewer.siteUrl)
                        }

                        ReaderChip {
                            icon: "logout"
                            text: root.loggingOut ? "Logging out\u2026" : "Log out"
                            enabled: !root.loggingOut
                            onClicked: root.loggingOut = true
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Logging out here logs the manga reader out too: it is one login."
                        color: Colors.on_surface_variant
                        font.pixelSize: 10
                        opacity: 0.7
                        wrapMode: Text.Wrap
                    }
                }

                // ── Not logged in: the manga backend's login flow ─────────────
                Loader {
                    Layout.fillWidth: true
                    active: !Novel.alLoggedIn
                    visible: active
                    sourceComponent: loginFlow
                }

                // ── Logging out (starts the manga backend if it is not running) ──
                Loader {
                    active: root.loggingOut
                    sourceComponent: logoutRunner
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Novel.trackError.length > 0 && Novel.alLoggedIn
                    text: Novel.trackError
                    color: Colors.error
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Component {
        id: logoutRunner

        Item {
            width: 0; height: 0

            Connections {
                target: Manga
                function onAlLoggedInChanged() { Novel.alRefresh() }
            }

            // The manga backend takes a moment to start; log out as soon as it answers
            Timer {
                interval: 300
                repeat: true
                running: true
                onTriggered: {
                    if (!Manga.serverReady) return
                    stop()
                    Manga.alLogout()
                    done.start()
                }
            }

            Timer {
                id: done
                interval: 1200
                onTriggered: { Novel.alRefresh(); root.loggingOut = false }
            }
        }
    }

    Component {
        id: loginFlow

        ColumnLayout {
            id: flow
            spacing: 14

            // The login finished in the manga backend: the novel backend reads the same file
            Connections {
                target: Manga
                function onAlLoggedInChanged() { Novel.alRefresh() }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Novel.alExpired
                text: "Your AniList login has run out. Log in again."
                color: Colors.error
                font.pixelSize: 12
                font.weight: Font.Bold
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                text: "Log in with AniList to keep track of the novels you read. It is the same login as the manga reader's: log in once and both use it."
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            // The manga backend is the one that runs the login: wait for it to come up
            RowLayout {
                visible: !Manga.serverReady
                spacing: 12

                Spinner {
                    width: 22
                    running: !Manga.serverReady
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Starting the login helper\u2026"
                    color: Colors.on_surface_variant
                    font.pixelSize: 12
                }
            }

            // First time (or changing it): the AniList app this shell logs in as
            ColumnLayout {
                Layout.fillWidth: true
                visible: Manga.serverReady && !Manga.alWaiting && (!Manga.alHasClientId || root.editClient)
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    text: "One-time setup. AniList wants an app to log in as, and making one takes a minute (if the manga reader is already logged in, you have done this):"
                    color: Colors.on_surface_variant
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "1. Open AniList's developer settings and press Create New Client."
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                ReaderChip {
                    icon: "link"
                    text: "Open developer settings"
                    onClicked: Qt.openUrlExternally("https://anilist.co/settings/developer")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "2. Give it any name, and as the Redirect URL put exactly this (select it to copy):"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                ReaderField {
                    Layout.fillWidth: true
                    readOnly: true
                    text: Manga.alRedirectUri
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "3. Save it, then paste its Client ID (a number) here:"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                ReaderField {
                    id: clientField
                    Layout.fillWidth: true
                    placeholder: "Client ID"
                    onAccepted: if (text.trim().length > 0) Manga.alSetClientId(text.trim(), true)
                }

                ReaderChip {
                    lit: true
                    text: "Save and log in"
                    enabled: !Manga.alBusy && clientField.text.trim().length > 0
                    onClicked: Manga.alSetClientId(clientField.text.trim(), true)
                }
            }

            // Set up: just log in
            RowLayout {
                visible: Manga.serverReady && !Manga.alWaiting && Manga.alHasClientId && !root.editClient
                spacing: 10

                ReaderChip {
                    lit: true
                    icon: "login"
                    text: "Log in with AniList"
                    enabled: !Manga.alBusy
                    onClicked: Manga.alStartLogin()
                }

                ReaderChip {
                    text: "Change client ID"
                    onClicked: root.editClient = true
                }
            }

            // The browser is open: waiting for AniList to send it back
            ColumnLayout {
                Layout.fillWidth: true
                visible: Manga.alWaiting
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Spinner {
                        width: 22
                        running: Manga.alWaiting
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Waiting for AniList. Approve SekaiPop in your browser, then come back here."
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }

                RowLayout {
                    spacing: 10

                    ReaderChip {
                        text: "Open again"
                        enabled: !Manga.alBusy
                        onClicked: Manga.alStartLogin()
                    }

                    ReaderChip {
                        text: "Cancel"
                        onClicked: Manga.alCancelLogin()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Can't use the redirect page? Set the app's Redirect URL to https://anilist.co/api/v2/oauth/pin, log in, and paste the token it shows:"
                    color: Colors.on_surface_variant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                ReaderField {
                    id: tokenField
                    Layout.fillWidth: true
                    secret: true
                    placeholder: "Paste a token"
                    onAccepted: if (text.trim().length > 0) Manga.alSubmitToken(text.trim())
                }

                ReaderChip {
                    text: "Use token"
                    enabled: !Manga.alBusy && tokenField.text.trim().length > 0
                    onClicked: Manga.alSubmitToken(tokenField.text.trim())
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Manga.alError.length > 0
                text: Manga.alError
                color: Colors.error
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                text: "The login is kept in ~/.local/share/sekaipop/readers/manga/anilist_auth.json, readable only by you."
                color: Colors.on_surface_variant
                font.pixelSize: 10
                opacity: 0.7
                wrapMode: Text.Wrap
            }
        }
    }
}
