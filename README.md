<div align="center">

# ☁️ CF Apache Site Manager

### 🔐 Interactive Apache HTTPS Site Manager with Cloudflare Origin SSL

![Version](https://img.shields.io/badge/version-1.0-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Apache](https://img.shields.io/badge/webserver-Apache-red)
![Cloudflare](https://img.shields.io/badge/SSL-Cloudflare%20Origin-orange)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

**Version 1.0**
**By Md. Forhad Parvez**

</div>

---

## ✨ Overview

`CF Apache Site Manager` is a standalone interactive Bash utility for quickly creating and managing Apache HTTPS virtual hosts using Cloudflare Origin SSL certificates.

It handles the repetitive Apache setup for you and provides a simple menu-driven interface.

---

## 🚀 Features

* 🌐 Add new Apache websites interactively
* 🔐 Configure Cloudflare Origin SSL
* 📋 Paste certificate and private key directly into the terminal
* 🔎 Validate SSL certificate and private key
* 🔗 Verify that the certificate and key match
* 📁 Automatically create document roots
* ⚙️ Automatically create Apache virtual hosts
* 🔁 Redirect HTTP → HTTPS
* 🧩 Enable required Apache modules
* 📜 List configured websites
* 🗑️ Remove existing websites
* 🔐 Remove script-managed SSL certificates
* 📦 Back up Apache configs before removal
* 🛡️ Confirm before deleting website files
* 🧪 Validate Apache configuration before reload
* 🔍 Display detected Apache environment information

---

## 📦 Repository

Suggested repository name:

```text
cf-apache-site-manager
```

Suggested project layout:

```text
cf-apache-site-manager/
└── cfsite
```

---

## ⚡ Installation

Clone the repository:

```bash
git clone https://github.com/forhad-dks/cf-apache-site-manager.git
```

Enter the project directory:

```bash
cd cf-apache-site-manager
```

Make the script executable:

```bash
chmod +x cfsite
```

Run it:

```bash
sudo ./cfsite
```

Or install it system-wide:

```bash
sudo cp cfsite /usr/local/sbin/cfsite
sudo chmod 700 /usr/local/sbin/cfsite
```

Then simply run:

```bash
sudo cfsite
```

---

## 🖥️ Main Menu

```text
   _____ _                 _  __ _
  / ____| |               | |/ _| |
 | |    | | ___  _   _  __| | |_| | __ _ _ __ ___
 | |    | |/ _ \| | | |/ _` |  _| |/ _` | '__/ _ \
 | |____| | (_) | |_| | (_| | | | | (_| | | |  __/
  \_____|_|\___/ \__,_|\__,_|_| |_|\__,_|_|  \___/

      Apache HTTPS Site Manager

        Version 1.0  •  By Mr Jack
────────────────────────────────────────────────────────────

1) Add HTTPS website
2) List configured websites
3) Remove website
4) Apache information
5) Test Apache configuration
0) Exit
```

---

## 🌐 Add a Website

Choose:

```text
1) Add HTTPS website
```

The script will ask for:

```text
Domain name
Document root
Cloudflare Origin Certificate
Cloudflare Private Key
```

Example:

```text
Domain name: example.com
Document root: /var/www/example.com
```

If the document root does not exist, the script will offer to create it automatically.

---

## ☁️ Cloudflare Origin SSL

When creating a website, the script guides you to:

```text
Cloudflare Dashboard
        ↓
Select Domain
        ↓
SSL/TLS
        ↓
Origin Server
        ↓
Create Certificate
```

Recommended Cloudflare settings:

```text
Private Key Type:
RSA (2048)

Hostnames:
example.com
*.example.com
```

Cloudflare will provide:

```text
Origin Certificate
Private Key
```

---

## 📋 Paste Certificate

The script asks you to paste the full Cloudflare Origin Certificate:

```text
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
```

After pasting it, press:

```text
Ctrl+D
```

---

## 🔑 Paste Private Key

Next, paste the Cloudflare private key:

```text
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

or:

```text
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
```

Then press:

```text
Ctrl+D
```

The script automatically:

```text
✓ Validates the certificate
✓ Validates the private key
✓ Compares their public keys
✓ Confirms they belong together
✓ Stores them securely
```

---

## 🔐 Certificate Storage

Managed Cloudflare certificates are stored under:

```text
/etc/ssl/cloudflare-origin/DOMAIN/
```

Example:

```text
/etc/ssl/cloudflare-origin/example.com/origin.pem
/etc/ssl/cloudflare-origin/example.com/origin.key
```

---

## ⚙️ Generated Apache Configuration

The generated Apache virtual host is similar to:

```apache
<VirtualHost *:80>

    ServerName example.com
    ServerAlias www.example.com

    Redirect permanent / https://example.com/

</VirtualHost>

<VirtualHost *:443>

    ServerName example.com
    ServerAlias www.example.com

    DocumentRoot "/var/www/example.com"

    SSLEngine on

    SSLCertificateFile "/etc/ssl/cloudflare-origin/example.com/origin.pem"
    SSLCertificateKeyFile "/etc/ssl/cloudflare-origin/example.com/origin.key"

    <Directory "/var/www/example.com">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html index.htm
    </Directory>

</VirtualHost>
```

---

## 📜 List Websites

Choose:

```text
2) List configured websites
```

The script shows:

```text
Domain
Apache config
Document root
Enabled status
SSL certificate path
```

---

## 🗑️ Remove Website

Choose:

```text
3) Remove website
```

Select the website you want to remove.

The script can remove:

```text
✓ Apache virtual host configuration
✓ Managed Origin Certificate
✓ Managed Private Key
```

Website files are **not deleted automatically**.

The script asks separately before deleting the document root.

---

## 📦 Backups

Before removing an Apache configuration, a backup is created under:

```text
/root/cfsite-backups/
```

Example:

```text
/root/cfsite-backups/20260907-201500/
```

---

## 🛡️ Safe Removal

The script protects important directories from accidental deletion.

It refuses recursive deletion of paths such as:

```text
/
/etc
/usr
/var
/var/www
/home
/root
/srv
/opt
```

---

## 🔍 Apache Information

Choose:

```text
4) Apache information
```

The script displays:

```text
Apache binary
Apache service
Apache configuration directory
Sites available directory
Sites enabled directory
Cloudflare certificate directory
Detected virtual hosts
```

---

## 🧪 Test Apache Configuration

Choose:

```text
5) Test Apache configuration
```

The script validates Apache before attempting reloads.

Equivalent Ubuntu/Debian command:

```bash
apache2ctl configtest
```

---

## 🌍 Direct VPS Test

To test a site directly against Apache while preserving the correct HTTPS hostname and TLS SNI:

```bash
curl -kI --resolve example.com:443:127.0.0.1 https://example.com/
```

Expected response:

```text
HTTP/1.1 200 OK
```

or your application's normal redirect.

---

## 📂 Managed Locations

Cloudflare certificates:

```text
/etc/ssl/cloudflare-origin/
```

Apache configuration backups:

```text
/root/cfsite-backups/
```

Apache virtual host locations are detected automatically.

---

## 🔧 Supported Apache Layouts

Designed primarily for:

```text
Ubuntu
Debian
```

Basic support is also included for common:

```text
RHEL
Rocky Linux
AlmaLinux
CentOS
```

Apache layouts.

---

## 💡 Typical Flow

```text
┌──────────────┐
│    Browser   │
└──────┬───────┘
       │
       │ HTTPS
       ▼
┌──────────────┐
│  Cloudflare  │
└──────┬───────┘
       │
       │ Full (strict)
       │ HTTPS
       ▼
┌──────────────┐
│ Apache VPS   │
│              │
│ PHP Website  │
└──────────────┘
```

---

## 👨‍💻 Author

<div align="center">

### Md. Forhad Parvez

**CF Apache Site Manager**

Version `1.0`

Made for fast and simple Apache + Cloudflare HTTPS deployment.

</div>
