import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

// Opened from the bar icon. Two views: the list of categories with their current
// default, and (after clicking one) the apps offered for that category. Plain
// clickable rows instead of drop-downs, so nothing depends on popups.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 400 * Style.uiScaleRatio
  property real contentPreferredHeight: 600 * Style.uiScaleRatio
  readonly property bool allowAttach: true
  anchors.fill: parent

  readonly property var mainInstance: pluginApi?.mainInstance

  // null: category list, otherwise the category whose apps are shown
  property var selectedCategory: null

  // App list: search text and how many matches are shown ("Show more" adds 5)
  readonly property int pageSize: 5
  property int shownCount: pageSize

  onSelectedCategoryChanged: {
    searchInput.text = "";
    shownCount = pageSize;
  }

  Component.onCompleted: mainInstance?.refresh()

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.marginM
      color: Color.mSurfaceVariant
      radius: Style.radiusL

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NIconButton {
            visible: root.selectedCategory !== null
            icon: "arrow-left"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: "Back"
            onClicked: root.selectedCategory = null
          }

          NIcon {
            visible: root.selectedCategory === null
            icon: "apps"
            pointSize: Style.fontSizeXL
            color: Color.mPrimary
          }

          NText {
            text: root.selectedCategory ? root.selectedCategory.label : "Default Apps"
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
            elide: Text.ElideRight
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

        NText {
          Layout.fillWidth: true
          text: root.selectedCategory
                ? "Choose the default app. Changes apply right away."
                : "Used by Dolphin and other KDE apps, GTK apps, xdg-open and the desktop portal."
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          wrapMode: Text.WordWrap
        }

        // e.g. "xdg-terminal-exec is not installed ..."
        Repeater {
          model: root.selectedCategory === null ? (mainInstance?.warnings ?? []) : []

          delegate: NText {
            required property var modelData
            Layout.fillWidth: true
            text: modelData
            pointSize: Style.fontSizeS
            color: Color.mError
            wrapMode: Text.WordWrap
          }
        }

        // Category list
        ListView {
          visible: root.selectedCategory === null
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.marginXS
          boundsBehavior: Flickable.StopAtBounds
          model: mainInstance?.categories ?? []

          delegate: Rectangle {
            id: catRow
            required property var modelData
            width: ListView.view.width
            height: catLayout.implicitHeight + Style.marginS * 2
            radius: Style.radiusM
            color: catMouse.containsMouse ? Color.mHover : "transparent"

            // the comma expressions make these re-evaluate when the scan results change
            readonly property string currentId: mainInstance ? (mainInstance.defaults, mainInstance.terminal, mainInstance.current(modelData)) : ""
            readonly property string statusText: mainInstance ? (mainInstance.defaults, mainInstance.apps, mainInstance.terminal, mainInstance.status(modelData)) : ""

            RowLayout {
              id: catLayout
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginM

              NIcon {
                icon: catRow.modelData.icon
                pointSize: Style.fontSizeL
                color: catMouse.containsMouse ? Color.mOnHover : Color.mPrimary
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                NText {
                  Layout.fillWidth: true
                  text: catRow.modelData.label
                  pointSize: Style.fontSizeM
                  font.weight: Style.fontWeightBold
                  color: catMouse.containsMouse ? Color.mOnHover : Color.mOnSurface
                  elide: Text.ElideRight
                }

                NText {
                  Layout.fillWidth: true
                  text: catRow.currentId ? mainInstance.appName(catRow.currentId) : "Not set"
                  pointSize: Style.fontSizeS
                  color: catMouse.containsMouse ? Color.mOnHover : Color.mOnSurface
                  elide: Text.ElideRight
                }

                NText {
                  Layout.fillWidth: true
                  visible: text !== ""
                  text: catRow.statusText
                  pointSize: Style.fontSizeXS
                  color: catMouse.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                  wrapMode: Text.WordWrap
                }
              }

              NIcon {
                icon: "chevron-right"
                pointSize: Style.fontSizeM
                color: catMouse.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
              }
            }

            MouseArea {
              id: catMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedCategory = catRow.modelData
            }
          }
        }

        NTextInput {
          id: searchInput
          visible: root.selectedCategory !== null
          Layout.fillWidth: true
          inputIconName: "search"
          placeholderText: "Search apps"
          onTextChanged: root.shownCount = root.pageSize
        }

        // App list for the selected category
        ListView {
          id: appList
          visible: root.selectedCategory !== null
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.marginXS
          boundsBehavior: Flickable.StopAtBounds
          model: matches.slice(0, root.shownCount)

          readonly property var matches: {
            if (!mainInstance || !root.selectedCategory)
              return [];
            const all = (mainInstance.apps, mainInstance.candidates(root.selectedCategory));
            const q = searchInput.text.trim().toLowerCase();
            return q === "" ? all : all.filter(a => a.name.toLowerCase().includes(q) || a.key.toLowerCase().includes(q));
          }

          footer: NButton {
            visible: appList.matches.length > root.shownCount
            height: visible ? implicitHeight : 0
            text: "Show more (" + (appList.matches.length - root.shownCount) + " more)"
            outlined: true
            onClicked: root.shownCount += root.pageSize
          }

          readonly property string currentId: (mainInstance && root.selectedCategory) ? (mainInstance.defaults, mainInstance.terminal, mainInstance.current(root.selectedCategory)) : ""

          delegate: Rectangle {
            id: appRow
            required property var modelData
            readonly property bool isCurrent: modelData.key === ListView.view.currentId
            width: ListView.view.width
            height: appText.implicitHeight + Style.marginS * 2
            radius: Style.radiusM
            color: appMouse.containsMouse ? Color.mHover : (isCurrent ? Qt.alpha(Color.mPrimary, 0.15) : "transparent")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginM

              NText {
                id: appText
                Layout.fillWidth: true
                text: appRow.modelData.name
                pointSize: Style.fontSizeM
                color: appMouse.containsMouse ? Color.mOnHover : Color.mOnSurface
                elide: Text.ElideRight
              }

              NIcon {
                visible: appRow.isCurrent
                icon: "check"
                pointSize: Style.fontSizeM
                color: appMouse.containsMouse ? Color.mOnHover : Color.mPrimary
              }
            }

            MouseArea {
              id: appMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                mainInstance?.setDefault(root.selectedCategory, appRow.modelData.key);
                root.selectedCategory = null;
              }
            }
          }

          NText {
            anchors.centerIn: parent
            visible: parent.count === 0
            text: (mainInstance?.loading ?? false) ? "Loading..."
                  : searchInput.text.trim() !== "" ? "No app matches the search"
                  : "No installed app supports this"
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }
  }
}
