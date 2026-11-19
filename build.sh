#!/usr/bin/env bash
# Build the data field.
#
#   ./build.sh              -> build for fenix7pro (bin/SunsetField.prg)
#   DEVICE=fenix7xpro ./build.sh
#   ./build.sh --iq         -> export a signed .iq package (all products)
#
set -euo pipefail
cd "$(dirname "$0")"

# Resolve the Connect IQ SDK: honour $CONNECTIQ_SDK, otherwise use the SDK
# currently selected in the SDK Manager (~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg).
if [[ -n "${CONNECTIQ_SDK:-}" ]]; then
    SDK="$CONNECTIQ_SDK"
elif [[ -f "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg" ]]; then
    SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
else
    SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"connectiq-sdk-mac-* 2>/dev/null | tail -1)"
fi
SDK="${SDK%/}"

if [[ ! -x "$SDK/bin/monkeyc" ]]; then
    echo "Connect IQ SDK not found. Set CONNECTIQ_SDK to the SDK folder." >&2
    exit 1
fi

DEVICE="${DEVICE:-fenix7pro}"
KEY="${KEY:-developer_key.der}"

if [[ ! -f "$KEY" ]]; then
    echo "Developer key '$KEY' not found."
    echo "Generate one with:"
    echo "  openssl genrsa -out developer_key.pem 4096"
    echo "  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt"
    exit 1
fi

mkdir -p bin

if [[ "${1:-}" == "--iq" ]]; then
    echo "Exporting signed .iq package (all products)..."
    "$SDK/bin/monkeyc" -f monkey.jungle -o bin/SunsetField.iq -y "$KEY" -e -r
    echo "Done: bin/SunsetField.iq"
else
    echo "Building for $DEVICE..."
    "$SDK/bin/monkeyc" -f monkey.jungle -o bin/SunsetField.prg -d "$DEVICE" -y "$KEY" -w
    echo "Done: bin/SunsetField.prg"
fi
