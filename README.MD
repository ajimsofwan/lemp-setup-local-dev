# 🧰 LEMP Stack Installer for Ubuntu 24.04

A simple Bash script to install or uninstall a full **LEMP stack** on Ubuntu 24.04, including:

* **Nginx**
* **MariaDB**
* **PHP 8.2 (via Ondrej PPA)**
* **phpMyAdmin**
* **mkcert** (for local HTTPS certificates)

---

## 🚀 Features

* Fully automated setup — just run and go.
* Optional **full purge mode** for complete cleanup.
* Auto-detects your current user.
* Configures a phpMyAdmin access via `https://db.local`.
* Handles SSL certificate creation with mkcert.

---

## ⚙️ Configuration

* **User detection**: The script automatically detects your username (`$SUDO_USER` or `$USER`).
* **Default directories:**

  * Sites: `/home/<user>/sites`
  * Certificates: `/etc/nginx/cert`
* **Default PHP version:** `8.2`
* **Default phpMyAdmin domain:** `db.local`
* **Default MariaDB root password:** `root`
---

## 📦 Installation

Clone this repository and navigate into it:

```bash
git clone https://github.com/<your-username>/lemp-installer.git
cd lemp-installer
```

Make the script executable and run it:

```bash
chmod +x install.sh
sudo ./install.sh
```

The script will:

1. Install Nginx, MariaDB, PHP 8.2, and phpMyAdmin.
2. Configure SSL with mkcert.
3. Set up a local phpMyAdmin site at `https://db.local`.
4. Start all necessary services.

---

## 🧹 Uninstallation

To uninstall the LEMP stack, run:

```bash
chmod +x uninstall.sh
sudo ./uninstall.sh
```

You’ll be asked whether to **purge all data**, including databases and site files.

* Choose `Y` → Removes everything (configs, data, certificates, sites).
* Choose `N` → Keeps your site data and MySQL databases.

---

## 🌐 Site Management

Once the LEMP stack is installed, you can easily create and delete local websites using the `site` command-line tool installed by the script.

### 🏗️ Create a new site

To create a new website (e.g., `myapp.local`):

```bash
sudo site create myapp.local
```

This will:

1. Create a directory under `/home/<user>/sites/myapp.local`
2. Generate an Nginx config for `myapp.local`
3. Set up SSL certificates using mkcert
4. Reload Nginx

Once complete, open your browser and visit:

```
https://myapp.local
```

---

### 🗑️ Delete an existing site

To remove a website:

```bash
sudo site delete myapp.local
```

You’ll be asked for confirmation before the site’s files and configuration are removed.

If you want to remove all sites at once (dangerous ⚠️):

```bash
sudo site purge
```

---

### 📁 Default Site Directory

All sites are stored in:

```
/home/<user>/sites
```

Each site directory contains its own `public` folder for web files.

---

## 🪪 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
