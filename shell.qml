//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
import Quickshell
import QtQuick

Scope {
    FontLoader {
        source: Quickshell.shellPath("fonts/Nuuxfont-Regular.ttf")
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
}
