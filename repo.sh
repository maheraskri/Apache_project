#!/bin/bash
if [ -e "/dev/sr0" ] ; then
    	mount /dev/sr0 /mnt && cd /mnt && mkdir /repo # mount CD and create dir
    	tar cvf - . | (cd /repo/; tar xvf -)  # Copy media content to local dir
else
	echo " Insert a CD  and try again"
fi
# Remove existing config && create new config file
rm -rf /etc/yum.repos.d/* && touch /etc/yum.repos.d/local.repo
# Configure the new repo
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
dnf update && dnf install createrepo httpd mod_ssl  -y
createrepo /repo/ && cp /etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial /repo 
systemctl enable --now httpd
# Open ports in firewalld
for i in http https ; do
        firewall-cmd --add-service=$i --permanent 2>/dev/null && firewall-cmd --reload
done
# Config apache
sed -i 's/^DocumentRoot.*/DocumentRoot "\/repo"/' /etc/httpd/conf/httpd.conf
sed -i 's/^<Directory "\/var\/www\/html"/<Directory "\/repo"/' /etc/httpd/conf/httpd.conf
rm -rf /etc/httpd/conf.d/welcome*
# Create ACL && set Selinux context 
setfacl -R -m u:apache:rwx  /repo && semanage fcontext -m -t httpd_sys_content_t "/repo(/.*)?" && restorecon -Rv /repo
# generate SSL cert
openssl req -x509 -nodes -days 365 --newkey rsa:2048 -keyout /etc/pki/tls/private/myrepo.key -out /etc/pki/tls/certs/myrepo.crt -subj "/CN=$HOSTNAME"
# Modify SSL config file 
sed -i 's/^SSLCertificateFile.*/SSLCertificateFile \/etc\/pki\/tls\/certs\/myrepo.crt/' /etc/httpd/conf.d/ssl.conf
sed -i 's/^SSLCertificateKeyFile.*/SSLCertificateKeyFile \/etc\/pki\/tls\/private\/myrepo.key/' /etc/httpd/conf.d/ssl.conf
# Redirect http traffic to https
touch /etc/httpd/conf.d/myrepo.conf
cat >> /etc/httpd/conf.d/myrepo.conf << SIG
<VirtualHost *:80>
ServerName 10.1.1.9
Redirect "/" "https://10.1.1.9/"
</VirtualHost>
SIG
# Restart Apache && Unmount CD device
systemctl restart httpd && umount /mnt
