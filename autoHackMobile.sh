#!/usr/bin/env bash
set -euo pipefail
echo "Para que el script funcione debes tener abierto BurpSuite y el Emulador al mismo tiempo"

FRIDA_VER="17.4.0"
CPU_ARCH=$(adb shell getprop ro.product.cpu.abilist | tr ',' '\n' | head -n1)

case "$CPU_ARCH" in
  "arm64-v8a") FRIDA_ARCH="android-arm64" ;;
  "armeabi-v7a" | "armeabi") FRIDA_ARCH="android-arm" ;;
  "x86") FRIDA_ARCH="android-x86" ;;
  "x86_64") FRIDA_ARCH="android-x86_64" ;;
  *) echo "ARQUITECTURA NO SOPORTADA: $CPU_ARCH" >&2; exit 1 ;;
esac

DL="https://github.com/frida/frida/releases/download/${FRIDA_VER}/frida-server-${FRIDA_VER}-${FRIDA_ARCH}.xz"
echo "[*] Descargando frida-server desde $DL ..."
curl -sSL "$DL" -o frida-server.xz

if ! file frida-server.xz | grep -q 'XZ compressed data'; then
  echo "[✘] Descarga errónea" >&2
  rm frida-server.xz
  exit 2
fi

unxz frida-server.xz
chmod +x frida-server

adb root || echo "[!] No es root, levantar permisos puede fallar"
adb wait-for-device
adb push frida-server /data/local/tmp/frida-server
adb shell "chmod 755 /data/local/tmp/frida-server"
adb shell "nohup /data/local/tmp/frida-server >/dev/null 2>&1 &"

if ! frida-ps -U >/dev/null 2>&1; then
  echo "[✘] frida-server no arrancó correctamente" >&2
  exit 3
fi
echo "[✔] frida-server en ejecución"

CERT_DER="Burp.der"
CERT_PEM="Burp.pem"

curl -sSf http://127.0.0.1:8080/cert -o "$CERT_DER"
openssl x509 -inform DER -in "$CERT_DER" -out "$CERT_PEM"
HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_PEM" | head -n1)
CERT_HASH="${HASH}.0"

echo "[*] Renombrando certificado a $CERT_HASH"
cp "$CERT_PEM" "$CERT_HASH"

adb push "$CERT_HASH" /data/local/tmp/

echo "[*] Poniendo SELinux en modo permisivo (setenforce 0)"
adb shell "setenforce 0" || echo "[!] No se pudo cambiar SELinux"

echo "[*] Intentando remontar /system como lectura-escritura..."
if adb shell "mount -o rw,remount /sys" 2>/dev/null; then
  echo "[✔] /sys remonteado como lectura-escritura"

else
  echo "[✘] No fue posible remountar /system, instalación del certificado en sistema no será posible." >&2
  echo "Podés instalar el certificado como usuario normal o rootear tu dispositivo" >&2
  adb shell "mount -o rw,remount /system" 2>/dev/null; >&2
  echo "[✔] /system remonteado como lectura-escritura" >&2
  exit 4
fi

echo "[*] Copiando certificado..."
adb shell "cp /data/local/tmp/$CERT_HASH /system/etc/security/cacerts/"
adb shell "chmod 644 /system/etc/security/cacerts/$CERT_HASH"

echo "[✔] Certificado instalado correctamente"

echo "[*] Configurando proxy HTTP para Burp Suite..."
adb shell settings put global http_proxy "127.0.0.1:8080"
adb reverse tcp:8080 tcp:8080

echo "[✔] Proxy configurado. Pronto para interceptar tráfico HTTPS con Frida."

