#!/bin/bash
# Builds the watch face: ./build.sh [probe] [simulate|install|log-on|log]
#   probe     builds the feasibility probe (meditation detection and particle frame rates) instead of the face
#   simulate  also runs it in the Connect IQ simulator
#   install   also copies it to a watch connected by USB in MTP mode
#   log-on    turns on the face's log on a connected watch (frame rates after each wrist raise)
#   log       prints that log
set -euo pipefail

cd "$(dirname "$0")"
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
SDK="${SDK%/}"
DEVICE="fenix947mm"
KEY="$HOME/.garmin/developer_key.der"

JUNGLE="monkey.jungle"
PRG="bin/Anicca.prg"
if [[ "${1:-}" == "probe" ]]; then
    JUNGLE="probe.jungle"
    PRG="bin/AniccaProbe.prg"
    shift
fi

mkdir -p bin
"$SDK/bin/monkeyc" -f "$JUNGLE" -d "$DEVICE" -y "$KEY" -o "$PRG" -w

if [[ "${1:-}" == "install" || "${1:-}" == "log-on" || "${1:-}" == "log" ]]; then
    case "$1" in
        install) ARGS=("$PRG") ;;
        log-on) ARGS=(--log-on "$(basename "$PRG" .prg | tr '[:lower:]' '[:upper:]')") ;;
        log) ARGS=(--log-read "$(basename "$PRG" .prg | tr '[:lower:]' '[:upper:]')" bin/watch.log) ;;
    esac
    LIBMTP="$(brew --prefix libmtp)"
    if [[ ! -x bin/mtp_install || tools/mtp_install.c -nt bin/mtp_install ]]; then
        clang -o bin/mtp_install tools/mtp_install.c -I"$LIBMTP/include" -L"$LIBMTP/lib" -lmtp
    fi
    # macOS camera services grab MTP devices and restart on their own, so stop them right before each attempt
    for attempt in 1 2 3 4 5; do
        pkill -x icdd || true
        pkill -x ptpcamerad || true
        pkill -x mscamerad-xpc || true
        if bin/mtp_install "${ARGS[@]}"; then
            [[ "$1" == "log" ]] && cat bin/watch.log
            exit 0
        fi
        sleep 2
    done
    exit 1
fi

if [[ "${1:-}" == "simulate" ]]; then
    pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" >/dev/null || { "$SDK/bin/connectiq" & sleep 5; }
    "$SDK/bin/monkeydo" "$PRG" "$DEVICE"
fi
