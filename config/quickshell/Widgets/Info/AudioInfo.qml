pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool active: false
    property var sinks: []
    property var sources: []
    property var devices: []
    property string defaultSink: ""
    property string defaultSource: ""

    onActiveChanged: {
        if (active) {
            update();
        }
    }

    function update(): void {
        fetchProc.running = true;
    }

    function setDefaultSink(name: string): void {
        if (!name) return;
        actionProc.command = ["pactl", "set-default-sink", name];
        actionProc.running = true;
    }

    function setDefaultSource(name: string): void {
        if (!name) return;
        actionProc.command = ["pactl", "set-default-source", name];
        actionProc.running = true;
    }

    function toggleDevice(dev): void {
        if (!dev || !dev.name) return;
        if (dev.kind === "sink") {
            setDefaultSink(dev.name);
        } else if (dev.kind === "source") {
            setDefaultSource(dev.name);
        }
    }

    function toggleMute(dev): void {
        if (!dev || !dev.name) return;
        if (dev.kind === "sink") {
            actionProc.command = ["pactl", "set-sink-mute", dev.name, "toggle"];
        } else {
            actionProc.command = ["pactl", "set-source-mute", dev.name, "toggle"];
        }
        actionProc.running = true;
    }

    function setVolume(dev, percent: int): void {
        if (!dev || !dev.name) return;
        var p = Math.max(0, Math.min(150, percent)) + "%";
        if (dev.kind === "sink") {
            actionProc.command = ["pactl", "set-sink-volume", dev.name, p];
        } else {
            actionProc.command = ["pactl", "set-source-volume", dev.name, p];
        }
        actionProc.running = true;
    }

    Process {
        id: actionProc
        running: false
        onExited: (code) => {
            root.update();
        }
    }

    Process {
        id: fetchProc
        running: false
        command: [
            "python3", "-c",
            "import json, subprocess\n" +
            "def get_audio_info():\n" +
            "    try:\n" +
            "        sinks_raw = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sinks'], stderr=subprocess.DEVNULL).decode('utf-8')\n" +
            "        sinks_data = json.loads(sinks_raw)\n" +
            "    except Exception:\n" +
            "        sinks_data = []\n" +
            "    try:\n" +
            "        sources_raw = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sources'], stderr=subprocess.DEVNULL).decode('utf-8')\n" +
            "        sources_data = json.loads(sources_raw)\n" +
            "    except Exception:\n" +
            "        sources_data = []\n" +
            "    try:\n" +
            "        def_sink = subprocess.check_output(['pactl', 'get-default-sink'], stderr=subprocess.DEVNULL).decode('utf-8').strip()\n" +
            "    except Exception:\n" +
            "        def_sink = ''\n" +
            "    try:\n" +
            "        def_source = subprocess.check_output(['pactl', 'get-default-source'], stderr=subprocess.DEVNULL).decode('utf-8').strip()\n" +
            "    except Exception:\n" +
            "        def_source = ''\n" +
            "    sinks = []\n" +
            "    for s in sinks_data:\n" +
            "        name = s.get('name', '')\n" +
            "        desc = s.get('description') or s.get('properties', {}).get('node.nick') or s.get('properties', {}).get('device.description') or name\n" +
            "        vol_obj = s.get('volume', {})\n" +
            "        vol_val = 0\n" +
            "        vol_pct = ''\n" +
            "        for ch, v in vol_obj.items():\n" +
            "            if isinstance(v, dict) and 'value_percent' in v:\n" +
            "                vol_pct = v['value_percent']\n" +
            "                vol_val = int(vol_pct.replace('%', '').strip())\n" +
            "                break\n" +
            "        sinks.append({\n" +
            "            'name': name,\n" +
            "            'description': desc,\n" +
            "            'volume': vol_val,\n" +
            "            'volumePercent': vol_pct or '0%',\n" +
            "            'muted': s.get('mute', False),\n" +
            "            'isDefault': (name == def_sink),\n" +
            "            'kind': 'sink'\n" +
            "        })\n" +
            "    sources = []\n" +
            "    for s in sources_data:\n" +
            "        name = s.get('name', '')\n" +
            "        if name.endswith('.monitor') or s.get('monitor_source') == name:\n" +
            "            continue\n" +
            "        if s.get('properties', {}).get('media.class') == 'Audio/Sink':\n" +
            "            continue\n" +
            "        desc = s.get('description') or s.get('properties', {}).get('node.nick') or s.get('properties', {}).get('device.description') or name\n" +
            "        vol_obj = s.get('volume', {})\n" +
            "        vol_val = 0\n" +
            "        vol_pct = ''\n" +
            "        for ch, v in vol_obj.items():\n" +
            "            if isinstance(v, dict) and 'value_percent' in v:\n" +
            "                vol_pct = v['value_percent']\n" +
            "                vol_val = int(vol_pct.replace('%', '').strip())\n" +
            "                break\n" +
            "        sources.append({\n" +
            "            'name': name,\n" +
            "            'description': desc,\n" +
            "            'volume': vol_val,\n" +
            "            'volumePercent': vol_pct or '0%',\n" +
            "            'muted': s.get('mute', False),\n" +
            "            'isDefault': (name == def_source),\n" +
            "            'kind': 'source'\n" +
            "        })\n" +
            "    print(json.dumps({\n" +
            "        'sinks': sinks,\n" +
            "        'sources': sources,\n" +
            "        'defaultSink': def_sink,\n" +
            "        'defaultSource': def_source\n" +
            "    }))\n" +
            "get_audio_info()\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.sinks = data.sinks || [];
                    root.sources = data.sources || [];
                    root.defaultSink = data.defaultSink || "";
                    root.defaultSource = data.defaultSource || "";
                    root.devices = [...root.sinks, ...root.sources];
                } catch (e) {
                    console.log("AudioInfo parse error:", e);
                }
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        onTriggered: {
            if (!fetchProc.running)
                fetchProc.running = true;
        }
    }

    Component.onCompleted: {
        update();
    }
}
