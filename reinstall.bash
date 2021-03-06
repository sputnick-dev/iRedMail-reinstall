#!/bin/bash

if ((UID!=0)); then
    echo >&2 "$0 need root privileges"
    exit 1
fi

set -eox pipefail

rm -f /etc/apt/sources.list.d/sogo*
sed -i 's@.*packages\.inverse\.ca/SOGo/nightly/.*@# &/' /etc/apt/sources.list
apt-get update -y
apt-get install -y wget curl rsync
if ! file $(readlink -f $(type -p rename)) | grep -qi Perl; then
    cd /usr/local/bin
    wget 'https://metacpan.org/raw/RMBARKER/File-Rename-0.20/rename.PL?download=1' -O rename
    chmod +x rename
    hash -p /usr/local/bin/rename rename
fi

if ! mysql -e '' &>/dev/null; then
    cat<<-EOF >&2
	Please, create a /root/.my.cnf file with credentials, example : 

	[client]
	user=root
	password="foobarbase"
	EOF
fi
bkpdir=/root/mysql_backup_reinstall_iRedMail
mkdir -p $bkpdir
for db in $(mysql -e "SHOW DATABASES" | awk 'NR>2 && !/performance_schema/'); do
    mysqldump --skip-lock-tables --events --quote-names --opt $db | gzip -9 - > $bkpdir/${db}_dump-$(date +%Y%m%d%H%M).sql.gz
done

mysql<<EOF
DROP DATABASE amavisd;
DROP DATABASE iredadmin;
DROP DATABASE roundcubemail;
DROP DATABASE sogo;
DROP DATABASE vmail;
EOF
systemctl stop mysql
systemctl disable mysql
mv /var/vmail /var/vmail.$(date +%y%m%d)
cp -a /etc/nginx /etc/nginx-$(date +%y%m%d)
rm -f /etc/nginx/sites-enabled/*default* /etc/nginx/templates/sogo.tmpl /etc/nginx/templates/redirect_to_https.tmpl
apt-get purge sogo roundcube\* postfix\* apache\* php5\* dovecot\* amavis\* clamav\* spamassassin\* logwatch freshclam
rm /etc/fail2ban/filter.d/roundcube.iredmail.conf
cd /root
rename "s/iRed.*/$&.$(date +%Y%m%d)/g" iRed*
cd /opt/
rename "s/iRed.*/$&.$(date +%Y%m%d)/g" iRed*
mv www www-$(date +%Y%m%d)
unlink iredapd &>/dev/null || true
cd /root
iredversion=$(
    curl -s https://bitbucket.org/zhb/iredmail/downloads/ |
    awk -F'[<>]' '/tar\.bz2/{print $2;exit}'
)
wget https://bitbucket.org/zhb/iredmail/downloads/$iredversion
tar xjvf $iredversion
cd ${iredversion%.tar.bz2}
bash iRedMail.sh && {
    cd /var/
    rsync -avP vmail.*/ vmail/
    rm -rf vmail.*
    for db in amavisd iredadmin roundcubemail sogo vmail; do
        zcat $bkpdir/${db}_dump-*.sql.gz | mariadb $db
    done 

	cat<<-EOF
	Think restoring sogo backups in /var/vmail/backups for calendar and contacts :

	cd /var/vmail/backups/sogo
	tar xjvf dirX.tar.bz2
	sogo-tool restore -p dirX you@domain.tld
	sogo-tool restore -f ALL dirX you@domain.tld

	https://docs.iredmail.org/errors.html#recipient-address-rejected-sender-is-not-same-as-smtp-authenticate-username
	for multiple senders
	EOF
}
