#!/bin/bash
# Check CD device availability
if [ -e "/dev/sr0" ] ; then
    	mount /dev/sr0 /mnt && cd /mnt && mkdir /repo # mount the CD and create a Directory
    	tar cvf - . | (cd /repo/; tar xvf -)  # Copy media content to the local directory by 
else
	echo " Insert a CD  and try again"
fi
# Removing any existing config files and create new config file
rm -rf /etc/yum.repos.d/* && touch /etc/yum.repos.d/local.repo
# Configure the local YUM/DNF repository
cat >> /etc/yum.repos.d/local.repo << EOF
[LocalRepo_AppStream]
name=LocalRepo_AppStream
enabled=1
gpgcheck=1
baseurl=file:///repo/AppStream/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
[LocalRepo_BaseOS]
name=LocalRepo_BaseOS
enabled=1
gpgcheck=1
baseurl=file:///repo/BaseOS/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF
# Install Apache with mod_ssl and createrepo package
dnf update && dnf install createrepo httpd mod_ssl  -y
# creating the repo directory and copy the official gpg key and start Apache  
createrepo /repo/ && cp /etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial /repo 
systemctl enable --now httpd
# opening the http and https ports on firewall
for i in http https ; do
        firewall-cmd --add-service=$i --permanent 2>/dev/null && firewall-cmd --reload
done
# Using sed to modify the DocumentRoot and the Directory in Apache config file && delete the default welcome page
sed -i 's/^DocumentRoot.*/DocumentRoot "\/repo"/' /etc/httpd/conf/httpd.conf
sed -i 's/^<Directory "\/var\/www\/html"/<Directory "\/repo"/' /etc/httpd/conf/httpd.conf
rm -rf /etc/httpd/conf.d/welcome*
# Create an ACL to give Apache full access && setting the Selinux context type on the repo directory 
setfacl -R -m u:apache:rwx  /repo && semanage fcontext -m -t httpd_sys_content_t "/repo(/.*)?" && restorecon -Rv /repo
# generate a self signed certifiacte and a private key for the TLS encryption
openssl req -x509 -nodes -days 365 --newkey rsa:2048 -keyout /etc/pki/tls/private/myrepo.key -out /etc/pki/tls/certs/myrepo.crt -subj "/CN=$HOSTNAME"
# Modify the SSL config file with sed to the path of the certificate and the key 
sed -i 's/^SSLCertificateFile.*/SSLCertificateFile \/etc\/pki\/tls\/certs\/myrepo.crt/' /etc/httpd/conf.d/ssl.conf
sed -i 's/^SSLCertificateKeyFile.*/SSLCertificateKeyFile \/etc\/pki\/tls\/private\/myrepo.key/' /etc/httpd/conf.d/ssl.conf
# create a config file in the Apache to redirect http traffic to https
touch /etc/httpd/conf.d/myrepo.conf
cat >> /etc/httpd/conf.d/myrepo.conf << SIG
<VirtualHost *:80>
ServerName 10.1.1.9
Redirect "/" "https://10.1.1.9/"
</VirtualHost>
SIG
# Restart the Apache service and unmount the CD device
systemctl restart httpd && umount /mnt
