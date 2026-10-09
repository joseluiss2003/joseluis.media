import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// MPRIS now-playing bar widget.
//   left click  -> open/close the panel
//   right click -> play/pause
//   middle      -> next track
//   scroll      -> volume up/down
// In the bar it paints a cava spectrum with the cover art as a small circle on
// top; the panel shows cover art, title/artist, media controls and a live seek
// bar.
BarWidget {
  id: root
  moduleName: "joseluis.media"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink

  property string preferredKey: ""
  property bool popupOpen: false
  property real positionValue: 0
  property bool userSeeking: false

  readonly property int visualizerBars: 14
  property var levels: []
  property int cavaFailures: 0
  property bool cavaOk: true

  readonly property string cavaConfigPath: String(Qt.resolvedUrl("cava.conf")).replace("file://", "")
  readonly property real coverSize: Math.max(12, Math.round(root.barSize * 0.62))

  function isProxy(player) {
    var dbus = String(player && player.dbusName || "").toLowerCase()
    var entry = String(player && player.desktopEntry || "").toLowerCase()
    return dbus.indexOf("playerctld") !== -1 || entry === "playerctld"
  }

  function hasMetadata(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
  }

  function playerKey(player) {
    return player ? String(player.dbusName || player.desktopEntry || player.identity || "") : ""
  }

  readonly property var activePlayer: {
    var preferred = null
    var playing = null
    var playingProxy = null
    var track = null
    var trackProxy = null
    var identity = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      var proxy = isProxy(p)
      if (preferredKey && playerKey(p) === preferredKey && hasMetadata(p)) preferred = p
      if (p.isPlaying) {
        if (!proxy && !playing) playing = p
        else if (proxy && !playingProxy) playingProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !track) track = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (!proxy && !identity) {
        identity = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    return playing || playingProxy || preferred || track || trackProxy || identity || null
  }

  readonly property bool hasMedia: activePlayer !== null
    && !!(activePlayer.trackTitle || activePlayer.trackArtist || activePlayer.identity)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? (activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
  readonly property bool playing: activePlayer ? !!activePlayer.isPlaying : false

  readonly property real trackLength: activePlayer && activePlayer.lengthSupported
    ? Math.max(0, activePlayer.length) : 0

  function action(name) {
    var p = activePlayer
    if (!p) return
    if (name === "next" && p.canGoNext) p.next()
    else if (name === "previous" && p.canGoPrevious) p.previous()
    if (playerKey(p) !== "") preferredKey = playerKey(p)
  }

  function togglePlayPause() {
    var p = activePlayer
    if (!p) return
    if (p.isPlaying && p.canPause) p.pause()
    else if (!p.isPlaying && p.canPlay) p.play()
    else if (p.canTogglePlaying) p.togglePlaying()
    if (playerKey(p) !== "") preferredKey = playerKey(p)
  }

  function changeVolume(delta) {
    var p = activePlayer
    if (p && p.canControl && p.volumeSupported) {
      p.volume = Math.max(0, Math.min(1, p.volume + delta))
    } else if (defaultSink && defaultSink.audio) {
      defaultSink.audio.volume = Math.max(0, Math.min(1, defaultSink.audio.volume + delta))
    }
  }

  function seekTo(position) {
    var p = activePlayer
    if (!p) return
    var clamped = Math.max(0, Math.min(trackLength, position))
    if (p.canSeek && p.positionSupported) p.position = clamped
    else if (p.canSeek) p.seek(clamped - p.position)
    positionValue = clamped
  }

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    function pad(n) { return n < 10 ? "0" + n : "" + n }
    return hours > 0
      ? hours + ":" + pad(minutes) + ":" + pad(secs)
      : minutes + ":" + pad(secs)
  }

  function ingestLevels(line) {
    if (!line) return
    var parts = String(line).split(";")
    var out = []
    for (var i = 0; i < root.visualizerBars && i < parts.length; i++) {
      var v = parseInt(parts[i], 10)
      out.push(isNaN(v) ? 0 : Math.max(0, Math.min(1, v / 100)))
    }
    if (out.length > 0) root.levels = out
  }

  // ---- Popup contract so shell.summon/hide/toggle routing can drive it.
  readonly property bool opened: popupOpen

  function open() { if (root.hasMedia) popupOpen = true }
  function close() { popupOpen = false }

  function togglePanel() {
    if (root.hasMedia) popupOpen = !popupOpen
    else popupOpen = false
  }

  onHasMediaChanged: if (!hasMedia) popupOpen = false
  onActivePlayerChanged: positionValue = activePlayer ? activePlayer.position : 0
  onPlayingChanged: {
    if (root.playing) {
      root.cavaFailures = 0
      root.cavaOk = true
    } else {
      cavaProc.running = false
      root.levels = []
    }
  }

  // Keep the same side padding as the icon widgets so the bar's gaps stay
  // uniform (the visual otherwise bleeds to both slot edges).
  readonly property real sidePadding: Style.space(8)
  readonly property real contentLong: Math.round(barSize * 2.4)
  visible: hasMedia
  implicitWidth: hasMedia ? (root.vertical ? barSize : contentLong + sidePadding * 2) : 0
  implicitHeight: hasMedia ? (root.vertical ? contentLong + sidePadding * 2 : barSize) : 0

  PwObjectTracker { objects: root.defaultSink ? [root.defaultSink] : [] }

  ShellIpc {
    target: "joseluis.media"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Process {
    id: cavaProc
    command: ["cava", "-p", root.cavaConfigPath]
    stdout: SplitParser {
      onRead: function(line) { root.ingestLevels(line) }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.cavaFailures++
        if (root.cavaFailures >= 4) root.cavaOk = false
      }
    }
  }

  Timer {
    interval: 800
    repeat: true
    running: root.playing && root.cavaOk && !cavaProc.running
    onTriggered: cavaProc.running = true
  }

  Timer {
    id: positionTicker
    interval: 250
    repeat: true
    running: root.activePlayer !== null && root.playing && !root.userSeeking
    onTriggered: if (root.activePlayer) root.positionValue = root.activePlayer.position
  }

  Connections {
    target: root.activePlayer
    function onPositionChanged() {
      if (root.activePlayer && !root.userSeeking) root.positionValue = root.activePlayer.position
    }
    function onLengthChanged() {
      if (root.activePlayer) root.positionValue = root.activePlayer.position
    }
    function onTrackChanged() {
      root.positionValue = 0
    }
  }

  Item {
    id: visual
    anchors.centerIn: parent
    width: root.vertical ? barSize : root.contentLong
    height: root.vertical ? root.contentLong : barSize

    Row {
      id: viz
      anchors.fill: parent
      spacing: Style.space(2)

      Repeater {
        model: root.visualizerBars

        Item {
          required property int index
          width: Math.max(1, (viz.width - viz.spacing * (root.visualizerBars - 1)) / root.visualizerBars)
          height: viz.height

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2
            width: parent.width
            height: Math.max(2, 2 + (root.levels[index] || 0) * (parent.height - 8))
            radius: width / 2
            color: Commons.Color.accent
            opacity: 0.55

            Behavior on height {
              enabled: root.playing && !Style.reduceMotion
              NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutQuad }
            }
          }
        }
      }
    }

    ClippingRectangle {
      id: cover
      anchors.centerIn: parent
      width: root.coverSize
      height: root.coverSize
      radius: width / 2
      color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)

      Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.artUrl
        visible: source !== ""
      }

      Text {
        anchors.centerIn: parent
        visible: root.artUrl === ""
        textFormat: Text.PlainText
        text: "󰝚"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Math.max(8, root.coverSize - 4)
      }
    }

    Rectangle {
      anchors.fill: cover
      radius: cover.radius
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(root.bar.foreground, 0.35)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    labelVisible: false
    tooltipText: root.hasMedia
      ? (root.title + (root.artist ? " — " + root.artist : "")) : ""

    onPressed: function(b) {
      if (!root.hasMedia) return
      if (b === Qt.RightButton) root.togglePlayPause()
      else if (b === Qt.MiddleButton) root.action("next")
      else root.togglePanel()
    }
    onWheelMoved: function(delta) {
      if (!root.hasMedia) return
      root.changeVolume(delta > 0 ? 0.05 : -0.05)
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(430))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      RowLayout {
        width: parent.width
        spacing: Style.space(12)

        BorderSurface {
          Layout.preferredWidth: Style.space(96)
          Layout.preferredHeight: Style.space(96)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: root.artUrl === ""
            textFormat: Text.PlainText
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.artist !== ""
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.album !== ""
            textFormat: Text.PlainText
            text: root.album
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          Button {
            iconText: "󰒮"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.action("previous")
          }

          Button {
            iconText: root.playing ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.font.iconLarge
            enabled: root.activePlayer
              && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.togglePlayPause()
          }

          Button {
            iconText: "󰒭"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.action("next")
          }
        }
      }

      Item {
        width: parent.width
        height: Math.max(seekSlider.implicitHeight,
          Math.max(positionText.implicitHeight, durationText.implicitHeight))

        Text {
          id: positionText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.formatTime(root.positionValue)
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: durationText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.formatTime(root.trackLength)
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSlider {
          id: seekSlider
          anchors.left: positionText.right
          anchors.right: durationText.left
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: root.trackLength > 0 ? root.trackLength : 1
          value: root.positionValue
          enabled: root.activePlayer && root.activePlayer.canSeek && root.trackLength > 0
          opacity: enabled ? 1.0 : 0.45
          onMoved: function(value) { root.userSeeking = true }
          onReleased: function(value) {
            root.userSeeking = false
            root.seekTo(value)
          }
        }
      }
    }
  }
}
