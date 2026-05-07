#!/bin/bash
set -e

PHP_VERSION="8.3"
PHPMYADMIN_DOMAIN="db.local"
USER_NAME=${SUDO_USER:-$USER}
SITES_DIR="/home/$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"

echo "=== 🧹 Uninstalling LEMP (PHP $PHP_VERSION) ==="
read -rp "Hapus SEMUA data website dan database? [y/N]: " answer

# Stop services
sudo systemctl stop nginx mariadb php$PHP_VERSION-fpm 2>/dev/null || true

# Remove configs
sudo rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*
sudo rm -rf "$CERT_DIR"
sudo rm -rf /usr/share/phpmyadmin /etc/phpmyadmin
sudo rm -f /usr/local/bin/site

if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "Deleting sites and databases..."
  sudo rm -rf "$SITES_DIR"
  sudo rm -rf /var/lib/mysql
fi

# Purge packages (termasuk versi PHP lain untuk membersihkan 8.5)
echo "Purging PHP packages..."
sudo apt purge -y nginx* mariadb* php$PHP_VERSION* php8.4* php8.5* php-common php-imagick php-redis mkcert
sudo apt autoremove --purge -y
sudo apt clean

# Remove PPA
sudo add-apt-repository --remove ppa:ondrej/php -y 2>/dev/null || true

# Clean hosts
sudo sed -i "/$PHPMYADMIN_DOMAIN/d" /etc/hosts

echo "=== ✅ Uninstall Clean! ==="