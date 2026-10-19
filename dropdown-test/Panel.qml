import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

// Opened from the bar icon. Shows the same tests as the settings page, so the two
// places (panel window vs. settings popup) can be compared.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 460 * Style.uiScaleRatio
  property real contentPreferredHeight: 700 * Style.uiScaleRatio
  readonly property bool allowAttach: true
  anchors.fill: parent

  // Loaded by hand instead of by type name, so a load error is shown here
  readonly property var tests: Qt.createComponent(Qt.resolvedUrl("DropdownTests.qml"))

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.marginM
      color: Color.mSurfaceVariant
      radius: Style.radiusL

      NScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: Style.marginM

        ColumnLayout {
          width: scroll.availableWidth
          spacing: Style.marginM

          NText {
            visible: root.tests.status === Component.Error
            Layout.fillWidth: true
            text: "DropdownTests.qml failed to load:\n" + root.tests.errorString()
            color: Color.mError
            wrapMode: Text.WordWrap
          }

          Loader {
            Layout.fillWidth: true
            sourceComponent: root.tests.status === Component.Ready ? root.tests : null
            onLoaded: {
              item.place = "panel";
              item.pluginApi = root.pluginApi;
            }
          }
        }
      }
    }
  }
}
