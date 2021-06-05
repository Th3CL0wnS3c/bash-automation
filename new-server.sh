#!/bin/bash

# --------------------------------------------------------------------------------------------------
# Script  : new-server.sh
# Version : 1.0
# Date    : 05/06/2021
#
# Summary     : Used to quickly securing a debian server. Tasks list :
#				 - SSH secure config (including TOTP)
#				 - sudo rights
#				 - Security upgrades
#				 - Basic SSH Fail2ban
#				 - Setup slack login script (send slack alert at each ssh login)
#
#	V2 updates planned : Add multiples SSH users
#						 Check why slack script doesn't work once installed
# --------------------------------------------------------------------------------------------------

# Variables declaration

red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
rst=`tput sgr0`
yellow=`tput setaf 3`
errfile=error.log

# Functions Declaration

progress()
{
	PID=$!
	i=1
	while [ -d /proc/$PID ]
	do
		BAR='[.....]'
		for i in {1..7}; do
			echo -ne "\r${BAR:0:$i}"
			sleep .1
		done
	done
	echo -e "\n"
}

check-err()
{
	if [[ $? > 0 ]];then
    		echo -e "${red}[ERROR]${rst} Something went wrong, please check $errfile for more information\n"
    		exit 1
	else
    		echo "[OK]" > /dev/null
	fi
}

check_root()
{
	if [[ $EUID -ne 0 ]]; then
  	 	echo "This script must be run as root, use sudo "$0" instead" 1>&2
   		exit 1
	fi
}

list_interface()
{
	ip a | grep inet | cut -d " " -f 6 | sed 's/^127.*//' | sed 's/^[a-z].*//' |  sed 's/^\:\:.*//' | sed '/^$/d' > interfaces.txt
	cat interfaces.txt | while read f1
        do
          echo "1 - $f1" > int.txt
        done
    rm -rf interfaces.txt
}

user_input()
{
	read -p "Enter SSH port number (type ran for random port) : " sshprt
	list_interface
    cat int.txt
	read -p "Choose Server IP : " ipchoice
	temp="p"
	ipc=$(echo "$ipchoice$temp")
	case $ipchoice in
		(*[1-9]*) ip=$(sed -n "$ipc" int.txt | cut -d " " -f 3 | sed 's/\/.*//');;
		*) echo  -e "${red}Selected IP is not valid, please try again !${rst}\n"
	esac
	read -p "Enter Username allowed to SSH : " usr
	read -p "Enable TCP Forwarding ? " uitcpfw
	read -p "Choose SSH Auth Mode (1 -PubKey , 2- 2FA , 3- 3FA)" uiauthmode
	read -p "Configure SSH Slack Alert ? " slack_alert
	read -p "Configure sudo rights for a specific user ? " sudoconfig
	case $sudoconfig in
		y|Y|yes|YES) read -p "Enter username for sudo rights : " sudousr ;;
		n|N|no|NO) echo "Don't configure sudo rights" > /dev/null ;;
		*) echo "BAD response, default set to no" > /dev/null ;;
	esac
}

urldecode()
{
	python3 -c "import sys, urllib.parse as ul; print(ul.unquote_plus(sys.argv[1]))" $1
}

ssh_basic_conf()
{
	sed -i "s/^\#Port.*/Port\ ${sshprt}/" /etc/ssh/sshd_config
	sed -i 's/^\#AddressFamily.*/AddressFamily\ inet/' /etc/ssh/sshd_config
	sed -i "s/^\#ListenAddress\ 0\.0\.0\.0/ListenAddress\ ${ip}/" /etc/ssh/sshd_config
	sed -i 's/^\#Protocol.*/Protocol\ 2/' /etc/ssh/sshd_config
	sed -i 's/^\#LogLevel.*/LogLevel\ VERBOSE/' /etc/ssh/sshd_config
	sed -i '/^\#RekeyLimit.*/a Ciphers\ chacha20\-poly1305\@openssh.com\,aes256\-gcm\@openssh\.com\,aes256\-ctr' /etc/ssh/sshd_config
	sed -i '/^\Ciphers.*/a MACs hmac\-sha2\-256\-etm\@openssh\.com\,hmac\-sha2\-512\-etm\@openssh\.com' /etc/ssh/sshd_config
	sed -i 's/^\#LoginGraceTime.*/LoginGraceTime\ 1m/' /etc/ssh/sshd_config
	sed -i 's/^\#PermitRootLogin.*/PermitRootLogin\ no/' /etc/ssh/sshd_config
	sed -i 's/^\#StrictModes.*/StrictModes\ yes/' /etc/ssh/sshd_config
	sed -i 's/\#MaxAuthTries.*/MaxAuthTries\ 3/' /etc/ssh/sshd_config
	sed -i 's/\#MaxSessions.*/MaxSessions\ 2/' /etc/ssh/sshd_config
	sed -i 's/\#PubKeyAuthentication.*/PubKeyAuthentication\ yes/' /etc/ssh/sshd_config
	sed -i 's/^\#AuthorizedKeysFile.*/AuthorizedKeysFile\ \.ssh\/authorized\_keys/' /etc/ssh/sshd_config
	sed -i "/^AuthorizedKeysFile.*/a AllowUsers\ ${usr}" /etc/ssh/sshd_config 
	sed -i 's/^\#IgnoreRhosts.*/IgnoreRhosts\ yes/' /etc/ssh/sshd_config
	sed -i 's/^\#PasswordAuthentication.*/PasswordAuthentication\ no/' /etc/ssh/sshd_config
	sed -i 's/^\#PermitEmptyPasswords.*/PermitEmptyPasswords\ no/' /etc/ssh/sshd_config
	sed -i 's/^ChallengeResponseAuthentication\ no/ChallengeResponseAuthentication\ yes/' /etc/ssh/sshd_config
	sed -i "s/^\#AllowAgentForwarding.*/AllowAgentForwarding\ no/" /etc/ssh/sshd_config
	sed -i "s/^\#AllowTcpForwarding.*/AllowTcpForwarding\ ${tcpfw}/" /etc/ssh/sshd_config
	sed -i 's/^\X11Forwarding.*/X11Forwarding\ yes/' /etc/ssh/sshd_config
	sed -i 's/^\#PrintLastLog.*/PrintLastLog\ yes/' /etc/ssh/sshd_config
	sed -i 's/^\#TCPKeepAlive.*/TCPKeepAlive\ no/' /etc/ssh/sshd_config
	sed -i 's/^\#Banner.*/Banner\ \/etc\/banner/' /etc/ssh/sshd_config
}

setup_fail2ban()
{
	printf "[sshd]\n" > /etc/fail2ban/jail.local
	printf "enabled = true\n" >> /etc/fail2ban/jail.local	
	printf "maxretry = 10\n" >> /etc/fail2ban/jail.local	
	printf "findtime = 43200\n" >> /etc/fail2ban/jail.local
	printf "bantime = 86400\n" >> /etc/fail2ban/jail.local	
	printf "port = $sshprt\n" >> /etc/fail2ban/jail.local	
	printf "banaction = iptables-multiport\n" >> /etc/fail2ban/jail.local	
	printf "[Init]\n" > /etc/fail2ban/action.d/iptables-common.local
	printf "blocktype = DROP" >> /etc/fail2ban/action.d/iptables-common.local
}

setup_unattended_upgrades()
{
	printf 'APT::Periodic::Update-Package-Lists "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
	printf 'APT::Periodic::Unattended-Upgrade "1";\n' >> /etc/apt/apt.conf.d/20auto-upgrades
	printf 'APT::Periodic::AutocleanInterval "7";\n' >> /etc/apt/apt.conf.d/20auto-upgrades
}

setup_slack()
{
	mkdir /home/$usr/.scripts/
	wget https://raw.githubusercontent.com/Th3CL0wnS3c/bash-automation/master/ssh-login-alert.sh -P /home/$usr/.scripts/ 
	sed -i "s#SLACK_HOOK_URL#${slack_url}#g" /home/$usr/.scripts/ssh-login-alert.sh #Using # as sed delimiter to avoid errors cause $slack_url contains /
	sed -i "s/server\.domain\.com/${fqdn}/g" /home/$usr/.scripts/ssh-login-alert.sh
	chown -R $usr:$usr /home/$usr/.scripts/
	chmod 711 /home/$usr/.scripts/ssh-login-alert.ssh-login-alert
	echo "session optional setuid /home/$usr/.scripts/ssh-login-alert.sh" >> /etc/pam.d/sshd
}

install_totp()
{
	   echo -e "\n${blue}====${rst} Installing Google Authenticator for TOTP ${blue}====${rst}\n"
	   apt-get -y install libpam-google-authenticator 1> /dev/null 2> $errfile &
	   progress
	   check-err && echo -e "\n${green}==> Gooble Authenticator installed${rst}\n"
}

configure_totp()
{
	#Conf TOTP and send log and QR to log.txt
	printf 'y\ny\ny\nn\ny\n' | su - $usr -c "google-authenticator"  1> /home/$usr/log.txt & 2> /dev/null
	mkdir /home/$usr/TOTP/
	#Treat log.txt to export emergency codes and QR codes files
	sleep 5
	cat /home/$usr/log.txt | grep -A 5 "Your emergency scratch codes are:" > /home/$usr/TOTP/emergency_codes.txt
	qrurlbase=$(cat log.txt | grep "otpauth" | sed 's/.*\=otpauth/\otpauth/')
	urldecode $qrurlbase > qrurldecoded.txt
	qrurldecoded=$(cat qrurldecoded.txt)
	qrencode -m 2 -t utf8 $qrurldecoded > /home/$usr/TOTP/qrcode.txt
	rm -rf qrurldecoded.txt
	chown -R $usr:$usr /home/$usr/TOTP
	chmod 600 /home/$usr/TOTP/*
	rm -rf /home/$usr/log.txt
	check-err && echo -e "\n${green}==> Your 2FA codes has been setup. ${rst}\n"
}

configure_pamd()
{
	sed -i 's/\@include\ common\-password/\#\@include\ common\-password/g' /etc/pam.d/sshd
	sed -i '/\#\@include\ common\-password/a auth\ required\ pam\_google\_authenticator\.so\ nullok' /etc/pam.d/sshd
}


# Main Program

check_root

echo -e "\n${blue}====${rst} Installing basic packages ${blue}====${rst}\n"
apt-get -y install sudo openssh-server fail2ban unattended-upgrades curl git net-tools wget qrencode 1> /dev/null 2> $errfile &
progress
check-err && echo -e "\n${green}==> Packages successfully installed${rst}\n"

echo -e "\n${blue}====${rst} Requesting User Inputs ${blue}====${rst}\n"
user_input

# Setup Forwarding
case $uitcpfw in
	y|Y|yes|YES|Yes) 
		export tcpfw=yes
		read -p "Install Remote Sublime text ? : " sublime_text
		case $sublime_text in
			yes|YES|y|Yes) wget -O /usr/local/bin/rmate https://raw.github.com/aurora/rmate/master/rmate 1> /dev/null 2> $errfile &
						   progress
						   check-err
						   chmod a+x /usr/local/bin/rmate
						   check-err && echo -e "\n${green}==> Rmate successfully installed in /usr/local/bin ${rst}\n"
						   ;;
			no|NO|n|No) echo "don't install sublime text " > /dev/null;;
			*) echo "Default is no" > /dev/null;;
		esac;;	
	n|N|no|NO|No) export tcpfw=no;;
	*) echo "Bad value" & exit 0;;
esac

case $sshprt in
        ran|RAN) sshprt=$(awk -v min=20000 -v max=45000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}');;
        (*[1-9]*) echo "Fixed port by user, do nothing" > /dev/null;;
        "") echo -e "${red} ERROR ! supplied SSH port is empty, please try again !" ;;
        *) echo -e "${red} ERROR ! supplied SSH port is not valid, please try again !"; user_input ;;
esac

echo -e "\n${blue}====${rst} Setting Up SSH Configuration ${blue}====${rst}\n"
ssh_basic_conf 1> /dev/null 2> $errfile &
progress
check-err

# Configure Auth mode
case $uiauthmode in
	1) sed -i '/^UsePAM.*/a AuthenticationMethods\ publickey' /etc/ssh/sshd_config
	   echo -e "\n${green}==> SSH Configuration Complete${rst}\n";;
	2) install_totp
	   configure_totp
	   configure_pamd
	   sed -i '/^UsePAM.*/a AuthenticationMethods\ publickey\,keyboard\-interactive' /etc/ssh/sshd_config
	   echo -e "\n${green}==> SSH Configuration Complete${rst}\n";;
	3) install_totp
	   configure_totp
	   configure_pamd
	   sed -i '/^UsePAM.*/a AuthenticationMethods\ publickey\,password\ publickey\,keyboard\-interactive' /etc/ssh/sshd_config
	   echo -e "\n${green}==> SSH Configuration Complete${rst}\n";;
esac

#Configure Slack Alert
case $slack_alert in
	y|Y|YES|yes|Yes) echo -e "\n${blue}====${rst} Requesting Slack Data ${blue}====${rst}\n"
					 read -p "Enter Slack Hook URL : " slack_url
					 read -p "Enter Server FQDN : " fqdn
					 echo -e "\n${blue}===${rst} Configuring Slack Alert for SSH Logins ${blue}===${rst}\n"
					 setup_slack 1> /dev/null 2> $errfile &
					 progress
				  	 check-err && echo -e "\n${green}==> Slack alert set !${rst}\n";;
	n|N|NO|no|No) echo "Don't configure slack alert" > /dev/null;;
	*) echo "Bad argument, default to no " > /dev/null;;
esac

echo -e "\n${blue}====${rst} Setting up fail2ban ${blue}====${rst}\n"
setup_fail2ban 1> /dev/null 2> $errfile &
progress
check-err && echo -e "\n${green}==> Fail2ban successfully configured${rst}\n"

echo -e "\n${blue}====${rst} Setting up unattended-upgrades ${blue}====${rst}\n"
setup_unattended_upgrades 1> /dev/null 2> $errfile &
progress
check-err && echo -e "\n${green}==> Unattended-Upgrades successfully configured${rst}\n"

case $sudoconfig in
	y|Y|YES|yes|Yes) sed -i "/^root.*/a $sudousr\tALL\=\(ALL\:ALL\)\ ALL" /etc/sudoers;;
	n|N|NO|no|No) echo "Don't configure sudo rights" > /dev/null;;
	*) echo "Bad argument, default to no " > /dev/null;;
esac

# Restart services
echo -e "\n${blue}====${rst} Restarting Services ${blue}====${rst}\n"
/etc/init.d/fail2ban restart 1> /dev/null 2> $errfile &
/etc/init.d/ssh restart 1> /dev/null 2> $errfile &
/etc/init.d/unattended-upgrades restart 1> /dev/null 2> $errfile &
/etc/init.d/sudo restart 1> /dev/null 2> $errfile &
check-err && echo -e "\n${green}==> All services have been restarted ${rst}\n"

echo -e "\n${green}==> User $usr has now sudo rights ${rst}\n"
echo -e "\n${green}==>${rst} Your SSH Port is : ${green}$sshprt${rst}\n"
echo -e "\n${blue}====${rst} Please configure your TOTP token using generated files ${blue}====${rst}\n"
echo -e "\n${green}==>${rst} You will find the QR Code and emergency codes for 2FA in /home/$usr/TOTP ${rst}\n"
echo -e "\n${yellow}==== [WARNING] If you chose to use publickey auth (2,3), make sure to have your public key in /home/$usr/.ssh/authorized_keys ${yellow}====${rst}\n"