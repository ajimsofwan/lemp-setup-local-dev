#!/bin/bash
set -e

# === CONFIG ===
PHP_VERSION="8.3"
PHPMYADMIN_DOMAIN="db.local"
MYSQL_ROOT_PASS="root"
USER_NAME=${SUDO_USER:-$USER}
SITES_DIR="/home/$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"

echo "=== 🚀 Installing LEMP Stack (Forced PHP $PHP_VERSION) ==="

# Tambahkan PPA
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Install Nginx & MariaDB
sudo apt install -y nginx mariadb-server openssl mkcert libnss3-tools unzip wget

# Install PHP 8.3 secara spesifik agar tidak mengambil versi 8.5+
sudo apt install -y \
php$PHP_VERSION-fpm \
php$PHP_VERSION-cli \
php$PHP_VERSION-common \
php$PHP_VERSION-mysql \
php$PHP_VERSION-zip \
php$PHP_VERSION-curl \
php$PHP_VERSION-mbstring \
php$PHP_VERSION-xml \
php$PHP_VERSION-intl \
php$PHP_VERSION-gd \
php$PHP_VERSION-bcmath \
php$PHP_VERSION-sqlite3 \
php$PHP_VERSION-soap \
php$PHP_VERSION-readline \
php$PHP_VERSION-imagick \
php$PHP_VERSION-redis

# Set PHP 8.3 sebagai default di sistem
sudo update-alternatives --set php /usr/bin/php$PHP_VERSION
sudo update-alternatives --set php-config /usr/bin/php-config$PHP_VERSION
sudo update-alternatives --set phpize /usr/bin/phpize$PHP_VERSION

# Start & enable services
sudo systemctl enable --now nginx mariadb php$PHP_VERSION-fpm

# Secure MariaDB root
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS'; FLUSH PRIVILEGES;"

# Adjust PHP 8.3 limits
PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' $PHP_INI
sudo sed -i 's/^post_max_size = .*/post_max_size = 100M/' $PHP_INI
sudo sed -i 's/^memory_limit = .*/memory_limit = 512M/' $PHP_INI
sudo systemctl restart php$PHP_VERSION-fpm

# Setup directories
sudo mkdir -p $SITES_DIR $CERT_DIR
sudo chown -R $USER_NAME:$USER_NAME $SITES_DIR
chmod o+x "/home/$USER_NAME"

# Local CA setup
sudo -u $USER_NAME mkcert -install

# === Install phpMyAdmin ===
echo "=== Installing phpMyAdmin ==="
sudo mkdir -p /usr/share/phpmyadmin
cd /usr/share/phpmyadmin
sudo wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip -O pma.zip
sudo unzip -q pma.zip && sudo mv phpMyAdmin-*/* . && sudo rm -rf phpMyAdmin-* pma.zip
sudo mkdir -p /etc/phpmyadmin && sudo mkdir -p /var/lib/phpmyadmin/tmp
sudo chown -R www-data:www-data /usr/share/phpmyadmin /var/lib/phpmyadmin

# SSL for phpMyAdmin
sudo mkdir -p "$CERT_DIR/$PHPMYADMIN_DOMAIN"
sudo chown -R $USER_NAME:$USER_NAME "$CERT_DIR/$PHPMYADMIN_DOMAIN"
cd "$CERT_DIR/$PHPMYADMIN_DOMAIN"
sudo -u $USER_NAME mkcert "$PHPMYADMIN_DOMAIN"

# Nginx config for phpMyAdmin
sudo tee /etc/nginx/sites-available/$PHPMYADMIN_DOMAIN.conf > /dev/null <<NGINXCONF
server {
    listen 80;
    listen 443 ssl;
    server_name $PHPMYADMIN_DOMAIN;
    root /usr/share/phpmyadmin;
    index index.php;
    ssl_certificate     $CERT_DIR/$PHPMYADMIN_DOMAIN/$PHPMYADMIN_DOMAIN.pem;
    ssl_certificate_key $CERT_DIR/$PHPMYADMIN_DOMAIN/$PHPMYADMIN_DOMAIN-key.pem;
    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }
}
NGINXCONF

sudo ln -sf /etc/nginx/sites-available/$PHPMYADMIN_DOMAIN.conf /etc/nginx/sites-enabled/$PHPMYADMIN_DOMAIN.conf
sudo nginx -t && sudo systemctl reload nginx

if ! grep -q "$PHPMYADMIN_DOMAIN" /etc/hosts; then
  echo "127.0.0.1 $PHPMYADMIN_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
fi

# === Site Management Tool ===
SITE_SCRIPT="/usr/local/bin/site"
sudo tee $SITE_SCRIPT > /dev/null <<EOF
#!/bin/bash
USER_NAME=${SUDO_USER:-$USER}
SITES_DIR="/home/\$USER_NAME/sites"
CERT_DIR="/etc/nginx/cert"
PHP_VERSION="$PHP_VERSION"

create_site() {
  DOMAIN="\$1"
  DB_NAME=\$(echo "\$DOMAIN" | tr '.' '_')
  DB_PASS=\$(openssl rand -hex 8)
  SITE_PATH="\$SITES_DIR/\$DOMAIN/public"
  
  sudo mkdir -p "\$SITE_PATH"
  sudo chown -R \$USER_NAME:www-data "\$SITES_DIR/\$DOMAIN"
  
  cd "$CERT_DIR" && sudo mkdir -p "\$DOMAIN" && cd "\$DOMAIN"
  sudo -u \$USER_NAME mkcert "\$DOMAIN"

  sudo tee /etc/nginx/sites-available/\$DOMAIN.conf > /dev/null <<CONF
server {
    listen 80; listen 443 ssl;
    server_name \$DOMAIN;
    root \$SITE_PATH;
    index index.php;
    ssl_certificate $CERT_DIR/\$DOMAIN/\$DOMAIN.pem;
    ssl_certificate_key $CERT_DIR/\$DOMAIN/\$DOMAIN-key.pem;
    location / { try_files \\\$uri \\\$uri/ /index.php?\\\$args; }
    location ~ \\.php\\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php\$PHP_VERSION-fpm.sock;
    }
}
CONF
  sudo ln -sf /etc/nginx/sites-available/\$DOMAIN.conf /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS \\\`\$DB_NAME\\\`; GRANT ALL PRIVILEGES ON \\\`\$DB_NAME\\\`.* TO '\$DB_NAME'@'localhost' IDENTIFIED BY '\$DB_PASS';"
  echo "127.0.0.1 \$DOMAIN" | sudo tee -a /etc/hosts > /dev/null
  echo "✅ Site \$DOMAIN Created! DB Pass: \$DB_PASS"
}

case "\$1" in
  create) create_site "\$2" ;;
  delete) 
    sudo rm -f /etc/nginx/sites-enabled/\$2.conf /etc/nginx/sites-available/\$2.conf
    sudo rm -rf "$SITES_DIR/\$2" "$CERT_DIR/\$2"
    sudo nginx -t && sudo systemctl reload nginx
    echo "🗑️ Deleted \$2" ;;
  *) echo "Usage: site {create|delete} domain" ;;
esac
EOF
sudo chmod +x $SITE_SCRIPT

echo "=== ✅ Complete! PHP Version: \$(php -v | head -n 1) ==="