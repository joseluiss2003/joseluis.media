import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "joseluis.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""

  property bool popupOpen: false
  property real livePosition: -1

  function open() { popupOpen = true }
  function close() { popupOpen = false; livePosition = -1 }
  readonly property bool opened: popupOpen

  // playerctl selector for the active player: its own names come from the
  // MPRIS bus name, which is what the service reports as the player key.
  readonly property string positionTarget: {
    if (!mediaService || !activePlayer) return ""
    var key = mediaService.playerKey(activePlayer)
    if (!key) return ""
    var prefix = "org.mpris.MediaPlayer2."
    return key.indexOf(prefix) === 0 ? key.slice(prefix.length) : key
  }

  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    var mm = (h > 0 && m < 10 ? "0" : "") + m
    return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" : "") + sec
  }

  visible: hasMedia
  implicitWidth: hasMedia ? glyph.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.playIcon
    color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.iconLarge
    Behavior on color {
      enabled: !root.bar || root.bar.foregroundAnimationEnabled
      ColorAnimation { duration: Style.duration(160) }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.LeftButton) {
        root.popupOpen = !root.popupOpen
      } else if (mouse.button === Qt.RightButton) {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      } else if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        id: artRow
        width: parent.width
        spacing: Style.space(12)

        BorderSurface {
          id: artwork
          width: Style.space(72)
          height: Style.space(72)
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.spacing.md
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.artUrl
            visible: source !== ""
          }

          OpticalGlyph {
            visible: root.artUrl === ""
            anchors.centerIn: parent
            text: "󰝚"
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.displayLarge
            color: root.bar.foreground
          }
        }

        Item {
          id: info
          width: artRow.width - artwork.width - artRow.spacing * 2 - controls.implicitWidth
          height: artwork.height

          Column {
            id: infoColumn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              text: root.title || "Nothing playing"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.artist
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.album
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
        }

        Row {
          id: controls
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap
          readonly property real uniformHeight: Math.max(prevButton.implicitHeight, playButton.implicitHeight, nextButton.implicitHeight)

          Button {
            id: prevButton
            height: controls.uniformHeight
            iconText: "󰒮"
            foreground: root.bar.foreground
            iconSize: Style.font.icon
            horizontalPadding: Style.space(6)
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
          }

          Button {
            id: playButton
            height: controls.uniformHeight
            iconText: root.playIcon
            foreground: root.bar.foreground
            iconSize: Style.font.iconLarge
            horizontalPadding: Style.space(6)
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
          }

          Button {
            id: nextButton
            height: controls.uniformHeight
            iconText: "󰒭"
            foreground: root.bar.foreground
            iconSize: Style.font.icon
            horizontalPadding: Style.space(6)
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
          }
        }
      }

      Column {
        id: progress
        width: parent.width
        spacing: Style.space(6)
        visible: available

        readonly property bool available: root.activePlayer !== null
          && root.activePlayer.positionSupported && root.activePlayer.lengthSupported
          && root.activePlayer.length > 0
        readonly property bool seekable: available && root.activePlayer.canSeek
        readonly property real length: available ? root.activePlayer.length : 0
        readonly property real position: available
          ? Math.max(0, Math.min(length, root.livePosition >= 0 ? root.livePosition : root.activePlayer.position))
          : 0
        property bool dragging: false
        property real dragPosition: 0
        readonly property real shown: dragging ? dragPosition : position

        // Quickshell caches MPRIS Position once and then extrapolates it
        // from the clock, re-anchoring only on a Seeked event. A track that
        // loops without seeking leaves that estimate minutes ahead of the
        // real time, the clamp pins the display to the end and the bar
        // looks frozen. Read the true position while the popup is open.
        Process {
          id: positionProc
          running: false
          command: ["playerctl", "-p", root.positionTarget, "position"]
          stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
              var value = parseFloat(text)
              if (!isNaN(value) && value >= 0) root.livePosition = value
            }
          }
        }

        Timer {
          interval: 400
          repeat: true
          triggeredOnStart: true
          running: root.popupOpen && progress.available && !progress.dragging
            && root.positionTarget !== ""
          onTriggered: if (!positionProc.running) positionProc.running = true
        }

        // MPRIS pushes position only on seek/track events, so nudge the
        // cached property too: the bound value only refreshes when its
        // notify signal fires, and this is the fallback when playerctl
        // cannot reach the player.
        Timer {
          interval: 250
          repeat: true
          triggeredOnStart: true
          running: root.popupOpen && progress.available && !progress.dragging
            && root.activePlayer && root.activePlayer.isPlaying
          onTriggered: root.activePlayer.positionChanged()
        }

        Connections {
          target: root
          function onPopupOpenChanged() {
            if (root.popupOpen && root.activePlayer) root.activePlayer.positionChanged()
          }
        }

        function applyPosition(seconds) {
          var p = root.activePlayer
          if (!p || !seekable) return
          var clamped = Math.max(0, Math.min(length, seconds))
          p.position = clamped
          p.positionChanged()
          root.livePosition = clamped
        }

        function seekBy(delta) {
          applyPosition(position + delta)
        }

        Item {
          id: seekBar
          width: parent.width
          height: Style.space(14)

          HoverHandler { id: seekHover }

          function seekTo(x) {
            progress.dragPosition = Math.max(0, Math.min(1, x / width)) * progress.length
          }

          Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Style.space(3)
            radius: height / 2
            color: Util.alpha(root.bar.foreground, 0.2)

            Rectangle {
              width: progress.length > 0 ? parent.width * progress.shown / progress.length : 0
              height: parent.height
              radius: parent.radius
              color: Color.accent

              Behavior on width {
                enabled: !progress.dragging
                NumberAnimation {
                  duration: Style.duration(150)
                  easing.type: Easing.OutCubic
                }
              }
            }
          }

          Rectangle {
            id: knob
            readonly property bool hot: progress.dragging || seekHover.hovered
            width: Style.space(hot ? 12 : 8)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(seekBar.width - width,
              (progress.length > 0 ? seekBar.width * progress.shown / progress.length : 0) - width / 2))
            color: Color.accent

            Behavior on width {
              NumberAnimation { duration: Style.duration(120) }
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: progress.seekable
            hoverEnabled: true
            cursorShape: progress.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: function(mouse) {
              progress.dragging = true
              seekBar.seekTo(mouse.x)
            }
            onPositionChanged: function(mouse) {
              if (progress.dragging) seekBar.seekTo(mouse.x)
            }
            onReleased: {
              if (progress.dragging) progress.applyPosition(progress.dragPosition)
              progress.dragging = false
            }
            onCanceled: progress.dragging = false
            onWheel: function(wheel) {
              progress.seekBy(wheel.angleDelta.y > 0 ? 5 : -5)
            }
          }
        }

        Item {
          width: parent.width
          height: elapsed.implicitHeight

          Text {
            id: elapsed
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: root.formatTime(progress.shown)
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: "-" + root.formatTime(progress.length - progress.shown)
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
