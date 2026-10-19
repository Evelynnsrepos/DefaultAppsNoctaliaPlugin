import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

// The actual tests, used by Panel.qml and Settings.qml. Every press, popup
// open/close and selection is written to the event log below (newest on top) and
// to the Noctalia log with the tag "DropdownTest".
ColumnLayout {
  id: root

  property var pluginApi: null
  property string place: "?"  // "panel" or "settings"

  spacing: Style.marginM

  readonly property var fruits: [
    { key: "apple",  name: "Apple" },
    { key: "banana", name: "Banana" },
    { key: "cherry", name: "Cherry" },
    { key: "grape",  name: "Grape" },
    { key: "lemon",  name: "Lemon" }
  ]

  property string realDir: ""

  ListModel { id: events }

  function log(msg) {
    const line = Qt.formatTime(new Date(), "hh:mm:ss.zzz") + " [" + place + "] " + msg;
    events.insert(0, { line: line });
    if (events.count > 200) events.remove(200, events.count - 200);
    Logger.i("DropdownTest", line);
  }

  function rect(item) {
    if (!item) return "null";
    return Math.round(item.x) + "," + Math.round(item.y) + " " + Math.round(item.width) + "x" + Math.round(item.height);
  }

  function popupInfo(popup) {
    const win = popup.parent?.Window?.window;
    return "popup " + rect(popup)
        + " implicitH=" + Math.round(popup.implicitHeight)
        + " visible=" + popup.visible + " opacity=" + popup.opacity
        + " | parent=" + popup.parent
        + " | window=" + (win ? Math.round(win.width) + "x" + Math.round(win.height) : "none")
        + " | overlay=" + rect(popup.parent?.Overlay?.overlay);
  }

  Component.onCompleted: log("loaded, window=" + (root.Window.window ? root.Window.window : "none (not yet)"))

  // ----- paths (the "File name case mismatch" error comes from a link in here) -----

  Process {
    running: (pluginApi?.pluginDir ?? "") !== ""
    command: ["readlink", "-f", pluginApi?.pluginDir ?? ""]
    stdout: StdioCollector {
      onStreamFinished: root.realDir = text.trim()
    }
  }

  NText {
    text: "Paths"
    pointSize: Style.fontSizeL
    font.weight: Style.fontWeightBold
    color: Color.mPrimary
  }

  NText {
    Layout.fillWidth: true
    wrapMode: Text.WrapAnywhere
    pointSize: Style.fontSizeS
    color: Color.mOnSurface
    text: "pluginDir: " + (pluginApi?.pluginDir ?? "(no pluginApi)")
          + "\nreal path: " + (root.realDir || "...")
          + "\nNOCTALIA_CONFIG_DIR: " + (Quickshell.env("NOCTALIA_CONFIG_DIR") || "(not set)")
          + "\nconfigDir: " + Settings.configDir
          + "\nthis file: " + Qt.resolvedUrl("DropdownTests.qml")
  }

  NText {
    Layout.fillWidth: true
    visible: root.realDir !== "" && pluginApi && root.realDir !== pluginApi.pluginDir
    wrapMode: Text.WordWrap
    pointSize: Style.fontSizeS
    color: Color.mError
    text: "pluginDir goes through a link. Qt then reports \"File name case mismatch\" for the plugin's QML files."
  }

  NDivider { Layout.fillWidth: true }

  // ----- A: Noctalia's NComboBox with a plain array (what default-apps 0.2 used) -----

  NComboBox {
    id: comboA
    Layout.fillWidth: true
    label: "A: NComboBox, array model"
    description: "Same widget and kind of model as default-apps 0.2."
    model: root.fruits
    currentKey: "banana"
    onSelected: key => { currentKey = key; root.log("A selected " + key); }
  }

  Connections {
    target: comboA.comboBox
    function onPressedChanged() { root.log("A pressed=" + comboA.comboBox.pressed); }
    function onActivated(index) { root.log("A activated " + index); }
  }

  Connections {
    target: comboA.comboBox.popup
    function onAboutToShow() { root.log("A aboutToShow"); }
    function onOpened() { root.log("A opened: " + root.popupInfo(comboA.comboBox.popup)); }
    function onClosed() { root.log("A closed"); }
  }

  // ----- B: NComboBox with a ListModel -----

  ListModel {
    id: fruitModel
    ListElement { key: "apple";  name: "Apple" }
    ListElement { key: "banana"; name: "Banana" }
    ListElement { key: "cherry"; name: "Cherry" }
  }

  NComboBox {
    id: comboB
    Layout.fillWidth: true
    label: "B: NComboBox, ListModel"
    description: "Same widget, the model type Noctalia itself mostly uses."
    model: fruitModel
    currentKey: "apple"
    onSelected: key => { currentKey = key; root.log("B selected " + key); }
  }

  Connections {
    target: comboB.comboBox.popup
    function onOpened() { root.log("B opened: " + root.popupInfo(comboB.comboBox.popup)); }
    function onClosed() { root.log("B closed"); }
  }

  // ----- C: plain Qt ComboBox, no Noctalia styling -----

  NText {
    text: "C: plain Qt ComboBox"
    pointSize: Style.fontSizeM
    color: Color.mOnSurface
  }

  ComboBox {
    id: comboC
    Layout.fillWidth: true
    model: ["One", "Two", "Three"]
    onActivated: index => root.log("C activated " + index)
    onPressedChanged: root.log("C pressed=" + pressed)
  }

  Connections {
    target: comboC.popup
    function onOpened() { root.log("C opened: " + root.popupInfo(comboC.popup)); }
    function onClosed() { root.log("C closed"); }
  }

  // ----- D: a bare Popup opened by a button (do popups show at all here?) -----

  NButton {
    id: popupButton
    text: "D: open a plain Popup"
    onClicked: {
      root.log("D button clicked");
      plainPopup.open();
    }
  }

  Popup {
    id: plainPopup
    parent: popupButton
    y: popupButton.height + Style.marginS
    width: 220
    height: 80
    onOpened: root.log("D opened: " + root.popupInfo(plainPopup))
    onClosed: root.log("D closed")

    background: Rectangle {
      color: Color.mSurface
      border.color: Color.mPrimary
      border.width: Style.borderM
      radius: Style.radiusM
    }

    contentItem: NText {
      text: "Popup works. Click outside to close."
      color: Color.mOnSurface
      wrapMode: Text.WordWrap
    }
  }

  // ----- E: a plain click area (do clicks reach this page at all?) -----

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.baseWidgetSize
    radius: Style.radiusM
    color: clickArea.containsMouse ? Color.mHover : Color.mSurface
    border.color: Color.mOutline

    NText {
      anchors.centerIn: parent
      text: "E: click me"
      color: clickArea.containsMouse ? Color.mOnHover : Color.mOnSurface
    }

    MouseArea {
      id: clickArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.log("E clicked")
    }
  }

  NDivider { Layout.fillWidth: true }

  // ----- event log -----

  RowLayout {
    Layout.fillWidth: true

    NText {
      Layout.fillWidth: true
      text: "Event log (" + events.count + ")"
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightBold
      color: Color.mPrimary
    }

    NButton {
      text: "Clear"
      outlined: true
      onClicked: events.clear()
    }
  }

  Repeater {
    model: events

    delegate: NText {
      required property string line
      Layout.fillWidth: true
      text: line
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      wrapMode: Text.WrapAnywhere
    }
  }
}
