#!/bin/bash
clear

cat <<'EOF'
==========================================================
 Script: Instalación Zabbix 7.4 + Grafana en Ubuntu 24.04
 Autor: Steven Montero
==========================================================
EOF

echo

# ---- Colores ----
RED="\033[0;31m"
NC="\033[0m" # No Color

# ---- Variables ----
ZBX_DB_PASS="q2h5A6MNp6WD"
TZ_VALUE="America/Santo_Domingo"
ZBX_REL_FILE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
ZBX_REL_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZBX_REL_FILE}"

# ---- Funciones de verificación ----
is_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}❌ Error: Este script debe ejecutarse como root (sudo).${NC}"
        exit 1
    fi
}

is_ubuntu_2404() {
    if ! grep -qi "ubuntu" /etc/os-release || ! grep -qi "24.04" /etc/os-release; then
        echo -e "${RED}❌ Error: Este script solo es compatible con Ubuntu 24.04 (Noble).${NC}"
        exit 1
    fi
}

# ---- Ejecutar checkers ----
is_root
is_ubuntu_2404

set -euo pipefail

# ---- Variables ----
ZBX_DB_PASS="q2h5A6MNp6WD"
TZ_VALUE="America/Santo_Domingo"
ZBX_REL_FILE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
ZBX_REL_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZBX_REL_FILE}"

# ---- Comprobaciones ----
[[ "$(id -u)" -eq 0 ]] || { echo "❌ Ejecuta como root (sudo)."; exit 1; }
grep -qi "ubuntu" /etc/os-release && grep -qi "24.04" /etc/os-release \
  || { echo "❌ Este script es para Ubuntu 24.04 (noble)."; exit 1; }

echo "🚀 Instalando Zabbix 7.4 + Grafana en Ubuntu 24.04..."

# ----------------------------------------------------------
# 0) Preparativos
# ----------------------------------------------------------
echo "🧰 Preparando dependencias..."
apt-get update -y >/dev/null 2>&1
apt-get install -y wget curl gnupg ca-certificates lsb-release >/dev/null 2>&1

# ----------------------------------------------------------
# 1) Repositorio Zabbix 7.4
# ----------------------------------------------------------
echo "📦 [1/8] Añadiendo repositorio de Zabbix 7.4..."
wget -q "${ZBX_REL_URL}" -O "/tmp/${ZBX_REL_FILE}" >/dev/null 2>&1
dpkg -i "/tmp/${ZBX_REL_FILE}" >/dev/null 2>&1
apt-get update -y >/dev/null 2>&1

# ----------------------------------------------------------
# 2) Instalar Zabbix + MySQL
# ----------------------------------------------------------
echo "📦 [2/8] Instalando Zabbix y MySQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
  zabbix-sql-scripts zabbix-agent mysql-server >/dev/null 2>&1

# ----------------------------------------------------------
# 3) Base de datos
# ----------------------------------------------------------
echo "🗄️ [3/8] Creando base de datos y usuario..."
mysql -uroot >/dev/null 2>&1 <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZBX_DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

# ----------------------------------------------------------
# 4) Importar esquema
# ----------------------------------------------------------
echo "📥 [4/8] Importando esquema inicial..."
SQL_GZ="/usr/share/zabbix/sql-scripts/mysql/server.sql.gz"
[[ -f "$SQL_GZ" ]] || SQL_GZ="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
[[ -f "$SQL_GZ" ]] || { echo "❌ No se encontró server.sql.gz en rutas conocidas."; exit 1; }

zcat "$SQL_GZ" | mysql --default-character-set=utf8mb4 -uzabbix -p"${ZBX_DB_PASS}" zabbix >/dev/null 2>&1
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" >/dev/null 2>&1

# ----------------------------------------------------------
# 5) Configurar Zabbix server y Apache
# ----------------------------------------------------------
echo "⚙️ [5/8] Configurando zabbix_server.conf y Apache..."
apply_or_add () {
  local key="$1" val="$2" file="$3"
  if grep -q "^[#[:space:]]*${key}=" "$file"; then
    sed -i "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

apply_or_add "DBPassword" "${ZBX_DB_PASS}" /etc/zabbix/zabbix_server.conf
apply_or_add "StartPingers" "100" /etc/zabbix/zabbix_server.conf
apply_or_add "CacheSize"   "4G"  /etc/zabbix/zabbix_server.conf

if grep -q "php_value date.timezone" /etc/zabbix/apache.conf; then
  sed -i "s|php_value date.timezone .*|php_value date.timezone ${TZ_VALUE}|" /etc/zabbix/apache.conf
else
  echo "php_value date.timezone ${TZ_VALUE}" >> /etc/zabbix/apache.conf
fi

# ----------------------------------------------------------
# 6) Iniciar servicios
# ----------------------------------------------------------
echo "🚦 [6/8] Iniciando servicios..."
systemctl restart apache2 >/dev/null 2>&1
systemctl enable apache2 >/dev/null 2>&1
systemctl restart zabbix-server zabbix-agent >/dev/null 2>&1
systemctl enable zabbix-server zabbix-agent >/dev/null 2>&1

# ----------------------------------------------------------
# 7) Grafana
# ----------------------------------------------------------
echo "📊 [7/8] Instalando Grafana Enterprise..."
install -d -m 0755 /etc/apt/keyrings >/dev/null 2>&1
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg >/dev/null 2>&1
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/enterprise/deb stable main" \
  | tee /etc/apt/sources.list.d/grafana.list >/dev/null 2>&1

apt-get update -y >/dev/null 2>&1
apt-get install -y grafana-enterprise >/dev/null 2>&1

systemctl daemon-reload >/dev/null 2>&1
systemctl enable --now grafana-server >/dev/null 2>&1

grafana-cli plugins install alexanderzobnin-zabbix-app >/dev/null 2>&1 || true
systemctl restart grafana-server >/dev/null 2>&1

# ----------------------------------------------------------
# 8) Locale (al final)
# ----------------------------------------------------------
echo "🌐 Ajustando locale (en_US.UTF-8) sin reiniciar..."

apt-get install -y locales >/dev/null 2>&1 || true
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 >/dev/null 2>&1 || true
printf 'LANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale

grep -q 'LANG=en_US.UTF-8' /etc/apache2/envvars || echo 'export LANG=en_US.UTF-8' >> /etc/apache2/envvars
grep -q 'LC_ALL=en_US.UTF-8' /etc/apache2/envvars || echo 'export LC_ALL=en_US.UTF-8' >> /etc/apache2/envvars

systemctl daemon-reexec >/dev/null 2>&1 || true
systemctl restart apache2 >/dev/null 2>&1 || true
systemctl restart php8.3-fpm >/dev/null 2>&1 || true  # si existe

# ----------------------------------------------------------
# Resumen final
# ----------------------------------------------------------
echo "🎉 Instalación completada."
echo "➡️ Zabbix:  http://<IP_SERVIDOR>/zabbix"
echo "➡️ Grafana: http://<IP_SERVIDOR>:3000  (admin / admin)"
