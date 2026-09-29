import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../Data" as Dat

Scope {
    id: root

    // État de l'alerte
    property bool isAmbushActive: false
    property int targetPid: 0
    property string targetName: "UNKNOWN_PROCESS"
    property real targetMemoryMb: 0
    property real targetCpuPercent: 0
    property real totalRamMb: 16384
    property real systemRamPercent: 85.0

    // Ratio HP calculé pour la barre de vie
    readonly property real hpRatio: Math.min(1.0, Math.max(0.05, targetMemoryMb / Math.max(1024, (totalRamMb * 0.5))))

    // ─────────────────────────────────────────────────────────────
    // Contrôle & Actions
    // ─────────────────────────────────────────────────────────────

    function triggerAmbush(pid, name, memMb, cpuPct, totalRam, ramPct) {
        targetPid = pid;
        targetName = (name && name.length > 0) ? name.toUpperCase() : "TARGET_PROCESS";
        targetMemoryMb = memMb || 0;
        targetCpuPercent = cpuPct || 0;
        totalRamMb = totalRam || 16384;
        systemRamPercent = ramPct || 80.0;
        isAmbushActive = true;
        try { Dat.P3rSfx.openMenu(); } catch(e) {}
    }

    function dismissAmbush() {
        try { Dat.P3rSfx.closeMenu(); } catch(e) {}
        if (!isAmbushActive) return;
        if (exitAnim.running) {
            root.isAmbushActive = false;
            return;
        }
        exitAnim.restart();
    }

    function executeKill() {
        if (targetPid > 0) {
            try { Dat.P3rSfx.achievement(); } catch(e) {}
            killSlashAnim.start();
            killProc.command = [
                "gdbus", "call", "--session",
                "--dest", "org.persona.ProcessKiller",
                "--object-path", "/org/persona/ProcessKiller",
                "--method", "org.persona.ProcessKiller.KillProcess",
                root.targetPid.toString()
            ];
            killProc.running = true;
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Communication D-Bus & IPC
    // ─────────────────────────────────────────────────────────────

    // Écoute continue des signaux D-Bus
    Process {
        id: dbusMonitorProc
        command: ["gdbus", "monitor", "--session", "--dest", "org.persona.ProcessKiller"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("AmbushTriggered")) {
                    const regex = /\((\d+),\s*'([^']*)',\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)/;
                    const match = data.match(regex);
                    if (match) {
                        root.triggerAmbush(
                            parseInt(match[1]),
                            match[2],
                            parseFloat(match[3]),
                            parseFloat(match[4]),
                            parseFloat(match[5]),
                            parseFloat(match[6])
                        );
                    }
                }
            }
        }
    }

    // Exécution du Kill (avec fallback kill -9)
    Process {
        id: killProc
        command: ["true"]
        running: false
        onExited: (code, status) => {
            if (code !== 0 && root.targetPid > 0) {
                fallbackKillProc.command = ["kill", "-9", root.targetPid.toString()];
                fallbackKillProc.running = true;
            }
        }
    }

    Process {
        id: fallbackKillProc
        command: ["true"]
        running: false
    }

    // IPC Quickshell direct (qs -c ~/.config/quickshell/ ipc call persona_killer trigger ...)
    IpcHandler {
        target: "persona_killer"
        function trigger(pid, name, memMb, cpuPct, totalRam, ramPct) {
            root.triggerAmbush(
                parseInt(pid),
                name,
                parseFloat(memMb),
                parseFloat(cpuPct),
                parseFloat(totalRam),
                parseFloat(ramPct)
            );
        }
        function test() {
            root.triggerAmbush(1337, "CHROME.EXE", 3840.5, 78.4, 16384, 86.2);
        }
        function dismiss() {
            root.dismissAmbush();
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Overlay Plein Écran (wlr-layer-shell)
    // ─────────────────────────────────────────────────────────────

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: ambushWindow
            property var modelData
            screen: modelData
            visible: root.isAmbushActive
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "persona-process-killer"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: root.isAmbushActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // FocusScope pour capture clavier infaillible (Échap, Entrée, Espace)
            FocusScope {
                anchors.fill: parent
                focus: root.isAmbushActive

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.dismissAmbush();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.executeKill();
                        event.accepted = true;
                    }
                }
            }

            // Conteneur principal
            Rectangle {
                id: mainContainer
                anchors.fill: parent
                color: Qt.rgba(0.04, 0.06, 0.1, 0.90)
                opacity: 0
                scale: 1.05

                // Zone cliquable de secours en arrière-plan (clic pour fermer directement)
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: root.dismissAmbush()
                }

                // Lignes de hachures Persona
                Canvas {
                    anchors.fill: parent
                    opacity: 0.25
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.strokeStyle = "#E60012";
                        ctx.lineWidth = 2;
                        for (var x = -parent.height; x < parent.width + parent.height; x += 35) {
                            ctx.beginPath();
                            ctx.moveTo(x, 0);
                            ctx.lineTo(x + parent.height * 0.6, parent.height);
                            ctx.stroke();
                        }
                    }
                }

                // Flash d'impact au Kill
                Rectangle {
                    id: slashFlash
                    anchors.fill: parent
                    color: "white"
                    opacity: 0
                    z: 100
                }

                // ── Bannière Haute : "MASS DESTRUCTION // RAM AMBUSH" ──
                Rectangle {
                    id: topBanner
                    anchors {
                        top: parent.top
                        topMargin: 45
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: parent.width * 0.85
                    height: 70
                    color: "#E60012"
                    transform: Rotation { angle: -2 }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: -10
                        anchors.topMargin: -6
                        color: "#0C0F1D"
                        z: -1
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 25
                        anchors.rightMargin: 25

                        Text {
                            text: "⚠️  MASS DESTRUCTION // RAM AMBUSH"
                            color: "#FFFFFF"
                            font.pixelSize: 28
                            font.bold: true
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 2
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            color: "#FFD700"
                            implicitWidth: 160
                            implicitHeight: 36
                            radius: 4

                            Text {
                                anchors.centerIn: parent
                                text: "RAM " + root.systemRamPercent.toFixed(0) + "% CRITICAL"
                                color: "#000000"
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }
                    }
                }

                // ── Carte Centrale du Boss / Processus ──
                Rectangle {
                    id: bossCard
                    anchors.centerIn: parent
                    width: Math.min(850, parent.width * 0.75)
                    height: 380
                    color: "#0F1420"
                    border.color: "#E60012"
                    border.width: 3
                    radius: 4
                    transform: Rotation { angle: -1.5 }

                    // Solid Shadow
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.topMargin: 12
                        color: "#E60012"
                        z: -1
                        radius: 4
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 35
                        spacing: 20

                        // Header Boss
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 15

                            Rectangle {
                                color: "#1CC9D9"
                                implicitWidth: 80
                                implicitHeight: 32
                                radius: 3

                                Text {
                                    anchors.centerIn: parent
                                    text: "SHADOW"
                                    color: "#000000"
                                    font.bold: true
                                    font.pixelSize: 14
                                }
                            }

                            Text {
                                text: root.targetName
                                color: "#FFFFFF"
                                font.pixelSize: 34
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "PID #" + root.targetPid
                                color: "#FFD700"
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 2
                            color: "#303A4D"
                        }

                        // Barre de Vie
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "HP // MEMORY CONSUMPTION"
                                    color: "#E60012"
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.targetMemoryMb.toFixed(1) + " MB (" + (root.targetMemoryMb / 1024).toFixed(2) + " GB)"
                                    color: "#FFFFFF"
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 26
                                color: "#06080E"
                                border.color: "#4A5568"
                                border.width: 1
                                radius: 2

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 2
                                    width: Math.max(10, (parent.width - 4) * root.hpRatio)
                                    color: root.targetMemoryMb > 2048 ? "#E60012" : "#FF6B00"

                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        PropertyAnimation { to: 0.6; duration: 600; easing.type: Easing.InOutQuad }
                                        PropertyAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "CPU THREAT: " + root.targetCpuPercent.toFixed(1) + "%"
                                    color: "#1CC9D9"
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "TOTAL RAM: " + (root.totalRamMb / 1024).toFixed(1) + " GB"
                                    color: "#A0AEC0"
                                    font.pixelSize: 13
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Boutons d'Action
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 25

                            // Bouton SIGKILL
                            Button {
                                id: killBtn
                                Layout.fillWidth: true
                                implicitHeight: 65
                                onClicked: root.executeKill()

                                background: Rectangle {
                                    color: killBtn.hovered ? "#FF2A42" : "#E60012"
                                    radius: 4
                                    transform: Rotation { angle: -1 }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.leftMargin: -4
                                        anchors.topMargin: 4
                                        color: "#000000"
                                        z: -1
                                        radius: 4
                                    }
                                }

                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    Text {
                                        text: "⚔️ ALL-OUT ATTACK (SIGKILL)"
                                        color: "#FFFFFF"
                                        font.pixelSize: 20
                                        font.bold: true
                                        font.letterSpacing: 1
                                    }
                                    Rectangle {
                                        color: "#FFD700"
                                        implicitWidth: 65
                                        implicitHeight: 24
                                        radius: 3
                                        Text {
                                            anchors.centerIn: parent
                                            text: "ENTER"
                                            color: "#000000"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            // Bouton ESCAPE
                            Button {
                                id: escapeBtn
                                Layout.preferredWidth: 200
                                implicitHeight: 65
                                onClicked: root.dismissAmbush()

                                background: Rectangle {
                                    color: escapeBtn.hovered ? "#2D3748" : "#1A202C"
                                    border.color: "#4A5568"
                                    border.width: 1
                                    radius: 4
                                }

                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "ESCAPE"
                                        color: "#E2E8F0"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                    Rectangle {
                                        color: "#4A5568"
                                        implicitWidth: 45
                                        implicitHeight: 22
                                        radius: 3
                                        Text {
                                            anchors.centerIn: parent
                                            text: "ESC"
                                            color: "#FFFFFF"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Animations
                ParallelAnimation {
                    id: enterAnim
                    running: root.isAmbushActive
                    NumberAnimation {
                        target: mainContainer
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: mainContainer
                        property: "scale"
                        from: 1.08
                        to: 1.0
                        duration: 300
                        easing.type: Easing.OutBack
                    }
                }

                SequentialAnimation {
                    id: killSlashAnim
                    ParallelAnimation {
                        NumberAnimation {
                            target: slashFlash
                            property: "opacity"
                            from: 0
                            to: 0.95
                            duration: 100
                        }
                        NumberAnimation {
                            target: bossCard
                            property: "scale"
                            from: 1.0
                            to: 1.15
                            duration: 120
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: slashFlash
                            property: "opacity"
                            to: 0
                            duration: 350
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: mainContainer
                            property: "opacity"
                            to: 0
                            duration: 350
                        }
                    }
                    ScriptAction {
                        script: {
                            root.isAmbushActive = false;
                            bossCard.scale = 1.0;
                        }
                    }
                }

                SequentialAnimation {
                    id: exitAnim
                    NumberAnimation {
                        target: mainContainer
                        property: "opacity"
                        to: 0
                        duration: 200
                        easing.type: Easing.InQuad
                    }
                    ScriptAction {
                        script: {
                            root.isAmbushActive = false;
                        }
                    }
                }
            }
        }
    }
}
