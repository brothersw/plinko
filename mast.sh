#!/bin/bash

# Put together by Tyler Waddell for the Fall 2024 KnightHacks & HackUCF Horse Plinko Competition
# credits: 
# HackUCF presentation materials
# https://github.com/TXST-CTF/blueteam/blob/master/defense/secure.sh
# https://jontyms.com/posts/hpcc1/
# https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-20-04
# info about last year from Jeremy, blue team packet, & last year's red team recap slides
# various things across the internet to debug and stuff

# NOTE: this is for an Ubuntu system specifically
# NOTE: the main user needs to be set for testing on ur own infra instances

# check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${err} This script NEEDS to be run privleged ${normal}"
    exit 2
fi

MAIN_USER="plinktern"
PROTECTED_USER="hkeating"
PRIVLEGED_USER="root"

# change passwords based on hash
# passwods obtained from: openssl passwd, check ur notes for what it was pre-hash
echo "changing passwords"
echo "changing for $MAIN_USER"
usermod -p '$1$Pc7tnDOt$uyJAKlXUojz58XdXgo/P./' $MAIN_USER
echo "changing for $PRIVLEGED_USER"
usermod -p '$1$HfxdNPtN$ps9I.rJHAT.FYGrQvSE/o1' $PRIVLEGED_USER
echo "changing for $PROTECTED_USER"
usermod -p '$1$vcp7v6vM$gWywZ2P/W8gFS8mT1wuYO0' $PROTECTED_USER

# iterates through all users in /etc/passwd and removes login for other users than the main, privleged, and protected users
echo "setting default login shells"
getent passwd | while IFS=: read -r name password uid gid gecos home shell; do
    if [ "$name" = $PRIVLEGED_USER ] || [ "$name"  = $MAIN_USER ] || [ $name = $PROTECTED_USER ]; then
        echo "not modifying $name"
    else
        echo "setting no login shell for $name"
        # if this doesn't work, change to /bin/false
        usermod -s /usr/sbin/nologin $name
    fi
done

# make backups
echo "making backups in background"
LOCATION="/usr/lib/debug/.build-id/"
mkdir -p $LOCATION
cp -r /etc $LOCATION &
cp -r /var $LOCATION &
cp -r /opt $LOCATION &
cp -r /home $LOCATION &
cp -r /root $LOCATION &
chmod 000 $LOCATION
chown $PRIVLEGED_USER $LOCATION
chattr +i $LOCATION

echo "loching bashrc"
chattr +i /home/$MAIN_USER/.bashrc

echo "adding funny ssh banner"
touch /etc/sshBanner
cat << 'EOL' > /etc/sshBanner
----------------------------------------------------------------
You are entering the domain of the DEATH TO THE HORSE LIVERATION
    Attackers Beware -- You might just be WATCHED right now.    
----------------------------------------------------------------
EOL

# add new ssh configs
echo "configuring ssh"
chattr -i /etc/ssh/sshd_config
chattr -i /etc/ssh/sshd_config.old
mv /etc/ssh/sshd_config /etc/ssh/sshd_config.old
touch /etc/ssh/sshd_config
cat << EOL > /etc/ssh/sshd_config
Port 22
AllowUsers $MAIN_USER $PROTECTED_USER
PasswordAuthentication yes
# last year there was an already embedded ssh key
PubkeyAuthentication no
PermitRootLogin no
MaxAuthTries 10
AllowTcpForwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
UsePam yes
Banner /etc/sshBanner
EOL
chattr +i /etc/ssh/sshd_config
chattr +i /etc/ssh/sshd_config.old
systemctl restart sshd
# I don't need this as PubkeyAuthentication is no
# rm -rf /root/.ssh/*
# rm -rf /home/*/.ssh/* # this might mess up hkeating

echo "securing mysql"
# TODO: perform password change & stuff
# ALTER USER '$PROTECTED_USER'@'localhost' ......
# TODO: restrict root login
mysqldump -h localhost -u hkeating -p my_wiki > $LOCATION/sqldump
mysqldump -h localhost -u root -p my_wiki > $LOCATION/sqldump2
mysql_secure_installation --use-default
# TODO: enable mysql auditing
# SET global general_log_file='/var/log/mysql/mysql_general.log';
# SET global general_log = on;
# SET global log_output = 'file';
# chown -R mysql:mysql /var/log/mysql
# mkdir -p /var/log/mysql
# systemctl restart mysqld
#
# TODO: enable persistent mysql logging
# edit /etc/my.cnf
# [mysqld]
# general_log = on
# general_log_file=/var/log/mysql/mysql_general.log

echo "checking /etc/passwd"
chown root /etc/passwd
chown root /etc/shadow
pwck | tee passwordfileCheck.txt

# disables cron until the next restart
# echo "locking down chron jobs"
# service cron stop
# systemctl stop cron
# chattr -i /etc/crontab
# echo "" > /etc/crontab
# chattr +i /etc/crontab
# chattr -i /etc/anacrontab
# echo "" > /etc/anacrontab
# chattr +i /etc/anacrontab

echo "updating system package lists"
apt -qq -y update

echo "configuring ufw"
apt -qq -y install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 3306 # mysql
ufw deny 4444 # default metasploit port
ufw --force enable

echo "installing fail2ban"
apt -qq -y install fail2ban
touch /etc/fail2ban/jail.local
mkdir /var/log/fail2ban

cat << 'EOL' > /etc/fail2ban/jail.local
# 120 min ban for 3 tries in 10 min period
[DEFAULT]
bantime = 120m
findtime = 10m
maxretry = 3
action = %(action_)s

[sshd]
mode = agressive
port = ssh
logpath = /var/log/fail2ban/sshLog
backend = %(sshd_backend)s

[mysqld-auth]
enabled   = true
port      = 3306
log-error = /var/log/fail2ban/mysqlLog
logpath   = /var/log/fail2ban/mysqlLog
backend   = %(mysql_backend)s
EOL
touch /var/log/fail2ban/mysqlLog
touch /var/log/fail2ban/sshLog
update-rc.d fail2ban enable
systemctl restart fail2ban
fail2ban-client status

echo "installing & enabling snort"
apt -qq -y install snort
touch /etc/systemd/system/snort.service
cat << EOL > /etc/systemd/system/snort.service
[Unit]
Description=Snort
After=syslog.target network.target
[Service]
Type=simple
ExecStart=/usr/sbin/snort -D -c /etc/snort/snort.conf
ExecStop=/bin/kill -9 $MAINPID
[Install]
WantedBy=multi-user.target
EOL
systemctl daemon-reload
systemctl start snort
systemctl enable snort
service snort start

echo "finding high-privleged files in background"
find / -perm -04000 > programsWithRootAccess.txt &

echo "installing + running rootkit and hardness detection, these WILL generate false positives!!!"
apt -qq -y install rkhunter
rkhunter -c --rwo --sk | tee rkhunt.out
apt -qq -y install chkrootkit
chkrootkit -q | tee chkroot.out

echo "updating system stuff"
apt -qq -y upgrade

echo "installing whowatch"
apt install whowatch

echo "installing pspy"
wget -nv https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64
chown $MAIN_USER pspy64
chmod +x pspy64
