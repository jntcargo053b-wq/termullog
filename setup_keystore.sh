#!/bin/bash
# setup_keystore.sh — jalankan dari root project termullog
set -e

KEYSTORE_PATH="android/app/keystore.jks"
ALIAS="upload"

echo "=== TermulLog Keystore Setup ==="
echo ""

# Cek apakah keystore sudah ada
if [ -f "$KEYSTORE_PATH" ]; then
  echo "✓ Keystore sudah ada di $KEYSTORE_PATH"
  echo "  Skip pembuatan, langsung encode..."
else
  echo "Masukkan password untuk keystore (minimal 6 karakter):"
  read -s STORE_PASS
  echo "Konfirmasi password:"
  read -s STORE_PASS2
  if [ "$STORE_PASS" != "$STORE_PASS2" ]; then
    echo "❌ Password tidak cocok"
    exit 1
  fi

  echo ""
  echo "Membuat keystore baru..."
  keytool -genkey -v \
    -keystore "$KEYSTORE_PATH" \
    -alias "$ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass "$STORE_PASS" \
    -keypass "$STORE_PASS" \
    -dname "CN=TermulLog, O=Dev, L=Malang, S=EastJava, C=ID" \
    -noprompt

  echo "✓ Keystore dibuat: $KEYSTORE_PATH"
fi

echo ""
echo "=== Encode keystore ke Base64 ==="
B64=$(base64 -w 0 "$KEYSTORE_PATH")
echo ""
echo "Salin nilai berikut ke GitHub Secret KEYSTORE_BASE64:"
echo "-------------------------------------------------------"
echo "$B64"
echo "-------------------------------------------------------"
echo ""
echo "=== Langkah selanjutnya ==="
echo "Buka: https://github.com/YOUR_USERNAME/termullog/settings/secrets/actions"
echo ""
echo "Set 4 secrets berikut:"
echo "  KEYSTORE_BASE64    → output base64 di atas"
echo "  KEY_STORE_PASSWORD → password yang kamu masukkan tadi"
echo "  KEY_ALIAS          → upload"
echo "  KEY_PASSWORD       → password yang sama"
echo ""
echo "=== Tambahkan ke .gitignore ==="
if grep -q "keystore.jks" .gitignore 2>/dev/null; then
  echo "✓ keystore.jks sudah ada di .gitignore"
else
  echo "android/app/keystore.jks" >> .gitignore
  echo "android/key.properties" >> .gitignore
  echo "✓ Ditambahkan ke .gitignore"
fi

echo ""
echo "✅ Selesai! Commit .gitignore, lalu push ke main."
