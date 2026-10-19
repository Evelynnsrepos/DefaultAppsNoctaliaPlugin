import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Shown in Noctalia's settings (Plugins -> Default Apps -> settings). Choices are
// applied immediately, so there is nothing left to save.
ColumnLayout {
  id: root
  spacing: Style.marginM

  property var pluginApi: null
  property real preferredWidth: 480 * Style.uiScaleRatio

  readonly property var mainInstance: pluginApi?.mainInstance

  Component.onCompleted: mainInstance?.refresh()

  function saveSettings() {}

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: "Used by Dolphin and other KDE apps, GTK apps, xdg-open and the desktop portal. Changes apply right away."
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      wrapMode: Text.WordWrap
    }

    NIconButton {
      icon: "refresh"
      baseSize: Style.baseWidgetSize * 0.8
      tooltipText: "Reload installed apps"
      onClicked: mainInstance?.refresh()

      RotationAnimation on rotation {
        running: mainInstance?.loading ?? false
        from: 0; to: 360
        duration: 1000
        loops: Animation.Infinite
      }
    }
  }

  // e.g. "xdg-terminal-exec is not installed ..."
  Repeater {
    model: mainInstance?.warnings ?? []

    delegate: NText {
      required property var modelData
      Layout.fillWidth: true
      text: modelData
      pointSize: Style.fontSizeS
      color: Color.mError
      wrapMode: Text.WordWrap
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  Repeater {
    model: mainInstance?.categories ?? []

    delegate: RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.marginM

      NIcon {
        icon: modelData.icon
        pointSize: Style.fontSizeL
        color: Color.mPrimary
        Layout.alignment: Qt.AlignVCenter
      }

      NComboBox {
        Layout.fillWidth: true
        minimumWidth: 0
        label: modelData.label
        // the comma expressions make these re-evaluate when the scan results change
        description: mainInstance ? (mainInstance.defaults, mainInstance.apps, mainInstance.terminal, mainInstance.status(modelData)) : ""
        model: mainInstance ? (mainInstance.apps, mainInstance.candidates(modelData)) : []
        currentKey: mainInstance ? (mainInstance.defaults, mainInstance.terminal, mainInstance.current(modelData)) : ""
        placeholder: "Not set"
        onSelected: key => mainInstance?.setDefault(modelData, key)
      }
    }
  }
}
