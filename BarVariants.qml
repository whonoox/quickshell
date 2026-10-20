import Quickshell
import Quickshell.Hyprland
import QtQuick

Variants {
    id: root

    // When true, targets only the primary display (screen 0)
    // Used by: BluetoothBar, WifiBar, NotificationPanel
    property bool primaryOnly: false
    property alias onlyPrimary: root.primaryOnly

    // When true, targets all detected displays (e.g. RoundedOverlay)
    property bool allScreens: false
    property alias everyScreen: root.allScreens

    // Reactively track the active monitor name from Hyprland
    readonly property string activeMonName: {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name) {
            return Hyprland.focusedMonitor.name
        }
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.monitor && Hyprland.focusedWorkspace.monitor.name) {
            return Hyprland.focusedWorkspace.monitor.name
        }
        return ""
    }

    readonly property var activeScreen: {
        var screens = Quickshell.screens
        if (!screens || screens.length === 0) return null
        if (screens.length === 1) return screens[0]

        var targetName = root.activeMonName
        if (targetName) {
            for (var i = 0; i < screens.length; i++) {
                if (screens[i].name === targetName) {
                    return screens[i]
                }
            }
        }
        return screens[0]
    }

    model: {
        var screens = Quickshell.screens
        if (!screens || screens.length === 0) return []
        if (root.allScreens) {
            return screens
        }
        if (root.primaryOnly) {
            return [screens[0]]
        }
        // Default: display ONLY on the active workspace / focused monitor
        return root.activeScreen ? [root.activeScreen] : [screens[0]]
    }
}
