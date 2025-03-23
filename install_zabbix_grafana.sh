#!/bin/bash
# Script para instalar Zabbix 6 y Grafana en Ubuntu 22.04

# Verifica que se esté ejecutando como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root. Usa sudo."
    exit 1
fi

echo "Iniciando instalación de Zabbix 6 y Grafana..."

# Variables: ajusta la contraseña de la BBDD según tu necesidad.
ZABBIX_DB_PASSWORD="tu_contraseña_segura"
ZABBIX_RELEASE_DEB="zabbix-release_latest_6.0+ubuntu22.04_all.deb"

###############################################
# INSTALACIÓN DE ZABBIX 6
###############################################

# PASO 2: Instalar repositorio de Zabbix
wget https://repo.zabbix.com/zabbix/6.0/ubuntu-arm64/pool/main/z/zabbix-release/${ZABBIX_RELEASE_DEB} -O ${ZABBIX_RELEASE_DEB}
dpkg -i ${ZABBIX_RELEASE_DEB}
apt update

# PASO 3: Instalar Zabbix (servidor, frontend, agente) y MySQL server
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent
apt install -y mysql-server

# PASO 4: Crear base de datos para Zabbix
mysql -uroot <<EOF
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF

# PASO 5: Importar esquema y datos iniciales
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p${ZABBIX_DB_PASSWORD} zabbix

# PASO 6: Desactivar log_bin_trust_function_creators
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

# PASO 7: Configurar la base de datos en Zabbix (editar /etc/zabbix/zabbix_server.conf)
# Descomenta y actualiza la línea DBPassword
sed -i 's/^# DBPassword=/DBPassword=/' /etc/zabbix/zabbix_server.conf
sed -i "s/DBPassword=.*/DBPassword=${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf

# PASO 8: Iniciar y habilitar los servicios de Zabbix y Apache
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

echo "Zabbix instalado. Accede a: http://<IP_DEL_SERVIDOR>/zabbix"

###############################################
# INSTALACIÓN DE GRAFANA
###############################################

# PASO 1: Añadir repositorios y dependencias de Grafana
apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor > /etc/apt/trusted.gpg.d/grafana.gpg
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana-enterprise

# PASO 2: Iniciar y habilitar el servidor de Grafana
systemctl daemon-reload
systemctl start grafana-server
systemctl enable grafana-server

# PASO 3: Instalar el plugin de Zabbix para Grafana
grafana-cli plugins install alexanderzobnin-zabbix-app
systemctl restart grafana-server

echo "Grafana instalado. Accede a: http://<IP_DEL_SERVIDOR>:3000 (Usuario: admin / Contraseña: admin)"
echo "Proceso de instalación finalizado."
