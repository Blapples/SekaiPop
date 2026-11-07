import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sekai.readers

// The AniList account page of the manga panel: log in, see who is logged in, log out.
// The login itself is the backend's (Manga.alStartLogin: AniList opens in the browser and sends
// it back to a page of the backend, which keeps the token); this only shows where it stands.
//
//   AniListLogin { id: anilist; anchors.fill: parent }
//   anilist.open()
//
// First time: the AniList app's client ID is asked for once (anilist.co/settings/developer ->
// Create New Client, redirect URL = Manga.alRedirectUri; no secret is used). A token can also be
// pasted while a login is waiting, for when the redirect page can't be reached.
Item {
    id: root

    signal closed()
    // A cover on the profile page was tapped (a favourite, or Jump back in): the parent opens it
    signal mangaSelected(string mangaId)

    // Changing the client ID of an app that was already set up
    property bool editClient: false

    visible: false

    function open() {
        Manga.alError = ""
        root.editClient = false
        visible = true
        Manga.alRefresh()
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
                width: Math.min(flick.width - 48, Manga.alLoggedIn ? 600 : 460)
                x: (flick.width - width) / 2
                y: 24
                spacing: 14

                // ── Logged in: the profile (banner, numbers, Jump back in, favourites, account) ──
                ProfilePage {
                    Layout.fillWidth: true
                    visible: Manga.alLoggedIn

                    onMangaSelected: function(mangaId) { root.mangaSelected(mangaId) }
                }

                // ── Not logged in ─────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !Manga.alLoggedIn
                    spacing: 14

                    StyledText {
                        Layout.fillWidth: true
                        visible: Manga.alExpired
                        text: "Your AniList login has run out. Log in again."
                        color: Colors.error
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Log in with AniList to keep track of what you are reading."
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }

                    // First time (or changing it): the AniList app this shell logs in as
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !Manga.alWaiting && (!Manga.alHasClientId || root.editClient)
                        spacing: 10

                        StyledText {
                            Layout.fillWidth: true
                            text: "One-time setup. AniList wants an app to log in as, and making one takes a minute:"
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
                        visible: !Manga.alWaiting && Manga.alHasClientId && !root.editClient
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
                    visible: !Manga.alLoggedIn
                    text: "The login is kept in ~/.local/share/sekaipop/readers/manga/anilist_auth.json, readable only by you."
                    color: Colors.on_surface_variant
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    opacity: 0.7
                }
            }
        }
    }
}
