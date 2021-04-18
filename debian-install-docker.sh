#!/bin/bash

red=`tput setaf 1`
green=`tput setaf 2`
rst=`tput sgr0`
yellow=`tput setaf 3`
errfile=error.log

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

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root, use sudo "$0" instead" 1>&2
   exit 1
fi

echo -e "\n${green}====${rst} Installing Docker dependencies ${green}====${rst}\n"
sudo apt-get install -y  apt-transport-https ca-certificates curl gnupg2 software-properties-common 1> /dev/null 2> $errfile &
progress
check-err

echo -e "${green}====${rst} Retrieving GPG Key from docker.com ${green}====${rst}\n"
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add - 1> /dev/null 2>> $errfile &
progress
check-err

echo -e "${green}====${rst} Adding docker sources to repositories list${green}====${rst}\n"
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" 1> /dev/null 2>> $errfile &
progress
check-err
sudo apt-get update 1> /dev/null 2>> $errfile
check-err

echo -e "${green}====${rst} Installing Docker ${green}====${rst}\n"
sudo apt install -y docker-ce-cli docker-ce containerd.io 1> /dev/null 2>> $errfile &
progress
check-err

echo -e "${green}====${rst} Installing docker-compose Docker Compose ${green}====${rst}\n"
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 1> /dev/null 2>> $errfile &
progress
check-err
sudo chmod +x /usr/local/bin/docker-compose > /dev/null

echo -e "${green}====${rst} Docker has been successfully installed ${green}====${rst}\n"
docker --version
echo -e "docker-compose version : $(docker-compose -v | cut -d " " -f 3,4,5)\n"

echo -e "${green}====${rst} Creating docker dedicated user ${green}====${rst}\n"
sudo groupadd docker 1> /dev/null 2>> $errfile
sudo usermod -a -G docker $USER 1> /dev/null 2>> $errfile
check-err

read -p "Do you want to logout now to apply new rights to docker (y/n) ? " usrinput
echo -e "\n" 

case $usrinput in
	Y|y) logout;;
	*) echo -e "${yellow}[WARNING]${rst} New docker rights will be applied at next login\n";;
esac
