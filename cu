# ============================================================
# CACTI MONITORING SETUP
# Domain : lab-smk.xyz
# IP     : 192.168.30.10
# Host   : ahmadshofawi
# ============================================================


# 0. FIX SUDO (jalankan sebagai root sekali di awal)
su -
usermod -aG sudo ahmads
echo "ahmads ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ahmads
exit


# 1. SET HOSTNAME
sudo hostnamectl set-hostname ahmadshofawi


# 2. KONFIGURASI IP NETWORK
sudo nano /etc/netplan/50-cloud-init.yaml

network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: true
      dhcp6: true
    enp0s3:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.1
      nameservers:
        addresses:
          - 192.168.30.10
          - 8.8.8.8
          - 1.1.1.1

sudo netplan apply


# 3. KONFIGURASI /etc/hosts
sudo nano /etc/hosts

127.0.0.1       localhost
192.168.30.10   ahmadshofawi.lab-smk.xyz    ahmadshofawi    www    monitor

hostname
hostname -f


# 4. KONFIGURASI BIND9
sudo nano /etc/bind/named.conf.options

options {
        directory "/var/cache/bind";
        //==========================================================
        allow-query { any; };
        //==========================================================
        allow-recursion { !192.168.20.0/24; any; };
        //==========================================================
        forwarders {
                1.1.1.1;
                8.8.8.8;
        };
        //==========================================================
        dnssec-validation auto;
        //==========================================================
        listen-on-v6 { any; };
};

sudo nano /etc/bind/named.conf.local

zone "lab-smk.xyz" {
    type master;
    file "/etc/bind/db.lab-smk";
};

zone "30.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192";
};

sudo cp /etc/bind/db.local /etc/bind/db.lab-smk
sudo nano /etc/bind/db.lab-smk

$TTL    604800
@       IN      SOA     ahmadshofawi.lab-smk.xyz. root.lab-smk.xyz. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
@               IN      NS      ahmadshofawi.lab-smk.xyz.
@               IN      A       192.168.30.10
ahmadshofawi    IN      A       192.168.30.10
www             IN      A       192.168.30.10
monitor         IN      A       192.168.30.10

sudo cp /etc/bind/db.127 /etc/bind/db.192
sudo nano /etc/bind/db.192

$TTL    604800
@       IN      SOA     ahmadshofawi.lab-smk.xyz. root.lab-smk.xyz. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
@       IN      NS      ahmadshofawi.lab-smk.xyz.
10      IN      PTR     ahmadshofawi.lab-smk.xyz.

sudo named-checkconf
sudo named-checkzone lab-smk.xyz /etc/bind/db.lab-smk
sudo named-checkzone 30.168.192.in-addr.arpa /etc/bind/db.192
sudo systemctl restart bind9


# 5. INSTALL APACHE2 + SSL
sudo apt update
sudo apt install apache2 -y

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt \
  -subj "/C=ID/ST=Jawa/L=Kota/O=Lab SMK/CN=lab-smk.xyz" \
  -addext "subjectAltName=DNS:lab-smk.xyz,DNS:www.lab-smk.xyz,DNS:monitor.lab-smk.xyz,DNS:ahmadshofawi.lab-smk.xyz"

sudo a2enmod ssl
sudo a2enmod headers
sudo a2enmod rewrite


# 6. INSTALL MARIADB + SNMP + CACTI
sudo apt update
sudo apt install mariadb-server snmp snmpd -y

sudo systemctl start mariadb
sudo mysql_secure_installation

# PERHATIAN: apt install cacti akan memunculkan layar biru (wizard), siapkan:
# 1. Web server        : pilih apache2 (tekan Spasi untuk beri tanda *, lalu Enter)
# 2. Configure database: pilih <Yes>
# 3. MySQL password    : isi cacti123 atau Enter untuk generate otomatis
sudo apt install cacti cacti-spine -y

sudo nano /etc/snmp/snmpd.conf

agentaddress udp:161,udp6:[::1]:161
rocommunity public default

sudo systemctl restart snmpd


# 7. FIX LOCALE
sudo apt install locales-all -y
sudo update-locale LANG=en_US.UTF-8
sudo systemctl restart apache2


# 8. KONFIGURASI TIMEZONE + PHP
sudo timedatectl set-timezone Asia/Jakarta
date

# timezone + tuning untuk Web Server (apache2)
sudo nano /etc/php/8.3/apache2/php.ini

# cari dengan Ctrl+W lalu ubah masing-masing:
date.timezone = Asia/Jakarta
memory_limit = 512M
max_execution_time = 60

# timezone + tuning untuk Poller/CLI (SANGAT PENTING untuk grafik Cacti)
sudo nano /etc/php/8.3/cli/php.ini

# cari dengan Ctrl+W lalu ubah masing-masing:
date.timezone = Asia/Jakarta
memory_limit = 512M
max_execution_time = 60

sudo systemctl restart apache2


# 9. VIRTUAL HOST CACTI (HTTPS)
sudo nano /etc/apache2/sites-available/monitor-ssl.conf

# redirect HTTP ke HTTPS
<VirtualHost *:80>
    ServerName monitor.lab-smk.xyz
    Redirect permanent / https://monitor.lab-smk.xyz/
</VirtualHost>

<IfModule mod_ssl.c>
    <VirtualHost _default_:443>
        ServerName monitor.lab-smk.xyz
        DocumentRoot /usr/share/cacti/site
        SSLEngine on
        SSLCertificateFile      /etc/ssl/certs/apache-selfsigned.crt
        SSLCertificateKeyFile   /etc/ssl/private/apache-selfsigned.key
        <Directory /usr/share/cacti/site>
            Options +FollowSymLinks
            AllowOverride None
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>

sudo a2ensite monitor-ssl.conf
sudo a2dissite 000-default.conf


# 9.5 KONFIGURASI FIREWALL (UFW)
sudo ufw allow 22/tcp
sudo ufw allow 53/udp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 161/udp
sudo ufw --force enable
sudo ufw status


# 10. START SEMUA SERVICE
sudo systemctl restart apache2
sudo systemctl restart cron
sudo systemctl enable apache2


# 11. KONFIGURASI SNMP MIKROTIK
/snmp set enabled=yes contact="ahmads@ahmadshofawi.lab-smk.xyz" location="Ruang Server SMK" trap-version=2
/snmp community set [ find default=yes ] name=public read-access=yes addresses=192.168.30.10/32


# ============================================================
# AKSES CACTI : https://monitor.lab-smk.xyz
# LOGIN       : admin / admin (ganti saat pertama login)
# ============================================================
