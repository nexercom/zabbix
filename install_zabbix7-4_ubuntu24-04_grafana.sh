#!/bin/bash
# ==========================================================
# Zabbix 7.4 + Grafana en Ubuntu 24.04 (Noble) - Salida "steps"
# ==========================================================
set -euo pipefail

# ---- Vars ----
ZBX_DB_PASS="q2h5A6MNp6WD"               
TZ_VALUE="America/Santo_Domingo"
ZBX_REL_FILE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
ZBX_REL_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZBX_REL_FILE}"
LOG="/var/log/install_zbx74.log"

# ---- Helpers (imprime paso y manda comandos al LOG) ----
say(){ echo -e "$1"; }
run(){ say "$1"; bash -c "$2" >>"$LOG" 2>&1; }
req_root(){ [[ $(id -u) -eq 0 ]] || { echo "❌ Ejecuta como root (sudo)."; exit 1; } }
req_ubuntu_2404(){ grep -qi "ubuntu" /etc/os-release && grep -qi "24.04" /etc/os-release || { echo "❌ Requiere Ubuntu 24.04."; exit 1; } }

req_root
req_ubuntu_2404
: > "$LOG"  # limpia log

say "🚀 Instalando Zabbix 7.4 + Grafana (Ubuntu 24.04). Log: $LOG"

# 0) Prep
run "🧰 Preparando dependencias..." \
  "apt-get update -qq && apt-get install -y -qq wget curl gnupg ca-certificates lsb-release locales"

# 0.1) Locale en_US.UTF-8 para que el pre-check no falle
run "🌐 Generando locale en_US.UTF-8..." \
  "sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8"

# 0.2) Exportar locale a Apache (Zabbix lo revisa)
run "🌐 Aplicando locale a Apache..." \
  "grep -q 'LANG=en_US.UTF-8' /etc/apache2/envvars || echo 'export LANG=en_US.UTF-8' >> /etc/apache2/envvars; \
   grep -q 'LC_ALL=en_US.UTF-8' /etc/apache2/envvars || echo 'export LC_ALL=en_US.UTF-8' >> /etc/apache2/envvars"

# 1) Repo Zabbix
run "📦 [1/8] Añadiendo repositorio de Zabbix 7.4..." \
  "wget -q '${ZBX_REL_URL}' -O '/tmp/${ZBX_REL_FILE}' && dpkg -i '/tmp/${ZBX_REL_FILE}' && apt-get update -qq"

# 2) Paquetes Zabbix + MySQL
run "📦 [2/8] Instalando Zabbix server, frontend y MySQL..." \
  "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
   zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
   zabbix-sql-scripts zabbix-agent mysql-server"

# 3) DB
run "🗄️ [3/8] Creando base de datos y usuario..." \
  "mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZBX_DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF"

# 4) Import esquema (ruta nueva con fallback)
run '📥 [4/8] Importando esquema inicial...' '
SQL_GZ="/usr/share/zabbix/sql-scripts/mysql/server.sql.gz";
[ -f "$SQL_GZ" ] || SQL_GZ="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz";
[ -f "$SQL_GZ" ] || { echo "No se encontró server.sql.gz"; exit 1; }
zcat "$SQL_GZ" | mysql --default-character-set=utf8mb4 -uzabbix -p"'"${ZBX_DB_PASS}"'" zabbix;
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"
'

# 5) Config zabbix_server.conf + TZ PHP
run "⚙️ [5/8] Configurando zabbix_server.conf y Apache..." '
apply_or_add(){ key="$1"; val="$2"; file="$3";
  if grep -q "^[#[:space:]]*${key}=" "$file"; then sed -i "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$file";
  else echo "${key}=${val}" >> "$file"; fi; }
apply_or_add "DBPassword" "'"${ZBX_DB_PASS}"'" /etc/zabbix/zabbix_server.conf
apply_or_add "StartPingers" "100" /etc/zabbix/zabbix_server.conf
apply_or_add "CacheSize" "4G" /etc/zabbix/zabbix_server.conf
if grep -q "php_value date.timezone" /etc/zabbix/apache.conf; then
  sed -i "s|php_value date.timezone .*|php_value date.timezone '"${TZ_VALUE}"'|" /etc/zabbix/apache.conf
else
  echo "php_value date.timezone '"${TZ_VALUE}"'" >> /etc/zabbix/apache.conf
fi
'

# 6) Servicios
run "🚦 [6/8] Iniciando servicios..." \
  "systemctl restart apache2 && systemctl enable apache2 && systemctl restart zabbix-server zabbix-agent && systemctl enable zabbix-server zabbix-agent"

say "✅ Zabbix Web:  http://<IP_SERVIDOR>/zabbix  (Admin / zabbix)"

# 7) Grafana
run "📊 [7/8] Instalando Grafana Enterprise..." '
install -d -m 0755 /etc/apt/keyrings;
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg >/dev/null;
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/enterprise/deb stable main" \
  | tee /etc/apt/sources.list.d/grafana.list >/dev/null;
apt-get update -qq && apt-get install -y -qq grafana-enterprise;
systemctl daemon-reload; systemctl enable --now grafana-server;
grafana-cli plugins install alexanderzobnin-zabbix-app || true;
systemctl restart grafana-server
'

say "🎉 Instalación completada."
say "➡️ Zabbix:  http://<IP_SERVIDOR>/zabbix"
say "➡️ Grafana: http://<IP_SERVIDOR>:3000 (admin / admin)"
say "📝 Log detallado: $LOG"
