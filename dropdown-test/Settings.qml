import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Plugin settings page: same tests as the panel, but inside Noctalia's settings
// popup, where the drop-downs of default-apps 0.2 never opened.
ColumnLayout {
  id: root

  property var pluginApi: null
  spacing: Style.marginM

  readonly property var tests: Qt.createComponent(Qt.resolvedUrl("DropdownTests.qml"))

  function saveSettings() {}

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
      item.place = "settings";
      item.pluginApi = root.pluginApi;
    }
  }
}
