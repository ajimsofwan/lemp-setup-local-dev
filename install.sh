#!/bin/bash
set -e

# === CONFIG ===
PHP_VERSION="8.2"
PHPMYADMIN_DOMAIN="db.local"
MYSQL_ROOT_PASS="root"
USER_NAME=${SUDO_USER:-$USER}
SITES_DIR="/home/$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"


echo "=== Installing LEMP Stack for Ubuntu ==="
sudo add-apt-repository ppa:ondrej/php -y >/dev/null 2>&1 
sudo apt update -y
sudo apt install -y nginx mariadb-server php$PHP_VERSION-fpm php$PHP_VERSION-mysql php$PHP_VERSION-zip php$PHP_VERSION-curl php$PHP_VERSION-mbstring php$PHP_VERSION-xml openssl mkcert libnss3-tools unzip wget

# Start & enable
sudo systemctl enable --now nginx mariadb php$PHP_VERSION-fpm

# Secure MariaDB root
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS'; FLUSH PRIVILEGES;"

# Adjust PHP limits
sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo sed -i 's/^post_max_size = .*/post_max_size = 50M/' /etc/php/$PHP_VERSION/fpm/php.ini
sudo systemctl restart php$PHP_VERSION-fpm

# Setup directories
sudo mkdir -p $SITES_DIR $CERT_DIR
sudo chown -R $USER_NAME:$USER_NAME $SITES_DIR

# Allow nginx access home folder
chmod o+x "/home/$USER_NAME"

# Local CA setup
sudo -u $USER_NAME mkcert -install

# === Install phpMyAdmin (local, SSL protected) ===
echo "=== Installing phpMyAdmin ==="
sudo mkdir -p /usr/share/phpmyadmin
cd /usr/share/phpmyadmin
sudo wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip -O pma.zip
sudo unzip -q pma.zip && sudo mv phpMyAdmin-*/* . && sudo rm -rf phpMyAdmin-* pma.zip
sudo mkdir -p /etc/phpmyadmin && sudo mkdir -p /var/lib/phpmyadmin/tmp
sudo chown -R www-data:www-data /usr/share/phpmyadmin /var/lib/phpmyadmin

# Generate SSL cert for phpMyAdmin domain
sudo mkdir -p "$CERT_DIR/$PHPMYADMIN_DOMAIN"
sudo chown -R $USER_NAME:$USER_NAME "$CERT_DIR/$PHPMYADMIN_DOMAIN"
sudo chmod 755 "$CERT_DIR/$PHPMYADMIN_DOMAIN"
cd "$CERT_DIR/$PHPMYADMIN_DOMAIN"
sudo -u $USER_NAME mkcert "$PHPMYADMIN_DOMAIN"

# Create nginx config for phpMyAdmin
sudo tee /etc/nginx/sites-available/$PHPMYADMIN_DOMAIN.conf > /dev/null <<NGINXCONF
server {
    listen 80;
    listen 443 ssl;
    server_name $PHPMYADMIN_DOMAIN;

    client_max_body_size 100M;

    root /usr/share/phpmyadmin;
    index index.php;

    ssl_certificate     $CERT_DIR/$PHPMYADMIN_DOMAIN/$PHPMYADMIN_DOMAIN.pem;
    ssl_certificate_key $CERT_DIR/$PHPMYADMIN_DOMAIN/$PHPMYADMIN_DOMAIN-key.pem;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }
}
NGINXCONF

sudo ln -sf /etc/nginx/sites-available/$PHPMYADMIN_DOMAIN.conf /etc/nginx/sites-enabled/$PHPMYADMIN_DOMAIN.conf
sudo nginx -t && sudo systemctl reload nginx

# Add phpMyAdmin domain to hosts
if ! grep -q "$PHPMYADMIN_DOMAIN" /etc/hosts; then
  echo "127.0.0.1 $PHPMYADMIN_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
fi

# === Add site management tool ===
SITE_SCRIPT="/usr/local/bin/site"
sudo tee $SITE_SCRIPT > /dev/null <<'EOF'
#!/bin/bash
set -e
USER_NAME="ajimsofwan"
SITES_DIR="/home/$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
PHP_VERSION="8.2"
MYSQL_ROOT_PASS="root"

add_hosts() {
  DOMAIN="$1"
  if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts > /dev/null
  fi
}

create_site() {
  DOMAIN="$1"
  if [ -z "$DOMAIN" ]; then
    echo "Usage: site create <domain>"
    exit 1
  fi

  DB_NAME=$(echo "$DOMAIN" | tr '.' '_')
  DB_USER="$DB_NAME"
  DB_PASS=$(openssl rand -hex 8)

  SITE_PATH="$SITES_DIR/$DOMAIN/public"
  sudo mkdir -p "$SITE_PATH"
  sudo chown -R $USER_NAME:www-data "$SITES_DIR/$DOMAIN"

  # SSL
  sudo mkdir -p "$CERT_DIR/$DOMAIN"
  sudo chown -R $USER_NAME:$USER_NAME "$CERT_DIR/$DOMAIN"
  sudo chmod 755 "$CERT_DIR/$DOMAIN"
  cd "$CERT_DIR/$DOMAIN"
  mkcert "$DOMAIN"
  CRT="$CERT_DIR/$DOMAIN/$DOMAIN.pem"
  KEY="$CERT_DIR/$DOMAIN/$DOMAIN-key.pem"

  # PHP index
  cat > "$SITE_PATH/index.php" <<PHP
<?php
echo "<h2>Welcome to $DOMAIN</h2>";
echo "<p>PHP Version: " . phpversion() . "</p>";
?>
PHP

  # Nginx config
  CONF="$NGINX_AVAIL/$DOMAIN.conf"
  sudo tee $CONF > /dev/null <<NGINXCONF
server {
    listen 80;
    listen 443 ssl;
    server_name $DOMAIN;

    root $SITE_PATH;
    index index.php index.html;

    client_max_body_size 100M;

    ssl_certificate     $CRT;
    ssl_certificate_key $KEY;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXCONF

  sudo ln -sf "$CONF" "$NGINX_ENABLED/$DOMAIN.conf"
  sudo nginx -t && sudo systemctl reload nginx

  # Create DB
  sudo mysql -u root -p"$MYSQL_ROOT_PASS" <<MYSQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL

  add_hosts "$DOMAIN"

  echo "✅ Site created!"
  echo "--------------------------------------------"
  echo " Domain:        https://$DOMAIN"
  echo " Root:          $SITE_PATH"
  echo " DB name:       $DB_NAME"
  echo " DB user:       $DB_USER"
  echo " DB pass:       $DB_PASS"
  echo "--------------------------------------------"
}

delete_site() {
  DOMAIN="$1"
  if [ -z "$DOMAIN" ]; then
    echo "Usage: site delete <domain>"
    exit 1
  fi
  DB_NAME=$(echo "$DOMAIN" | tr '.' '_')
  DB_USER="$DB_NAME"
  echo "Deleting $DOMAIN ..."
  sudo rm -f "$NGINX_ENABLED/$DOMAIN.conf" "$NGINX_AVAIL/$DOMAIN.conf"
  sudo rm -rf "$SITES_DIR/$DOMAIN"
  sudo rm -rf "$CERT_DIR/$DOMAIN"
  sudo nginx -t && sudo systemctl reload nginx
  sudo mysql -u root -p"$MYSQL_ROOT_PASS" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  sudo sed -i "/$DOMAIN/d" /etc/hosts
  echo "🗑️  Site deleted: $DOMAIN"
}

case "$1" in
  create) create_site "$2" ;;
  delete) delete_site "$2" ;;
  *)
    echo "Usage: site {create|delete} <domain>"
    ;;
esac
EOF

sudo chmod +x $SITE_SCRIPT

echo "=== ✅ LEMP stack + phpMyAdmin setup complete ==="
echo "MySQL root pass: $MYSQL_ROOT_PASS"
echo "Try visiting: https://$PHPMYADMIN_DOMAIN"
echo "Manage sites with: site create mywebsite.local"
