#!/bin/bash
# ==========================================================
# Script de instalación: Zabbix 6.4 + Grafana en Ubuntu 22.04
# Autor: Steven Montero
# Uso: sudo bash install_zabbix64_grafana.sh
# ==========================================================

set -e

# ---- Variables ----
ZABBIX_DB_PASSWORD="q2h5A6MNp6WD"
ZABBIX_RELEASE_DEB_FILE="zabbix-release_6.4-1+ubuntu22.04_all.deb"
ZABBIX_RELEASE_DEB_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/${ZABBIX_RELEASE_DEB_FILE}"

# ---- Verificar root ----
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Este script debe ejecutarse como root. Usa sudo."
    exit 1
fi

echo "🚀 Instalando Zabbix 6.4 y Grafana en Ubuntu 22.04..."

# ----------------------------------------------------------
# INSTALACIÓN ZABBIX 6.4
# ----------------------------------------------------------
echo "📦 [1/6] Configurando repositorio de Zabbix..."
wget -q "${ZABBIX_RELEASE_DEB_URL}" -O "${ZABBIX_RELEASE_DEB_FILE}"
dpkg -i "${ZABBIX_RELEASE_DEB_FILE}"
apt update -y

echo "📦 [2/6] Instalando Zabbix y MySQL..."
DEBIAN_FRONTEND=noninteractive apt install -y \
    zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
    zabbix-sql-scripts zabbix-agent mysql-server

echo "🗄️ [3/6] Creando base de datos y usuario..."
mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

echo "🗄️ [4/6] Importando esquema inicial..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 -uzabbix -p"${ZABBIX_DB_PASSWORD}" zabbix

mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

echo "⚙️ [5/6] Configurando zabbix_server.conf..."
sed -i 's/^[#[:space:]]*DBPassword=.*/DBPassword='"${ZABBIX_DB_PASSWORD}"'/' /etc/zabbix/zabbix_server.conf
grep -q '^DBPassword=' /etc/zabbix/zabbix_server.conf || echo "DBPassword=${ZABBIX_DB_PASSWORD}" >> /etc/zabbix/zabbix_server.conf

sed -i 's/^[#[:space:]]*StartPingers=.*/StartPingers=300/' /etc/zabbix/zabbix_server.conf
grep -q '^StartPingers=' /etc/zabbix/zabbix_server.conf || echo "StartPingers=300" >> /etc/zabbix/zabbix_server.conf

sed -i 's/^[#[:space:]]*CacheSize=.*/CacheSize=6G/' /etc/zabbix/zabbix_server.conf
grep -q '^CacheSize=' /etc/zabbix/zabbix_server.conf || echo "CacheSize=6G" >> /etc/zabbix/zabbix_server.conf

echo "🚦 [6/6] Iniciando servicios Zabbix..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

echo "✅ Zabbix instalado en: http://<IP_SERVIDOR>/zabbix"

# ----------------------------------------------------------
# INSTALACIÓN GRAFANA
# ----------------------------------------------------------
echo "📊 Instalando Grafana Enterprise..."
apt-get install -y apt-transport-https software-properties-common wget gpg
wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor > /etc/apt/trusted.gpg.d/grafana.gpg
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee /etc/apt/sources.list.d/grafana.list >/dev/null

apt-get update
apt-get install -y grafana-enterprise

systemctl daemon-reload
systemctl start grafana-server
systemctl enable grafana-server

echo "🔌 Instalando plugin de Zabbix para Grafana..."
grafana-cli plugins install alexanderzobnin-zabbix-app || true
systemctl restart grafana-server

echo "🎉 Instalación finalizada!"
echo "➡️ Accede a Zabbix: http://<IP_SERVIDOR>/zabbix"
echo "➡️ Accede a Grafana: http://<IP_SERVIDOR>:3000 (admin / admin)"
