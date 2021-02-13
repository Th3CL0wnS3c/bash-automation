#!/bin/bash

#Variables

red=`tput setaf 1`
green=`tput setaf 2`
rst=`tput sgr0`
yellow=`tput setaf 3`
blue=`tput setaf 4`
apterrorfile=apt_error.log
giterrorfile=git_error.log
apacheerrfile=apache_error.log

#Functions

function conf_phpipam_vhost()
{
        echo -e "\n"
        read -p "Enter your domain name : " dom
        #echo -e "\n"
        read -p "Enter Host Name : " hostn
        #echo -e "\n"
        read -p "Enable SSL ?(requires cert and key to be acessible in ssl folder) (Default : No) : " enssl

        function conf-base()
        {
            sed -i "s/ipamhost/$hostn/g" confs/vhost.conf confs/vhost-ssl.conf
            sed -i "s/domain.com/$dom/g" confs/vhost.conf confs/vhost-ssl.conf
        }

        function conf-ssl()
        {
            echo -e "\n"
            keyfilename=$(ls ssl/ | grep ".key")
            certfilename=$(ls ssl/ | grep ".crt")
            sed -i "s/privatekeyforipam.key/$keyfilename/g" confs/vhost-ssl.conf
            sed -i "s/certforipam.pem/$certfilename/g" confs/vhost-ssl.conf   
        }

        echo -e "\n"
        case $enssl in
             Y|y)
                 conf-base
                 conf-ssl
                 vhostname=$hostn"."$dom"-ssl.conf"
                 mv confs/vhost-ssl.conf confs/$vhostname ;;
             N|n)
                 conf-base
                 vhostname=$hostn"."$dom".conf"
                 mv confs/vhost.conf confs/$vhostname ;;
             *)
                 conf-base
                 vhostname=$hostn"."$dom".conf"
                 mv confs/vhost.conf confs/$vhostname ;;
        esac
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

echo -e "${green}====${rst} Retrieving PHPipam sources ${green}====${rst}\n"

echo -e "${blue}[Checking if git is available]${rst}\n"
checkgit=$(git --version)
if [ -z checkgit ];then
 	echo -e "${blue}[Installing git]${rst}"
 	sudo apt-get install git 1> /dev/null 2>> $apterrorfile &
    progress
    check-err
 else
 	echo -e "${green}====${rst}\nGit is already installed !"
 fi

echo -e "${blue}[Cloning github repository]${rst}\n"
sudo git clone --recursive --quiet https://github.com/phpipam/phpipam.git /var/www/phpipam 1> /dev/null 2> $giterrorfile &
progress
check-err

echo -e "${green}====${rst} Configuring PHPipam ${green}====${rst}\n"

echo -e "${blue}[Configuring IPAM Database Credentials]\n${rst}"
sudo cp /var/www/phpipam/config.dist.php /var/www/phpipam/config.php
read -p -s  "Enter the password for phpipam user on mysql : " phpipamsqlpass
sudo sed -i "s/phpipamadmin/$phpipamsqlpass/g" /var/www/phpipam/config.php

echo -e "${blue}[Configuring apache vhost]\n${rst}"
conf_phpipam_vhost
sudo cp confs/$vhostname /etc/apache2/sites-available/

if [ ! -f confs/vhost-ssl.conf ];then
    echo -e "${blue}[Configuring SSL]\n${rst}"
    sudo cp ../ssl/$keyfilename /etc/ssl/private/
    sudo cp ../ssl/$certfilename /etc/ssl/certs/
    sudo chmod 640 /etc/ssl/private/$keyfilename
    sudo chmod 710 /etc/ssl/certs/$certfilename
    sudo chown root -R /etc/ssl/private/
    sudo chown root -R /etc/ssl/certs/
else
    echo "SSL not setup, nothing to do" > /dev/null
fi

echo -e "${blue}\n[Enabling configuration]\n${rst}"
sudo a2dissite 000-default.conf 1> /dev/null 2>> $apacheerrfile
sudo a2ensite $vhostname 2>&1 > /dev/null 
sudo systemctl reload apache2 2>&1 > /dev/null

echo -e "${green}====${rst}\nInstallation Complete, please go to https://$hostn.$dom to complete the setup${green}====${rst}\n"
