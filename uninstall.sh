#!/bin/bash
set -e

# === CONFIG ===
PHP_VERSION="8.2"
PHPMYADMIN_DOMAIN="db.local"
MYSQL_ROOT_PASS="root"
USER_NAME=${SUDO_USER:-$USER}
SITES_DIR="/home/$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"

echo "=== 🧹 Uninstalling LEMP Stack ==="
echo
read -rp "Do you want to PURGE ALL data (including databases and site files)? [y/N]: " answer

PURGE_ALL=false
if [[ "$answer" =~ ^[Yy]$ ]]; then
  PURGE_ALL=true
  echo "⚠️  FULL PURGE mode — all site data and databases will be deleted!"
else
  echo "SAFE mode — site files and databases will be kept."
fi
echo

echo "Stopping services..."
sudo systemctl stop nginx mariadb php$PHP_VERSION-fpm 2>/dev/null || true
sudo systemctl disable nginx mariadb php$PHP_VERSION-fpm 2>/dev/null || true

echo "Removing Nginx configs..."
sudo rm -f "/etc/nginx/sites-enabled/$PHPMYADMIN_DOMAIN.conf"
sudo rm -f "/etc/nginx/sites-available/$PHPMYADMIN_DOMAIN.conf"

# Remove cert directory
if [ -d "$CERT_DIR" ]; then
  echo "Removing SSL certificates..."
  sudo rm -rf "$CERT_DIR"
fi

echo "Removing phpMyAdmin..."
sudo rm -rf /usr/share/phpmyadmin /etc/phpmyadmin /var/lib/phpmyadmin

echo "Removing site management tool..."
sudo rm -f /usr/local/bin/site

# Remove sites (optionally)
if [ -d "$SITES_DIR" ]; then
  if $PURGE_ALL; then
    echo "Deleting all sites in $SITES_DIR..."
    sudo rm -rf "$SITES_DIR"
  else
    echo "Keeping site files in $SITES_DIR"
  fi
fi

echo "Cleaning /etc/hosts..."
sudo sed -i "/$PHPMYADMIN_DOMAIN/d" /etc/hosts

echo "Removing LEMP packages..."
sudo apt purge -y nginx nginx-common nginx-core \
  php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-cli php$PHP_VERSION-common \
  mariadb-server mariadb-client mkcert libnss3-tools

if $PURGE_ALL; then
  echo "Purging MariaDB data..."
  sudo rm -rf /var/lib/mysql /var/log/mysql /etc/mysql
fi

echo "Fixing package state..."
sudo dpkg --configure -a || true
sudo apt --fix-broken install -y || true

echo "Cleaning unused packages..."
sudo apt autoremove --purge -y
sudo apt autoclean -y
sudo apt clean -y

# Remove PHP PPA if present
if grep -q "ppa:ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
  echo "Removing PHP PPA..."
  sudo add-apt-repository --remove ppa:ondrej/php -y >/dev/null 2>&1 || true
fi

echo
echo "=== ✅ Uninstall Complete ==="
if $PURGE_ALL; then
  echo "All data, databases, and configs were removed."
else
  echo "LEMP stack uninstalled. Site files and databases preserved."
fi
