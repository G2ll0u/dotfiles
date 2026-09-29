import QtQuick
import qs.Data as Dat

MouseArea {
    id: root

    property bool soundOnHover: true
    property bool soundOnClick: true
    property bool soundOnRightClick: true

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
        if (soundOnHover) {
            Dat.P3rSfx.hover();
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton && soundOnClick) {
            Dat.P3rSfx.select();
        } else if (mouse.button === Qt.RightButton && soundOnRightClick) {
            Dat.P3rSfx.back();
        }
    }
}
