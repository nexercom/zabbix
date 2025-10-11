#!/bin/bash
# ==========================================================
# Script: Zabbix 7.4 + Grafana en Ubuntu 24.04 (Noble)
# Autor: Steven Montero (actualizado)
# Uso:   sudo bash install_zabbix74_grafana.sh
# ==========================================================

set -euo pipefail

# ---- Variables ----
ZBX_DB_PASS="q2h5A6MNp6WD"                      
TZ_VALUE="America/Santo_Domingo"                
ZBX_REL_FILE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
ZBX_REL_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZBX_REL_FILE}"

# ---- Verificaciones básicas ----
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Este script debe ejecutarse como root. Usa sudo."
  exit 1
fi

if ! grep -qi "ubuntu" /etc/os-release || ! grep -qi "24.04" /etc/os-release; then
  echo "❌ Este instalador está preparado para Ubuntu 24.04 (noble)."
  exit 1
fi

echo "🚀 Instalando Zabbix 7.4 y Grafana en Ubuntu 24.04..."

# ----------------------------------------------------------
# 0) Preparativos
# ----------------------------------------------------------
echo "🧰 Preparando dependencias..."
apt-get update -y
apt-get install -y wget curl gnupg ca-certificates lsb-release

# ----------------------------------------------------------
# 1) Repositorio oficial Zabbix 7.4
# ----------------------------------------------------------
echo "📦 [1/8] Añadiendo repositorio de Zabbix 7.4..."
wget -q "${ZBX_REL_URL}" -O "/tmp/${ZBX_REL_FILE}"
dpkg -i "/tmp/${ZBX_REL_FILE}"
apt-get update -y

# ----------------------------------------------------------
# 2) Instalar Zabbix + LAMP piezas necesarias
# ----------------------------------------------------------
echo "📦 [2/8] Instalando Zabbix server, frontend y MySQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
  zabbix-sql-scripts zabbix-agent mysql-server

# ----------------------------------------------------------
# 3) Base de datos
# ----------------------------------------------------------
echo "🗄️ [3/8] Creando base de datos y usuario..."
mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZBX_DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

echo "🗄️ [4/8] Importando esquema inicial..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz \
  | mysql --default-character-set=utf8mb4 -uzabbix -p"${ZBX_DB_PASS}" zabbix

mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

# ----------------------------------------------------------
# 4) Configurar zabbix_server.conf y Apache/PHP
# ----------------------------------------------------------
echo "⚙️ [5/8] Configurando zabbix_server.conf..."
# Password DB
if grep -q '^[#[:space:]]*DBPassword=' /etc/zabbix/zabbix_server.conf; then
  sed -i "s|^[#[:space:]]*DBPassword=.*|DBPassword=${ZBX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
else
  echo "DBPassword=${ZBX_DB_PASS}" >> /etc/zabbix/zabbix_server.conf
fi

# Ajustes opcionales de rendimiento (ajusta a tu RAM)
apply_or_add () {
  local key="$1" val="$2" file="$3"
  if grep -q "^[#[:space:]]*${key}=" "$file"; then
    sed -i "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}
apply_or_add "StartPingers" "100" /etc/zabbix/zabbix_server.conf
apply_or_add "CacheSize"   "2G"  /etc/zabbix/zabbix_server.conf

# Zona horaria PHP del frontend (archivo de Apache de Zabbix)
if grep -q "php_value date.timezone" /etc/zabbix/apache.conf; then
  sed -i "s|php_value date.timezone .*|php_value date.timezone ${TZ_VALUE}|" /etc/zabbix/apache.conf
else
  echo "php_value date.timezone ${TZ_VALUE}" >> /etc/zabbix/apache.conf
fi

# ----------------------------------------------------------
# 5) Arrancar servicios Zabbix
# ----------------------------------------------------------
echo "🚦 [6/8] Iniciando servicios Zabbix..."
systemctl restart apache2
systemctl enable apache2

systemctl restart zabbix-server zabbix-agent
systemctl enable zabbix-server zabbix-agent

echo "✅ Zabbix Web:  http://<IP_SERVIDOR>/zabbix"
echo "ℹ️ Usuario inicial: Admin / zabbix (lo cambiarás en el primer login)."

# ----------------------------------------------------------
# 6) Instalar Grafana Enterprise (repos oficiales)
# ----------------------------------------------------------
echo "📊 [7/8] Instalando Grafana Enterprise..."
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/enterprise/deb stable main" \
  | tee /etc/apt/sources.list.d/grafana.list >/dev/null

apt-get update -y
apt-get install -y grafana-enterprise

systemctl daemon-reload
systemctl enable --now grafana-server

echo "🔌 Instalando plugin Zabbix para Grafana..."
grafana-cli plugins install alexanderzobnin-zabbix-app || true
systemctl restart grafana-server

# ----------------------------------------------------------
# 7) Resumen final
# ----------------------------------------------------------
echo "🎉 Instalación completada."
echo "➡️ Zabbix:  http://<IP_SERVIDOR>/zabbix"
echo "➡️ Grafana: http://<IP_SERVIDOR>:3000  (admin / admin)"
echo "   Luego en Grafana: Enable el plugin 'Zabbix' y configura la conexión al MySQL de Zabbix."
