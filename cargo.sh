#!/bin/bash

# Put together by Tyler Waddell for the Fall 2024 KnightHacks & HackUCF Horse Plinko Competition
# credits: 
# HackUCF presentation materials
# https://github.com/TXST-CTF/blueteam/blob/master/defense/secure.sh
# https://jontyms.com/posts/hpcc1/
# https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-20-04
# info about last year from Jeremy, blue team packet, & last year's red team recap slides
# various things across the internet to debug and stuff

# NOTE: this is for a Rocky 9 system specifically
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
usermod -p '$1$.mrlT69N$5Su8h5jpBBPyOMUw5e4Nn0' $MAIN_USER
echo "changing for $PRIVLEGED_USER"
usermod -p '$1$sotSJ86T$ts6heTKPcKFSZymZksF4c/' $PRIVLEGED_USER
echo "changing for $PROTECTED_USER"
usermod -p '$1$P6xuvvUC$RuomZyBXDK8uVcioLvI5Y/' $PROTECTED_USER

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

echo "Dissconnecting other ssh users"
CUR_SESSION=$(tty | sed 's|/dev/||')
SESSIONS_TO_KICK=$(who | awk -v current="$CUR_SESSION" '$2 ~ /pts/ && $2 != current {print $2}')
# Loop through the list of users and disconnect their sessions
for SESSION in $SESSIONS_TO_KICK; do
    echo "Disconnecting session: $SESSION"
    sudo pkill -t "$SESSION"
done

echo "adding funny ftp banner"
touch /etc/vsftpd/ftpBanner
cat << 'EOL' > /etc/vsftpd/ftpBanner
---------------------------------------------------------------- 
WARNING: This FTP server contains DANGEROUS information that may
create confusion and mania in the user. PROCEED WITH CAUTION!!!
----------------------------------------------------------------
EOL

echo "configuring vsftpd"
chattr -i /etc/vsftpd/vsftpd.conf
chattr -i /etc/vsftpd/vsftpd.conf.old
mv /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.old
touch /etc/vsftpd/vsftpd.conf
cat << EOL > /etc/vsftpd/vsftpd.conf
chown_uploads
chroot_local_user
anon_umask=044
data_connection_timeout=120
idle_session_timeout=150
max_clients=3
chown_username=plinktern
cmds_allowed=RETR,PWD,HELP
nopriv_user=games
banner_file=/etc/vsftpd/ftpBanner
xferlog_enable=YES
EOL
chattr +i /etc/vsftpd/vsftpd.conf
chattr +i /etc/vsftpd/vsftpd.conf.old
systemctl restart vsftpd

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
dnf install epel-release -y -q
dnf makecache --refresh -q

echo "configuring ufw"
dnf install ufw -y -q
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow ftp
ufw deny 4444 # default metasploit port
ufw deny 6200
ufw --force enable

# TODO: Test fail2ban
echo "installing fail2ban"
dnf install fail2ban -y
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

[vsftpd]
enabled = true
port    = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/fail2ban/ftpLog
EOL
touch /var/log/fail2ban/ftpLog
touch /var/log/fail2ban/sshLog
update-rc.d fail2ban enable
systemctl restart fail2ban
fail2ban-client status

# TODO: Test
echo "installing & enabling snort"
dnf install snort -y -q
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

echo "updating system stuff"
dnf upgrade --refresh

echo "installing whowatch"
dnf install whowatch -y -q

echo "installing pspy"
dnf install wget -y
wget -nv https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64
chown $MAIN_USER pspy64
chmod +x pspy64

echo "installing + running rootkit and hardness detection, these WILL generate false positives!!!"
dnf install rkhunter -y -q
rkhunter -c --rwo --sk | tee rkhunt.out
dnf install chkrootkit -y -q
chkrootkit -q | tee chkroot.out

# TODO: Test
echo "verifying packages"
rpm --verify --all | tee rpmVerify.txt

echo "copying backups to sonar"
scp -rp $LOCATION plinktern@172.16.16.5:/Backup/
