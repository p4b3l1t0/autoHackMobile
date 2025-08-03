#!/usr/bin/env bash
# By P4b3l1t0
set -euo pipefail

# 1. Detectar arquitectura y versión de Frida CLI
ARCH=$(adb shell getprop ro.product.cpu.abilist | tr ',' '\n' | head -n1)
FRIDA_VER=$(frida --version 2>/dev/null || true)
if [ -z "$FRIDA_VER" ]; then
  echo "Error: no encontré frida en tu sistema. Instalá con: pip install frida-tools --break-system-packages" >&2
  exit 1
fi

echo "[*] frida version: $FRIDA_VER, CPU arch: $ARCH"

# 2. Instalar frida-tools (por si faltan dependencias)
pip3 install --user frida-tools --break-system-packages 2>/dev/null || pip install --user frida-tools --break-system-packages

# 3. Descargar frida-server apropiado
DL="https://github.com/frida/frida/releases/download/${FRIDA_VER}/frida-server-${FRIDA_VER}-android-${ARCH}.xz"
echo "[*] Descargando frida-server desde $DL ..."
curl -sSL "$DL" | unxz > frida-server
chmod +x frida-server

# 4. Push al dispositivo/emulador
adb root &>/dev/null || echo "[!] No es un emulador root"
adb wait-for-device
adb push frida-server /data/local/tmp/frida-server
adb shell "chmod 755 /data/local/tmp/frida-server"

# 5. Lanzar frida-server sin colgarse
echo "[*] Iniciando frida-server..."
adb shell "nohup /data/local/tmp/frida-server >/dev/null 2>&1 & exit"
sleep 1

if frida-ps -U >/dev/null 2>&1; then
  echo "[✔] frida-server corriendo correctamente"
else
  echo "[✘] No se pudo conectar a frida-server" >&2
  exit 2
fi

# 6. Descargar certificado Burp Suite automáticamente
CERT_DER="Burp.der"
CERT_PEM="Burp.pem"

echo "[*] Descargando certificado CA desde Burp Suite..."
if ! curl -sSf http://127.0.0.1:8080/cert -o "$CERT_DER"; then
  echo "[✘] No se pudo descargar el certificado desde Burp. Asegurate de que Burp Suite esté corriendo y el proxy activo." >&2
  exit 3
fi

# 7. Convertir y calcular hash
openssl x509 -inform DER -in "$CERT_DER" -out "$CERT_PEM"
HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_PEM" | head -n1)
CERT_HASH="${HASH}.0"

echo "[*] Renombrando certificado a $CERT_HASH"
cp "$CERT_PEM" "$CERT_HASH"

# 8. Instalar certificado en Android
adb push "$CERT_HASH" /data/local/tmp/
adb shell <<EOF
mount -o rw,remount /
cp /data/local/tmp/$CERT_HASH /system/etc/security/cacerts/
chmod 644 /system/etc/security/cacerts/$CERT_HASH
EOF
echo "[✔] Certificado Burp instalado como certificado del sistema"

# 9. Configurar proxy en Android para Burp
echo "[*] Configurando proxy HTTP en Android para Burp..."
adb shell settings put global http_proxy "127.0.0.1:8080"
adb reverse tcp:8080 tcp:8080
echo "[✔] Proxy configurado: 127.0.0.1:8080 (redirigido a Burp Suite)"

echo "✅ Todo configurado. Ya podés interceptar tráfico HTTPS y usar Frida sin configuraciones extra."
