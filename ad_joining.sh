#!/bin/bash

# =========================
# Script: add_rhel_to_domain.sh
# Author : YOUR NAME HERE
# Email  : your.email@example.com
# Date   : $(date +%Y-%m-%d)
# Purpose: Automatically join RHEL to Active Directory domain
# =========================

# ===== Get User Inputs =====
read -p "Enter Domain Name (e.g., gora.local): " DOMAIN
read -p "Enter Domain Controller IP Address: " DOMAIN_DC
read -p "Enter Domain Admin Username (e.g., Administrator): " DOMAIN_USER
read -p "Enter the system hostname (without domain): " HOST
read -p "Enter the IP address to assign RHEL: " IPADDR
read -s -p "Enter password for domain user $DOMAIN_USER: " DOMAIN_PASS
echo ""

# ===== Global Variables =====
REALM=$(echo "$DOMAIN" | awk '{print toupper($0)}')
WORKGROUP=$(echo "$DOMAIN" | cut -d. -f1 | awk '{print toupper($0)}')
GATEWAY="192.168.1.1"
DNS="$DOMAIN_DC"
SEARCH_DOMAIN="$DOMAIN"
DOMAIN_CRED="$DOMAIN_USER%$DOMAIN_PASS"
DOMAIN_ERROR_LOG="/tmp/domain_adding_error.txt"
AUTHSELECT_ERROR_LOG="/tmp/authselect_error.txt"
REPORT_FILE="/tmp/domain_join_report.txt"
HOSTNAME="${HOST}.${DOMAIN}"

# ===== Show Author Info =====
echo "======================================"
echo "Script: add_rhel_to_domain.sh"
echo "Author: YOUR NAME HERE"
echo "Date  : $(date +%Y-%m-%d)"
echo "======================================"

# ===== Hostname Setup =====
hostnamectl set-hostname "$HOSTNAME" 2>> "$DOMAIN_ERROR_LOG"

# ===== Detect Network Interface =====
IFACE=$(nmcli -t -f NAME c show | grep -E 'System eth0|ens160|enp0s3' | head -n 1)

# ===== Configure Network =====
nmcli con mod "$IFACE" ipv4.addresses "$IPADDR/24" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS" \
    ipv4.dns-search "$SEARCH_DOMAIN" \
    ipv4.method manual

nmcli con down "$IFACE"
nmcli con up "$IFACE"
ip a show "$IFACE"

# ===== Update /etc/resolv.conf & /etc/hosts =====
echo -e "search $SEARCH_DOMAIN\nnameserver $DNS" > /etc/resolv.conf
grep -q "$HOSTNAME" /etc/hosts || echo "$IPADDR $HOSTNAME $HOST" >> /etc/hosts

# ===== Install Required Packages =====
dnf install -y realmd sssd samba samba-common samba-winbind samba-winbind-clients oddjob oddjob-mkhomedir adcli krb5-workstation

# ===== Join Domain =====
echo "$DOMAIN_PASS" | realm join --user="$DOMAIN_USER" "$DOMAIN" --install=/ 2>> "$DOMAIN_ERROR_LOG"
echo "$DOMAIN_PASS" | net ads join -U "$DOMAIN_CRED" 2>> "$DOMAIN_ERROR_LOG"

# ===== Configure /etc/samba/smb.conf =====
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = $WORKGROUP
   realm = $REALM
   security = ADS
   kerberos method = secrets and keytab
   dedicated keytab file = /etc/krb5.keytab

   winbind use default domain = true
   winbind enum users = yes
   winbind enum groups = yes
   winbind nss info = rfc2307
   winbind offline logon = true

   idmap config * : backend = tdb
   idmap config * : range = 3000-7999
   idmap config $WORKGROUP : backend = rid
   idmap config $WORKGROUP : range = 10000-999999

   template homedir = /home/%U
   template shell = /bin/bash
EOF

# ===== Configure /etc/sssd/sssd.conf =====
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMAIN
config_file_version = 2
services = nss, pam

[domain/$DOMAIN]
ad_domain = $DOMAIN
krb5_realm = $REALM
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
fallback_homedir = /home/%u
default_shell = /bin/bash
use_fully_qualified_names = False
ldap_id_mapping = True
EOF

chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf

# ===== NSS Configuration =====
sed -i '/^passwd:/c\passwd:     files sss winbind' /etc/nsswitch.conf
sed -i '/^group:/c\group:      files sss winbind' /etc/nsswitch.conf
sed -i '/^shadow:/c\shadow:     files sss' /etc/nsswitch.conf

# ===== Authselect & Services =====
authselect select sssd --force 2>> "$AUTHSELECT_ERROR_LOG"
authselect enable-feature with-mkhomedir --force 2>> "$AUTHSELECT_ERROR_LOG"

systemctl enable --now sssd smb nmb winbind 2>/dev/null
systemctl restart sssd smb nmb winbind 2>/dev/null

realm permit --all

# ===== Firewall Configuration =====
firewall-cmd --permanent --add-service=samba
firewall-cmd --permanent --add-service=kerberos
firewall-cmd --reload

# ===== Service Recovery: SSSD =====
systemctl is-active --quiet sssd
if [ $? -ne 0 ]; then
    echo "[!] sssd not active. Rejoining domain..."
    realm leave "$DOMAIN" 2>/dev/null
    echo "$DOMAIN_PASS" | realm join --user="$DOMAIN_USER" "$DOMAIN" --install=/ 2>> "$DOMAIN_ERROR_LOG"
    ls -l /etc/krb5.keytab
    echo "$DOMAIN_PASS" | kinit "$DOMAIN_USER"
    klist
    systemctl restart sssd winbind smb 2>/dev/null
fi

# ===== Service Recovery: WINBIND =====
systemctl is-active --quiet winbind
if [ $? -ne 0 ]; then
    echo "[!] winbind not active. Verifying configuration..."
    testparm -s
    echo "$DOMAIN_PASS" | net ads leave -U "$DOMAIN_CRED" 2>/dev/null
    echo "$DOMAIN_PASS" | net ads join -U "$DOMAIN_CRED" 2>> "$DOMAIN_ERROR_LOG"
    systemctl restart sssd smb nmb winbind 2>/dev/null
    systemctl enable sssd smb nmb winbind 2>/dev/null
fi

# ===== Post-run Report =====
{
echo "========== Domain Join Report =========="
echo "Hostname          : $HOSTNAME"
echo "IP Address        : $IPADDR"
echo "Domain Name       : $DOMAIN"
echo "Domain Controller : $DOMAIN_DC"
echo "Domain User       : $DOMAIN_USER"
echo ""
systemctl is-active --quiet sssd && echo "[✔] sssd: active" || echo "[✗] sssd: inactive"
systemctl is-active --quiet winbind && echo "[✔] winbind: active" || echo "[✗] winbind: inactive"
echo ""
echo "Test commands:"
echo "----------------------------------------"
echo "realm list"
echo "klist -k /etc/krb5.keytab"
echo "wbinfo -p"
echo "wbinfo -t"
echo "wbinfo -u"
echo "wbinfo -g"
echo "getent passwd <domain-user>"
echo "id <domain-user>"
echo "su - <domain-user>"
echo "----------------------------------------"
echo "Logs:"
echo "  - $DOMAIN_ERROR_LOG"
echo "  - $AUTHSELECT_ERROR_LOG"
echo "Date/Time: $(date)"
echo "========================================"
} > "$REPORT_FILE"

echo "[✔] Domain join completed. Report saved at: $REPORT_FILE"