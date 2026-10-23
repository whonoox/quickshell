//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    // The theme reaches Omarchy's stock shell over IPC. This shell is a
    // separate Quickshell instance, so it has to expose the same
    // interface to be told about a theme change.
    //
    // Watching the theme files is not enough: omarchy-theme-set replaces
    // the whole theme directory (rm -rf, then mv), which destroys the
    // inode a file watch is attached to. The theme arrives over IPC
    // instead, which is exact and immediate.
    IpcHandler {
        target: "shell"

        function ping(): string {
            return "ok"
        }

        function applyTheme(colorsB64: string, shellB64: string): string {
            var colorsRaw = ""
            try {
                colorsRaw = Qt.atob(String(colorsB64 || ""))
            } catch (e) {
                colorsRaw = ""
            }

            if (colorsRaw) {
                Theme.loadColors(colorsRaw)
            }

            return "ok"
        }
    }

    WorkspaceBar{}
    TimeBar{}
    BatteryBar{}
    AudioBar{}
    BrightnessBar{}
    WifiBar{}
    BluetoothBar{}
    RoundedOverlay{}
    OmarchyMenu{}
    NotificationPanel{}
    ScoopTestPanel{}
    WallpaperPicker{}
    ThemePicker{}
    ToggleBar{}
}
