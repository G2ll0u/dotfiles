pragma Singleton
import Quickshell
import QtQuick
import QtMultimedia

Singleton {
    id: root

    // Master volume & enable toggle
    property real volume: 0.7
    property bool enabled: true

    // Individual SoundEffects (WAV 48kHz P3R Rips for ultra-low latency)
    SoundEffect {
        id: sfxHover
        source: Qt.resolvedUrl("../Assets/sounds/hover.wav")
        volume: root.volume * 0.7
    }

    SoundEffect {
        id: sfxSelect
        source: Qt.resolvedUrl("../Assets/sounds/select.wav")
        volume: root.volume * 0.85
    }

    SoundEffect {
        id: sfxReturn
        source: Qt.resolvedUrl("../Assets/sounds/return.wav")
        volume: root.volume * 0.85
    }

    SoundEffect {
        id: sfxOpenMenu
        source: Qt.resolvedUrl("../Assets/sounds/open_menu.wav")
        volume: root.volume * 0.85
    }

    SoundEffect {
        id: sfxCloseMenu
        source: Qt.resolvedUrl("../Assets/sounds/close_menu.wav")
        volume: root.volume * 0.85
    }

    SoundEffect {
        id: sfxSwitchOn
        source: Qt.resolvedUrl("../Assets/sounds/switch_on.wav")
        volume: root.volume * 0.75
    }

    SoundEffect {
        id: sfxSwitchOff
        source: Qt.resolvedUrl("../Assets/sounds/switch_off.wav")
        volume: root.volume * 0.75
    }

    SoundEffect {
        id: sfxTab
        source: Qt.resolvedUrl("../Assets/sounds/tab_switch.wav")
        volume: root.volume * 0.8
    }

    SoundEffect {
        id: sfxSliderUp
        source: Qt.resolvedUrl("../Assets/sounds/slider_up.wav")
        volume: root.volume * 0.7
    }

    SoundEffect {
        id: sfxSliderDown
        source: Qt.resolvedUrl("../Assets/sounds/slider_down.wav")
        volume: root.volume * 0.7
    }

    SoundEffect {
        id: sfxToast
        source: Qt.resolvedUrl("../Assets/sounds/toast.wav")
        volume: root.volume * 0.85
    }

    SoundEffect {
        id: sfxAchievement
        source: Qt.resolvedUrl("../Assets/sounds/achievement.wav")
        volume: root.volume * 0.9
    }

    // Direct playback functions
    function hover() {
        if (root.enabled) sfxHover.play();
    }
    function playHover() { hover(); }

    function select() {
        if (root.enabled) sfxSelect.play();
    }
    function playSelect() { select(); }

    function back() {
        if (root.enabled) sfxReturn.play();
    }
    function playBack() { back(); }
    function playReturn() { back(); }
    function returnSfx() { back(); }

    function openMenu() {
        if (root.enabled) sfxOpenMenu.play();
    }
    function playOpenMenu() { openMenu(); }

    function closeMenu() {
        if (root.enabled) sfxCloseMenu.play();
    }
    function playCloseMenu() { closeMenu(); }

    function switchOn() {
        if (root.enabled) sfxSwitchOn.play();
    }
    function playSwitchOn() { switchOn(); }

    function switchOff() {
        if (root.enabled) sfxSwitchOff.play();
    }
    function playSwitchOff() { switchOff(); }

    function tab() {
        if (root.enabled) sfxTab.play();
    }
    function playTab() { tab(); }

    function sliderUp() {
        if (root.enabled) sfxSliderUp.play();
    }
    function playSliderUp() { sliderUp(); }

    function sliderDown() {
        if (root.enabled) sfxSliderDown.play();
    }
    function playSliderDown() { sliderDown(); }

    function toast() {
        if (root.enabled) sfxToast.play();
    }
    function playToast() { toast(); }

    function achievement() {
        if (root.enabled) sfxAchievement.play();
    }
    function playAchievement() { achievement(); }
}
