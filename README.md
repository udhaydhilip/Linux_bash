rhel-ad-domain-join/
├── add_rhel_to_domain.sh
├── README.md
├── .gitignore
└── LICENSE

# 🔗 RHEL to Active Directory Domain Join Script

Automated Bash script to join a Red Hat Enterprise Linux (RHEL) system to a Windows Active Directory (AD) domain using `realmd`, `sssd`, `samba`, and `winbind`.

---

## 👨‍💻 Author

**Udaya Dhilip**  
Lead Platform Engineer  
Skills: Linux, Bash, AWS, Terraform, Ansible, Git, Docker, Kubernetes, Networking

---

## 🚀 Features

- Interactive prompts for domain info, hostname, and IP configuration
- Detects active network interface and assigns static IP
- Installs all required packages
- Joins domain using both `realm` and `net ads`
- Configures Samba, SSSD, DNS, `/etc/hosts`, and `/etc/resolv.conf`
- Handles domain rejoin logic if services fail
- Restarts and enables required services
- Creates error and status reports

---

## 🧰 Requirements

- RHEL 8+
- Root access
- Domain admin credentials

---

## ⚙️ Usage

chmod +x add_rhel_to_domain.sh
sudo ./add_rhel_to_domain.sh

🧪 Post-Join Verification

realm list
klist -k /etc/krb5.keytab
wbinfo -p
wbinfo -t
wbinfo -u
wbinfo -g
getent passwd <domain-user>
id <domain-user>
su - <domain-user>

📁 Generated or Modified Files

/etc/samba/smb.conf
/etc/sssd/sssd.conf
/etc/resolv.conf
/etc/hosts
/tmp/domain_adding_error.txt
/tmp/authselect_error.txt
/tmp/domain_join_report.txt