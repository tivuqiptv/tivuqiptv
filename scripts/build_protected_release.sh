#!/bin/sh
set -eu

: "${LICENSE_API_BASE_URL:?LICENSE_API_BASE_URL is required}"
: "${ACTIVATION_URL:?ACTIVATION_URL is required}"
: "${PHONE_APP_DOWNLOAD_URL:?PHONE_APP_DOWNLOAD_URL is required}"
: "${LICENSE_SERVER_PUBLIC_KEY:?LICENSE_SERVER_PUBLIC_KEY is required}"
: "${OFFICIAL_SIGNING_CERT_SHA256:?Amazon Appstore signing certificate SHA-256 is required}"
amazon_appstore_build="${AMAZON_APPSTORE_BUILD:-true}"
case "$amazon_appstore_build" in
  true|false) ;;
  *) echo "AMAZON_APPSTORE_BUILD must be true or false." >&2; exit 1 ;;
esac

if [ ! -f android/key.properties ]; then
  echo "Protected release refused: android/key.properties is missing." >&2
  echo "Create the permanent TIVUQIPTV signing key before commercial distribution." >&2
  exit 1
fi

store_file=$(sed -n 's/^storeFile=//p' android/key.properties | tail -n 1)
if [ -z "$store_file" ] || [ ! -f "android/$store_file" ]; then
  echo "Protected release refused: configured signing keystore was not found." >&2
  exit 1
fi

case "$LICENSE_API_BASE_URL" in
  https://*) ;;
  *) echo "Protected release requires an HTTPS license server." >&2; exit 1 ;;
esac

case "$ACTIVATION_URL" in
  https://*) ;;
  *) echo "Protected release requires an HTTPS activation URL." >&2; exit 1 ;;
esac

case "$PHONE_APP_DOWNLOAD_URL" in
  https://*) ;;
  *) echo "Protected release requires an HTTPS phone app download URL." >&2; exit 1 ;;
esac

flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/protected-symbols \
  --dart-define=LICENSE_API_BASE_URL="$LICENSE_API_BASE_URL" \
  --dart-define=ACTIVATION_URL="$ACTIVATION_URL" \
  --dart-define=PHONE_APP_DOWNLOAD_URL="$PHONE_APP_DOWNLOAD_URL" \
  --dart-define=LICENSE_SERVER_PUBLIC_KEY="$LICENSE_SERVER_PUBLIC_KEY" \
  --dart-define=OFFICIAL_SIGNING_CERT_SHA256="$OFFICIAL_SIGNING_CERT_SHA256" \
  --dart-define=AMAZON_APPSTORE_BUILD="$amazon_appstore_build" \
  --dart-define=ENFORCE_SERVER_LICENSE=true

echo "Protected APK: build/app/outputs/flutter-apk/app-release.apk"
echo "Keep build/protected-symbols in a private backup for crash decoding."
