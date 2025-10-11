#!/bin/bash
# ==========================================================
# Script de instalación: Zabbix 7.4 + Grafana en Ubuntu 24.04
# Autor: Steven Montero
# Uso: sudo bash install_zabbix7-4_ubuntu24-04_grafana.sh
# ==========================================================

set -e

LOG_FILE="/var/log/install_zbx74.log"
exec > >(tee -a "$LOG_FILE") 2>&1

DB_PASS="q2h5A6MNp6WD"
ZBX_RELEASE_DEB="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
ZBX_RELEASE_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZBX_RELEASE_DEB}"

echo "🚀 Instalando Zabbix 7.4 + Grafana (Ubuntu 24.04). Log: $LOG_FILE"

# ----------------------------------------------------------
# [0] Prepara entorno y locale
# ----------------------------------------------------------
echo "📦 Preparando dependencias..."
apt-get update -qq
apt-get install -y -qq wget gpg lsb-release locales software-properties-common

echo "🌐 Generando locale en_US.UTF-8..."
locale-gen en_US.UTF-8 >/dev/null 2>&1
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ----------------------------------------------------------
# [1] Añadir repositorio de Zabbix 7.4
# ----------------------------------------------------------
echo "📦 [1/8] Añadiendo repositorio de Zabbix 7.4..."
wget -q "${ZBX_RELEASE_URL}" -O "${ZBX_RELEASE_DEB}"
dpkg -i "${ZBX_RELEASE_DEB}" >/dev/null 2>&1
apt-get update -qq

# ----------------------------------------------------------
# [2] Instalar Zabbix y MySQL
# ----------------------------------------------------------
echo "📦 [2/8] Instalando Zabbix y MySQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
    zabbix-sql-scripts zabbix-agent mysql-server php8.3-mbstring php8.3-ldap php8.3-bcmath

# ----------------------------------------------------------
# [3] Crear base de datos y usuario
# ----------------------------------------------------------
echo "🗄️ [3/8] Creando base de datos y usuario..."
mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

# ----------------------------------------------------------
# [4] Importar esquema inicial
# ----------------------------------------------------------
echo "📥 [4/8] Importando esquema inicial..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASS}" zabbix
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

# ----------------------------------------------------------
# [5] Configurar zabbix_server.conf y Apache
# ----------------------------------------------------------
echo "⚙️ [5/8] Configurando zabbix_server.conf y Apache..."
ZBX_CONF="/etc/zabbix/zabbix_server.conf"

sed -i "s/^[#[:space:]]*DBPassword=.*/DBPassword=${DB_PASS}/" "$ZBX_CONF"
grep -q '^DBPassword=' "$ZBX_CONF" || echo "DBPassword=${DB_PASS}" >> "$ZBX_CONF"

sed -i 's/^[#[:space:]]*StartPingers=.*/StartPingers=100/' "$ZBX_CONF"
grep -q '^StartPingers=' "$ZBX_CONF" || echo "StartPingers=100" >> "$ZBX_CONF"

sed -i 's/^[#[:space:]]*CacheSize=.*/CacheSize=1G/' "$ZBX_CONF"
grep -q '^CacheSize=' "$ZBX_CONF" || echo "CacheSize=1G" >> "$ZBX_CONF"

systemctl restart apache2

# ----------------------------------------------------------
# [6] Iniciar servicios
# ----------------------------------------------------------
echo "🚦 [6/8] Iniciando servicios..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2 >/dev/null

echo "✅ Zabbix Web: http://<IP_SERVIDOR>/zabbix (Admin / zabbix)"

# ----------------------------------------------------------
# [7] Instalar Grafana Enterprise
# ----------------------------------------------------------
echo "📊 [7/8] Instalando Grafana Enterprise..."
wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor > /etc/apt/trusted.gpg.d/grafana.gpg
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee /etc/apt/sources.list.d/grafana.list >/dev/null
apt-get update -qq
apt-get install -y -qq grafana-enterprise

systemctl daemon-reload
systemctl enable grafana-server >/dev/null
systemctl start grafana-server

# Plugin de Zabbix
grafana-cli plugins install alexanderzobnin-zabbix-app >/dev/null 2>&1 || true
systemctl restart grafana-server

# ----------------------------------------------------------
# [8] Finalizar
# ----------------------------------------------------------
echo "🎉 [8/8] Instalación completada."
echo "➡️ Accede a Zabbix: http://<IP_SERVIDOR>/zabbix"
echo "➡️ Accede a Grafana: http://<IP_SERVIDOR>:3000 (admin / admin)"
echo "📝 Log completo en: $LOG_FILE"
