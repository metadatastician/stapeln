#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# @a2ml-metadata begin
# (
#   id                   = "stapeln-launcher"
#   type                 = "launcher"
#   version              = "1.0.0"
#   app-name             = "stapeln"
#   app-display          = "Stapeln"
#   app-url              = "http://localhost:4010"
#   standards-compliance = [
#     "launcher-standard.adoc"
#     "LM-LA-LIFECYCLE-STANDARD.adoc"
#     "cross-platform-system-integration-modes"
#   ]
#   modes = [
#     "--start"
#     "--stop"
#     "--status"
#     "--auto"
#     "--browser"
#     "--integ"
#     "--disinteg"
#     "--help"
#   ]
#   platforms = [
#     "linux"
#     "macos"
#     "windows"
#   ]
#   lifecycle-phases-covered = [
#     "install"
#     "run"
#     "stop"
#     "status"
#     "uninstall"
#   ]
#   lifecycle-phases-deferred = [
#     "warmup"
#     "configure"
#     "personalize"
#     "update"
#     "repair"
#   ]
#   desktop-file-permissions = 444
#   integrity-verification   = "verify-desktop-integrity.sh"
# )
# @a2ml-metadata end
#
# ============================================================================
# stapeln-launcher.sh — Cross-platform launcher for Stapeln
# ============================================================================
#
# Implements:
#   • Comprehensive Launcher Standard (launcher-standard.adoc)
#   • LM/LA Lifecycle Standard (LM-LA-LIFECYCLE-STANDARD.adoc)
#   • System Integration Modes (--integ / --disinteg)
#
# Cross-platform support:
#   • Linux       (primary; tested on Fedora 43 Atomic)
#   • macOS       (native bash works; uses ~/Applications + ~/Desktop)
#   • Windows     (via Git Bash or WSL; uses Start Menu + Desktop shortcuts)
#
# Usage:
#   stapeln-launcher.sh [--auto|--start|--stop|--status|--browser|--integ|--disinteg|--help]
#
# Quick reference:
#   (no args)      — --auto (start server, open browser)
#   --start        — start the server only (no browser)
#   --stop         — stop the running server
#   --status       — show current status (running/stopped, URL if applicable)
#   --browser      — open the browser (assumes server already running)
#   --auto         — start + open browser (default)
#   --integ        — install desktop entry + Start Menu entry + Desktop shortcut
#   --disinteg     — remove everything --integ installed (clean uninstall)
#   --help         — print this help text
#
# Design notes:
#   • --integ is idempotent: running it twice is fine.
#   • --disinteg is idempotent: running it on a system that was never
#     integrated is a no-op with a friendly message.
#   • --integ uses --force to reinstall; without --force, it detects an
#     existing integration and asks before overwriting.
#
# Soft-attach integrations (all optional — work fine without):
#   • feedback-o-tron — error reporting
#   • hypatia         — LLM-assisted troubleshooting on failure
#   • panic-attack    — pre-flight checks
#
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------------------------

APP_NAME="stapeln"
APP_DISPLAY="Stapeln"
APP_DESC="Visual Container Stack Designer — containers for people who hate containers"
APP_CATEGORIES="Development;System;Utility;"

# Repository layout
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Runtime configuration
APP_PORT="4010"
URL="http://localhost:${APP_PORT}"
PID_FILE="/tmp/${APP_NAME}-server.pid"
LOG_FILE="/tmp/${APP_NAME}-server.log"

# Integration configuration
ICON_SOURCE="$REPO_DIR/assets/icon-256.png"
DESKTOP_FILE_SOURCE="$REPO_DIR/${APP_NAME}.desktop"

# Startup command: prefer scripts/run.sh, fall back to dev.sh, error if neither
if [ -x "$REPO_DIR/scripts/run.sh" ]; then
    START_COMMAND="$REPO_DIR/scripts/run.sh"
elif [ -x "$REPO_DIR/dev.sh" ]; then
    START_COMMAND="$REPO_DIR/dev.sh"
else
    START_COMMAND=""
fi

MODE="${1:---auto}"
FORCE="false"
[[ "${2:-}" == "--force" ]] && FORCE="true"

# ----------------------------------------------------------------------------
# LOGGING HELPERS
# ----------------------------------------------------------------------------

log()  { echo -e "\033[0;32m[$APP_DISPLAY]\033[0m $1"; }
warn() { echo -e "\033[0;33m[$APP_DISPLAY]\033[0m $1" >&2; }
err()  { echo -e "\033[0;31m[$APP_DISPLAY]\033[0m ERROR: $1" >&2; }

# Detect whether we're running in a GUI context with no visible terminal.
# True when stderr is not a tty AND a display server is available.
is_gui_context() {
    [ ! -t 2 ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }
}

# gui_error: show an error dialog the user can actually see.
# Prefers kdialog → zenity → notify-send → xmessage → stderr.
# Always also prints to stderr so CLI users see it too.
gui_error() {
    local title="$1"
    local body="$2"

    err "$title"
    # shellcheck disable=SC2001
    echo "$body" | sed 's/^/  /' >&2

    if is_gui_context; then
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title "$APP_DISPLAY: $title" --error "$body" 2>/dev/null &
        elif command -v zenity >/dev/null 2>&1; then
            zenity --error --title="$APP_DISPLAY: $title" --text="$body" --width=500 2>/dev/null &
        elif command -v notify-send >/dev/null 2>&1; then
            notify-send --urgency=critical --icon=dialog-error "$APP_DISPLAY: $title" "$body" 2>/dev/null &
        elif command -v xmessage >/dev/null 2>&1; then
            xmessage -center "$APP_DISPLAY: $title\n\n$body" 2>/dev/null &
        fi
    fi
}

# gui_info: same mechanism for informational messages (friendly, not errors).
gui_info() {
    local title="$1"
    local body="$2"

    log "$title"
    echo "$body" | sed 's/^/  /'

    if is_gui_context; then
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title "$APP_DISPLAY: $title" --msgbox "$body" 2>/dev/null &
        elif command -v zenity >/dev/null 2>&1; then
            zenity --info --title="$APP_DISPLAY: $title" --text="$body" --width=500 2>/dev/null &
        elif command -v notify-send >/dev/null 2>&1; then
            notify-send --icon=dialog-information "$APP_DISPLAY: $title" "$body" 2>/dev/null &
        elif command -v xmessage >/dev/null 2>&1; then
            xmessage -center "$APP_DISPLAY: $title\n\n$body" 2>/dev/null &
        fi
    fi
}

# ----------------------------------------------------------------------------
# PLATFORM DETECTION
# ----------------------------------------------------------------------------

detect_platform() {
    case "$(uname -s)" in
        Linux*)                                 echo "linux"   ;;
        Darwin*)                                echo "macos"   ;;
        CYGWIN*|MINGW*|MSYS*|Windows_NT)        echo "windows" ;;
        *)                                      echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"

# ----------------------------------------------------------------------------
# PLATFORM-SPECIFIC INTEGRATION PATHS
# ----------------------------------------------------------------------------
#
# Populate these as globals, then the integ/disinteg routines can act on
# them uniformly without reimplementing per-platform logic.

case "$PLATFORM" in
    linux)
        APPS_DIR="$HOME/.local/share/applications"
        ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
        DESKTOP_SHORTCUT_DIR="$HOME/Desktop"
        BIN_DIR="$HOME/.local/bin"
        DESKTOP_FILE_TARGET="$APPS_DIR/${APP_NAME}.desktop"
        DESKTOP_SHORTCUT_TARGET="$DESKTOP_SHORTCUT_DIR/${APP_NAME}.desktop"
        ICON_TARGET="$ICON_DIR/${APP_NAME}.png"
        LAUNCHER_TARGET="$BIN_DIR/${APP_NAME}-launcher"
        ;;
    macos)
        APPS_DIR="$HOME/Applications"
        DESKTOP_SHORTCUT_DIR="$HOME/Desktop"
        BIN_DIR="$HOME/.local/bin"
        DESKTOP_FILE_TARGET="$APPS_DIR/${APP_DISPLAY}.app"
        DESKTOP_SHORTCUT_TARGET="$DESKTOP_SHORTCUT_DIR/${APP_DISPLAY}.command"
        ICON_TARGET="$APPS_DIR/${APP_DISPLAY}.app/Contents/Resources/icon.png"
        LAUNCHER_TARGET="$BIN_DIR/${APP_NAME}-launcher"
        ;;
    windows)
        # Under Git Bash / WSL, $APPDATA is usually translated correctly.
        # Fall back sanely if not.
        APPDATA_DIR="${APPDATA:-$HOME/AppData/Roaming}"
        START_MENU_DIR="$APPDATA_DIR/Microsoft/Windows/Start Menu/Programs"
        DESKTOP_SHORTCUT_DIR="$HOME/Desktop"
        BIN_DIR="$HOME/.local/bin"
        DESKTOP_FILE_TARGET="$START_MENU_DIR/${APP_DISPLAY}.lnk"
        DESKTOP_SHORTCUT_TARGET="$DESKTOP_SHORTCUT_DIR/${APP_DISPLAY}.lnk"
        ICON_TARGET="$BIN_DIR/${APP_NAME}.ico"
        LAUNCHER_TARGET="$BIN_DIR/${APP_NAME}-launcher.sh"
        ;;
    *)
        APPS_DIR=""
        DESKTOP_SHORTCUT_DIR=""
        BIN_DIR="$HOME/.local/bin"
        DESKTOP_FILE_TARGET=""
        DESKTOP_SHORTCUT_TARGET=""
        ICON_TARGET=""
        LAUNCHER_TARGET="$BIN_DIR/${APP_NAME}-launcher"
        ;;
esac

# ----------------------------------------------------------------------------
# PROCESS MANAGEMENT (per launcher-standard.adoc §Process Management)
# ----------------------------------------------------------------------------

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

wait_for_url() {
    local max_wait=${1:-15}
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if command -v curl >/dev/null 2>&1 && curl -fsS "$URL" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

start_server() {
    if is_running; then
        log "Server already running (PID $(cat "$PID_FILE"))"
        return 0
    fi

    if [ -z "$START_COMMAND" ]; then
        gui_error "No startup command found" \
"Stapeln is installed, but I don't know how to start it yet.

Expected one of these files to exist and be executable:
  • $REPO_DIR/scripts/run.sh
  • $REPO_DIR/dev.sh

Neither is present. Create scripts/run.sh with your frontend + backend
startup sequence, then double-click this launcher again.

For now, you can open the repo at:
  $REPO_DIR"
        return 1
    fi

    log "Starting $APP_DISPLAY..."
    cd "$REPO_DIR"
    nohup "$START_COMMAND" >"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    if ! wait_for_url 15; then
        gui_error "Server did not start" \
"$APP_DISPLAY did not become reachable at $URL within 15 seconds.

Check the log file:
  tail -50 $LOG_FILE

Things to try:
  1. Is port $APP_PORT already in use?   ss -tlnp | grep $APP_PORT
  2. Can you reach it manually?          curl -v $URL
  3. Is the startup command runnable?    $START_COMMAND

If hypatia is installed, you can get assisted diagnosis with:
  hypatia diagnose --app $APP_NAME --log $LOG_FILE"

        if command -v feedback-o-tron >/dev/null 2>&1; then
            feedback-o-tron --event "launcher:start_failed" \
                --app "$APP_NAME" --url "$URL" --log "$LOG_FILE" \
                --error "Timeout after 15 seconds" 2>/dev/null || true
        fi
        return 1
    fi

    log "Server started (PID $(cat "$PID_FILE")) — $URL"
    return 0
}

stop_server() {
    if ! is_running; then
        log "No running server found"
        return 0
    fi
    log "Stopping $APP_DISPLAY..."
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    log "Stopped"
}

open_browser() {
    if ! is_running; then
        err "Server is not running — use --start or --auto first"
        return 1
    fi
    log "Opening $URL..."
    case "$PLATFORM" in
        linux)
            if command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" &
            elif command -v firefox >/dev/null 2>&1;  then firefox "$URL" &
            elif command -v chromium >/dev/null 2>&1; then chromium "$URL" &
            else warn "No browser found — open manually: $URL"; fi ;;
        macos)
            open "$URL" 2>/dev/null || warn "Could not open browser — open manually: $URL" ;;
        windows)
            if command -v start >/dev/null 2>&1; then start "$URL"
            elif command -v cygstart >/dev/null 2>&1; then cygstart "$URL"
            else warn "Could not open browser — open manually: $URL"; fi ;;
        *)
            warn "Unknown platform — open manually: $URL" ;;
    esac
}

# ----------------------------------------------------------------------------
# SYSTEM INTEGRATION — --integ
# ----------------------------------------------------------------------------

already_integrated() {
    [ -f "$DESKTOP_FILE_TARGET" ] || \
    [ -f "$LAUNCHER_TARGET" ]
}

write_linux_desktop_file() {
    local target="$1"
    # Use the custom icon if --integ installed one; otherwise fall back to a
    # freedesktop named icon that every standard icon theme provides, so the
    # user gets *some* recognisable icon instead of a blank text-file glyph.
    # 'package-x-generic' tends to render as a box/parcel — closer to the
    # "containers stacked up" metaphor than 'applications-development' which
    # most themes draw as a hammer or wrench.
    local icon_name
    if [ -f "$ICON_TARGET" ]; then
        icon_name="$APP_NAME"
    else
        icon_name="package-x-generic"
    fi

    cat > "$target" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_DISPLAY
GenericName=Container Stack Designer
Comment=$APP_DESC
Exec=$LAUNCHER_TARGET --auto
Icon=$icon_name
Terminal=false
Categories=$APP_CATEGORIES
StartupNotify=true
StartupWMClass=$APP_NAME
Actions=stop;status;

[Desktop Action stop]
Name=Stop Server
Exec=$LAUNCHER_TARGET --stop

[Desktop Action status]
Name=Server Status
Exec=$LAUNCHER_TARGET --status
EOF
    # Per LM-LA-LIFECYCLE-STANDARD §LM/LA-INSTALL: desktop files are 444
    # (read-only for all) so they can't be silently tampered with. To edit,
    # run `chmod +w` on the file first or re-run `--integ --force`.
    chmod 444 "$target"
}

write_macos_command_file() {
    local target="$1"
    cat > "$target" <<EOF
#!/usr/bin/env bash
exec "$LAUNCHER_TARGET" --auto
EOF
    chmod +x "$target"
}

do_integ_linux() {
    mkdir -p "$APPS_DIR" "$ICON_DIR" "$BIN_DIR" "$DESKTOP_SHORTCUT_DIR"

    # Install the launcher to a stable location on PATH
    cp "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$LAUNCHER_TARGET"
    chmod +x "$LAUNCHER_TARGET"
    log "  + launcher: $LAUNCHER_TARGET"

    # Install icon (optional — fallback to freedesktop named icon otherwise)
    if [ -f "$ICON_SOURCE" ]; then
        cp "$ICON_SOURCE" "$ICON_TARGET"
        log "  + icon:     $ICON_TARGET"
    else
        log "  · no custom icon at $ICON_SOURCE — using system fallback (package-x-generic)"
    fi

    # Install Start Menu entry
    write_linux_desktop_file "$DESKTOP_FILE_TARGET"
    log "  + menu:     $DESKTOP_FILE_TARGET"

    # Install Desktop shortcut
    # Deliberately NOT chmod +x on .desktop files — modern KDE/GNOME do not
    # require it and LM-LA-LIFECYCLE §INSTALL mandates 444 read-only for
    # tamper-resistance. The gio trust metadata below is what KDE actually
    # cares about.
    write_linux_desktop_file "$DESKTOP_SHORTCUT_TARGET"
    log "  + desktop:  $DESKTOP_SHORTCUT_TARGET"

    # Refresh the desktop database if available
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$APPS_DIR" 2>/dev/null || true

    # On KDE Plasma, mark the desktop file as trusted so it doesn't prompt
    # the user with a "this is an untrusted .desktop file" dialog on click.
    if command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP_FILE_TARGET" "metadata::trusted" true 2>/dev/null || true
        gio set "$DESKTOP_SHORTCUT_TARGET" "metadata::trusted" true 2>/dev/null || true
    fi

    # Integrity verification per LM-LA-LIFECYCLE §LM/LA-INSTALL: if
    # verify-desktop-integrity.sh is reachable, generate checksums so
    # tampering can be detected later. Soft-attach: silent skip if absent.
    if command -v verify-desktop-integrity.sh >/dev/null 2>&1; then
        verify-desktop-integrity.sh --generate 2>/dev/null \
            && log "  + integrity hashes generated" \
            || log "  · integrity hash generation failed (non-fatal)"
    elif [ -x "/var/mnt/eclipse/repos/.desktop-tools/verify-desktop-integrity.sh" ]; then
        /var/mnt/eclipse/repos/.desktop-tools/verify-desktop-integrity.sh --generate 2>/dev/null \
            && log "  + integrity hashes generated" \
            || log "  · integrity hash generation failed (non-fatal)"
    fi
}

do_integ_macos() {
    mkdir -p "$APPS_DIR" "$BIN_DIR" "$DESKTOP_SHORTCUT_DIR"

    # Install the launcher to PATH
    cp "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$LAUNCHER_TARGET"
    chmod +x "$LAUNCHER_TARGET"
    log "  + launcher: $LAUNCHER_TARGET"

    # Minimal .app bundle (not a full codesigned one — enough for Launchpad + Spotlight)
    local bundle="$DESKTOP_FILE_TARGET"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_DISPLAY</string>
    <key>CFBundleDisplayName</key><string>$APP_DISPLAY</string>
    <key>CFBundleIdentifier</key><string>org.hyperpolymath.$APP_NAME</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>icon</string>
</dict>
</plist>
EOF

    # Executable stub that runs the launcher
    cat > "$bundle/Contents/MacOS/$APP_NAME" <<EOF
#!/usr/bin/env bash
exec "$LAUNCHER_TARGET" --auto
EOF
    chmod +x "$bundle/Contents/MacOS/$APP_NAME"

    # Icon (macOS prefers .icns but png is tolerated for simple launchers)
    if [ -f "$ICON_SOURCE" ]; then
        cp "$ICON_SOURCE" "$ICON_TARGET"
        log "  + icon:     $ICON_TARGET"
    fi
    log "  + bundle:   $bundle"

    # Desktop .command file (macOS double-clickable)
    write_macos_command_file "$DESKTOP_SHORTCUT_TARGET"
    log "  + desktop:  $DESKTOP_SHORTCUT_TARGET"
}

do_integ_windows() {
    mkdir -p "$BIN_DIR" "$(dirname "$DESKTOP_FILE_TARGET")" "$DESKTOP_SHORTCUT_DIR"

    # Install the launcher
    cp "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$LAUNCHER_TARGET"
    chmod +x "$LAUNCHER_TARGET"
    log "  + launcher: $LAUNCHER_TARGET"

    # Real .lnk shortcuts require PowerShell or a compiled tool.
    # If PowerShell is reachable, use it. Otherwise drop a .bat shim.
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -NonInteractive -Command "
            \$ws = New-Object -ComObject WScript.Shell
            \$sc = \$ws.CreateShortcut('$DESKTOP_FILE_TARGET')
            \$sc.TargetPath = 'bash.exe'
            \$sc.Arguments = '$LAUNCHER_TARGET --auto'
            \$sc.Description = '$APP_DESC'
            \$sc.Save()
        " 2>/dev/null && log "  + start menu: $DESKTOP_FILE_TARGET"

        powershell.exe -NoProfile -NonInteractive -Command "
            \$ws = New-Object -ComObject WScript.Shell
            \$sc = \$ws.CreateShortcut('$DESKTOP_SHORTCUT_TARGET')
            \$sc.TargetPath = 'bash.exe'
            \$sc.Arguments = '$LAUNCHER_TARGET --auto'
            \$sc.Description = '$APP_DESC'
            \$sc.Save()
        " 2>/dev/null && log "  + desktop:    $DESKTOP_SHORTCUT_TARGET"
    else
        warn "PowerShell not reachable — writing .bat fallback shortcuts"
        local bat="${DESKTOP_FILE_TARGET%.lnk}.bat"
        cat > "$bat" <<EOF
@echo off
bash.exe "$LAUNCHER_TARGET" --auto
EOF
        log "  + start menu: $bat"

        local desk_bat="${DESKTOP_SHORTCUT_TARGET%.lnk}.bat"
        cat > "$desk_bat" <<EOF
@echo off
bash.exe "$LAUNCHER_TARGET" --auto
EOF
        log "  + desktop:    $desk_bat"
    fi
}

do_integ() {
    if already_integrated && [ "$FORCE" != "true" ]; then
        warn "$APP_DISPLAY is already integrated with the system."
        read -rp "Reinstall (overwrite existing)? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Nothing changed."
            return 0
        fi
    fi

    log "Integrating $APP_DISPLAY with the $PLATFORM desktop..."

    case "$PLATFORM" in
        linux)   do_integ_linux   ;;
        macos)   do_integ_macos   ;;
        windows) do_integ_windows ;;
        *)
            err "Unknown platform ($PLATFORM) — cannot integrate."
            err "Supported: linux, macos, windows (via Git Bash or WSL)."
            return 1
            ;;
    esac

    log "✓ $APP_DISPLAY is now in your Start Menu / Applications and on your Desktop."
    log "  Run it any time with: $LAUNCHER_TARGET"
    log "  Remove all of this with: $LAUNCHER_TARGET --disinteg"
}

# ----------------------------------------------------------------------------
# SYSTEM DIS-INTEGRATION — --disinteg
# ----------------------------------------------------------------------------

do_disinteg() {
    log "Removing $APP_DISPLAY system integration..."

    # Stop the server first if it's running
    if is_running; then
        log "  • stopping running server"
        stop_server
    fi

    local removed_anything="false"

    # Cross-platform: remove anything we know how to have created
    local targets=(
        "$DESKTOP_FILE_TARGET"
        "$DESKTOP_SHORTCUT_TARGET"
        "$ICON_TARGET"
        "$LAUNCHER_TARGET"
        "${DESKTOP_FILE_TARGET%.lnk}.bat"
        "${DESKTOP_SHORTCUT_TARGET%.lnk}.bat"
    )

    for t in "${targets[@]}"; do
        [ -z "$t" ] && continue
        if [ -e "$t" ] || [ -L "$t" ]; then
            if [ -d "$t" ]; then
                rm -rf "$t"
            else
                rm -f "$t"
            fi
            log "  - removed $t"
            removed_anything="true"
        fi
    done

    # Refresh the desktop database if we're on Linux
    if [ "$PLATFORM" = "linux" ] && command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    fi

    # Clean up runtime cruft
    rm -f "$PID_FILE"

    if [ "$removed_anything" = "true" ]; then
        log "✓ $APP_DISPLAY removed from your system."
        log "  Config in ~/.config/$APP_NAME/ and logs in /tmp/ left in place."
        log "  To remove those too: rm -rf ~/.config/$APP_NAME && rm -f $LOG_FILE"
    else
        log "Nothing to remove — $APP_DISPLAY was not integrated on this system."
    fi
}

# ----------------------------------------------------------------------------
# HELP
# ----------------------------------------------------------------------------

show_help() {
    cat <<EOF
$APP_DISPLAY launcher — $APP_DESC

Usage: $0 [MODE] [--force]

Runtime modes (from launcher-standard.adoc):
  --auto       Start server and open the browser (default if no mode given)
  --start      Start the server only (no browser)
  --stop       Stop the running server
  --status     Show running status and URL
  --browser    Open the browser (server must already be running)

System integration modes:
  --integ      Install into your Start Menu / Applications folder + Desktop
               Cross-platform: Linux (.desktop), macOS (.app + .command),
               Windows (Start Menu .lnk + Desktop .lnk, via PowerShell).
               Idempotent. Use '--integ --force' to reinstall without prompts.

  --disinteg   Remove everything --integ installed. Also stops the server.
               Leaves ~/.config/$APP_NAME/ and logs alone (so your settings
               survive a reinstall). Idempotent.

Misc:
  --help       This text

Files this launcher writes:
  PID file:    $PID_FILE
  Log file:    $LOG_FILE
  Launcher:    $LAUNCHER_TARGET           (after --integ)
  Menu entry:  $DESKTOP_FILE_TARGET       (after --integ)
  Desktop:     $DESKTOP_SHORTCUT_TARGET   (after --integ)
  Icon:        ${ICON_TARGET:-<none>}     (after --integ, if icon-256.png exists)

Detected platform: $PLATFORM
Detected repo:     $REPO_DIR

Compliance:
  • launcher-standard.adoc (comprehensive launcher template)
  • LM-LA-LIFECYCLE-STANDARD.adoc (installation + uninstallation)
  • Cross-platform LM-LA System Integration Modes (this launcher's own addition)
EOF
}

# ----------------------------------------------------------------------------
# MAIN SWITCH
# ----------------------------------------------------------------------------

case "$MODE" in
    --start)               start_server ;;
    --stop)                stop_server ;;
    --status)
        if is_running; then
            log "Server running (PID $(cat "$PID_FILE")) at $URL"
        else
            log "Server is not running"
        fi
        ;;
    --browser|--web)       open_browser ;;
    --auto)                start_server && open_browser ;;
    --integ)               do_integ ;;
    --disinteg)            do_disinteg ;;
    --help|-h)             show_help ;;
    *)
        err "Unknown mode: $MODE"
        err ""
        show_help
        exit 2
        ;;
esac
