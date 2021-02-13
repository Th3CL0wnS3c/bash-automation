#!/bin/bash

red=`tput setaf 1`
green=`tput setaf 2`
rst=`tput sgr0`
yellow=`tput setaf 3`
blue=`tput setaf 4`
errfile=error.log
apterrfile=apt_error.log
phperrfile=php_error.log

progress()
{
	PID=$!
	i=1
	while [ -d /proc/$PID ]
	do
		BAR='.............................................'
		for i in {1..45}; do
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

check-root()
{
	if [[ $EUID -ne 0 ]]; then
   		echo "This script must be run as root, use sudo "$0" instead" 1>&2
   		exit 1
	fi
}

update-sys()
{
	echo -e "\n\n${green}====${rst} Updating APT Sources ${green}====${rst}\n"
	sudo apt-get update 1> /dev/null 2> $apterrfile &
	progress
	echo -e "${green}====${rst} Upgrading packages ${green}====${rst}\n"
	sudo apt-get upgrade -y 1> /dev/null 2>> $apterrfile &
	progress
	check-err
	echo -e "${green}====${rst} Upgrading system ${green}====${rst}\n"
	sudo apt-get dist-upgrade -y 1> /dev/null 2>> $apterrfile &
	progress
	check-err	
}

conf-sql()
{
	sudo mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$rootdbpass');FLUSH PRIVILEGES;" 1> /dev/null 2> mysql_error.log
	SECURE_MYSQL=$(expect -c "
	set timeout 5
	spawn sudo mysql_secure_installation
	expect \"Enter current password for root (enter for none):\"
	send \"$rootdbpass\r\"
	expect \"Change the root password?\"
	send \"n\r\"
	expect \"Remove anonymous users?\"
	send \"y\r\"
	expect \"Disallow root login remotely?\"
	send \"y\r\"
	expect \"Remove test database and access to it?\"
	send \"y\r\"
	expect \"Reload privilege tables now?\"
	send \"y\r\"
	expect eof
	")
	sudo mysql -e "USE mysql;SELECT User,Host,plugin FROM mysql.user;UPDATE user SET plugin='mysql_native_password' WHERE user='root';FLUSH PRIVILEGES;" 1> /dev/null 2> mysql_error.log
}

check-php-ver()
{
	v73=$(sudo apt-cache search php7.* | grep "7.3")
	v72=$(sudo apt-cache search php7.* | grep "7.2")
	v71=$(sudo apt-cache search php7.* | grep "7.1")
	v70=$(sudo apt-cache search php7.* | grep "7.0")

	if [ -z "$v73" ] && [ ! -z "$v72" ] && [ -z "$v71" ] && [ -z "$v70" ] ;then
	        version="2"
	elif [ ! -z "$v73" ] && [ -z "$v72" ] && [ -z "$v71" ] && [ -z "$v70" ] ;then
	        version="3"
	elif [ -z "$v73" ] && [ -z "$v72" ] && [ ! -z "$v71" ] && [ -z "$v70" ] ;then
	        version="1"
	elif [ -z "$v73" ] && [ -z "$v72" ] && [ -z "$v71" ] && [ ! -z "$v70" ] ;then
	        version="0"
	else
	        version="NotFound"
	fi
}

check-root
read -s -p "Enter a strong root password for the database : " rootdbpass
update-sys

echo -e "${green}====${rst} Installing mysql and apache2 packages ${green}====${rst}\n"
sudo apt-get install -y apache2 apache2-utils expect mariadb-server mariadb-client 1> /dev/null 2>> $apterrfile &
progress
check-err

echo -e "${green}====${rst} Configuring MySQL ${green}====${rst}\n"
conf-sql &
progress
check-err

echo -e "${green}====${rst} Installing PHP Modules ${green}====${rst}\n"
echo -e "${blue}[Checking PHP Version available] ${rst}"
check-php-ver
check-err
echo -e "\nphp version available : 7.$version \n"
echo -e "${blue}[Installing Modules] ${rst}\n"
sudo apt-get install -y php7.$version-fpm php7.$version-mysql php7.$version-common php7.$version-gd php7.$version-json php7.$version-cli php7.$version-curl php7.$version-ldap php7.$version-gmp php7.$version-mbstring php7.$version-simplexml php-pear libmcrypt-dev libapache2-mod-php7.$version 1> /dev/null 2>> $apterrfile &
progress
check-err
echo -e "${blue}[Installing PHP Dev] ${rst}\n"
yes '' | sudo apt-get install -y php7.$version-dev 1> /dev/null 2>> $apterrfile &
progress
check-err
echo -e "${blue}[Installing mcrypt] ${rst}\n"
sudo pecl channel-update pecl.php.net 1> /dev/null 2>> $phperrfile 
check-err
yes '' | sudo pecl install mcrypt-1.0.3 1> /dev/null 2>> $phperrfile &
progress
check-err

echo -e "${blue}[Enabling Modules] ${rst}\n"
sudo a2enmod php7.$version 1> /dev/null 2>> $phperrfile
sudo a2enmod ssl 1> /dev/null 2>> $phperrfile 
sudo sed -i '$a extension=mcrypt.so' /etc/php/7.$version/apache2/php.ini
sudo sed -i '$a extension=mcrypt.so' /etc/php/7.$version/cli/php.ini
sudo ln -s /etc/apache2/mods-available/rewrite.load /etc/apache2/mods-enabled/rewrite.load 1> /dev/null 2>> $phperrfile 

echo -e "${blue}[Reloading Apache] ${rst}\n"
sudo systemctl reload apache2 > /dev/null
