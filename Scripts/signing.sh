#!/usr/bin/env bash
# Manages Glazer's code signing identity.
#
# Without an Apple Developer ID, Glazer is signed ad hoc, and macOS then treats every
# build as a different app: it asks again for the face lock Keychain item and forgets the
# camera and Accessibility permissions. Signing every build with the same self-signed
# certificate gives Glazer a stable identity (its designated requirement becomes "this
# bundle ID, signed by this certificate"), so macOS recognises updates as the same app.
#
# Usage:
#   Scripts/signing.sh create DIR
#       Creates a new identity in DIR: Glazer-Signing.p12, its password, and the
#       certificate's SHA-1 fingerprint. Keep the .p12 and password secret. Then:
#         - to sign releases, add them as GitHub secrets (the script prints the commands);
#         - to sign builds on your Mac, run `Scripts/signing.sh install DIR`.
#
#   Scripts/signing.sh install DIR
#       Imports the identity into its own keychain on this Mac, and records it in
#       ~/.config/glazer/signing.env, which Scripts/bundle.sh reads.
#
#   Scripts/signing.sh import-ci
#       For CI: imports the identity from the SIGNING_P12 (base64) and
#       SIGNING_P12_PASSWORD environment variables into a temporary keychain, and prints
#       the variables Scripts/bundle.sh needs, in the form `NAME=value`.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly common_name="Glazer Signing"
readonly config_dir="$HOME/.config/glazer"
readonly local_keychain="$HOME/Library/Keychains/glazer-signing.keychain-db"

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
}

# Writes a password-protected .p12 that macOS's security tool can read. Newer OpenSSL
# defaults to algorithms the Keychain can't import, so the legacy ones are named.
create() {
    local directory=${1:?Usage: Scripts/signing.sh create DIR}
    mkdir -p "$directory"
    chmod 700 "$directory"
    [[ ! -e "$directory/Glazer-Signing.p12" ]] || {
        echo "$directory/Glazer-Signing.p12 already exists. Use a new folder." >&2
        exit 73
    }

    local workspace
    workspace=$(mktemp -d)
    trap 'rm -rf "$workspace"' RETURN

    cat >"$workspace/certificate.cnf" <<EOF
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = $common_name
O = Glazer
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

    local password
    password=$(openssl rand -base64 24)
    openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
        -keyout "$workspace/key.pem" -out "$workspace/certificate.pem" \
        -config "$workspace/certificate.cnf" 2>/dev/null
    openssl pkcs12 -export -inkey "$workspace/key.pem" -in "$workspace/certificate.pem" \
        -name "$common_name" -passout "pass:$password" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -out "$directory/Glazer-Signing.p12"

    printf '%s\n' "$password" >"$directory/Glazer-Signing.password"
    openssl x509 -in "$workspace/certificate.pem" -noout -fingerprint -sha1 |
        sed 's/.*=//; s/://g' >"$directory/Glazer-Signing.sha1"
    chmod 600 "$directory"/Glazer-Signing.*

    cat <<EOF
Created a signing identity in $directory:
  Glazer-Signing.p12        the certificate and private key (secret)
  Glazer-Signing.password   its password (secret)
  Glazer-Signing.sha1       the certificate fingerprint: $(cat "$directory/Glazer-Signing.sha1")

To sign releases, add the identity to the repository's GitHub secrets:
  base64 -i "$directory/Glazer-Signing.p12" | gh secret set SIGNING_P12
  gh secret set SIGNING_P12_PASSWORD < "$directory/Glazer-Signing.password"

To sign builds on this Mac:
  Scripts/signing.sh install "$directory"

Keep the folder somewhere safe and private. Anyone with the .p12 and password can sign
apps that macOS treats as Glazer.
EOF
}

install_local() {
    local directory=${1:?Usage: Scripts/signing.sh install DIR}
    local p12="$directory/Glazer-Signing.p12"
    [[ -f "$p12" ]] || { echo "No identity in $directory. Run: Scripts/signing.sh create DIR" >&2; exit 66; }

    local keychain_password
    keychain_password=$(openssl rand -base64 24)
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    if [[ -e "$local_keychain" ]]; then
        security delete-keychain "$local_keychain"
    fi
    security create-keychain -p "$keychain_password" "$local_keychain"
    security set-keychain-settings "$local_keychain" # No automatic locking.
    security unlock-keychain -p "$keychain_password" "$local_keychain"
    security import "$p12" -k "$local_keychain" -P "$(cat "$directory/Glazer-Signing.password")" \
        -T /usr/bin/codesign >/dev/null
    # Let codesign use the key without asking each time.
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$local_keychain" >/dev/null

    add_to_search_list "$local_keychain"

    cat >"$config_dir/signing.env" <<EOF
# Written by Scripts/signing.sh install. Read by Scripts/bundle.sh.
GLAZER_SIGNING_IDENTITY=$(cat "$directory/Glazer-Signing.sha1")
GLAZER_SIGNING_KEYCHAIN=$local_keychain
GLAZER_SIGNING_KEYCHAIN_PASSWORD=$keychain_password
EOF
    chmod 600 "$config_dir/signing.env"
    echo "Builds on this Mac are now signed as $common_name ($(cat "$directory/Glazer-Signing.sha1"))."
}

import_ci() {
    : "${SIGNING_P12:?SIGNING_P12 is not set}" "${SIGNING_P12_PASSWORD:?SIGNING_P12_PASSWORD is not set}"
    local directory keychain keychain_password identity
    directory=$(mktemp -d)
    keychain="$directory/signing.keychain-db"
    keychain_password=$(openssl rand -base64 24)

    printf '%s' "$SIGNING_P12" | base64 --decode >"$directory/identity.p12"
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$directory/identity.p12" -k "$keychain" -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
    rm -f "$directory/identity.p12"
    add_to_search_list "$keychain"

    identity=$(security find-identity -p codesigning "$keychain" | awk '/"'"$common_name"'"/ { print $2; exit }')
    [[ -n "$identity" ]] || { echo "The identity didn't import." >&2; exit 65; }

    echo "GLAZER_SIGNING_IDENTITY=$identity"
    echo "GLAZER_SIGNING_KEYCHAIN=$keychain"
    echo "GLAZER_SIGNING_KEYCHAIN_PASSWORD=$keychain_password"
}

# codesign only finds identities in keychains on the user's search list.
add_to_search_list() {
    local keychain=$1 existing
    existing=$(security list-keychains -d user | tr -d '"' | sed 's/^ *//')
    if ! grep -qxF "$keychain" <<<"$existing"; then
        # shellcheck disable=SC2086 # One keychain path per line, none with spaces.
        security list-keychains -d user -s $existing "$keychain"
    fi
}

case "${1:-}" in
    create) create "${2:-}" ;;
    install) install_local "${2:-}" ;;
    import-ci) import_ci ;;
    *) usage ;;
esac
