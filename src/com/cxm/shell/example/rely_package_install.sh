#! /bin/bash

rely_dir=`dirname $0`
cd ${rely_dir}
workdir=`pwd`

#unzip -o ./*.zip -d /opt/

function check_install () {
	$1 -h > /dev/null
	if [ $? != 0 ];then
		echo It is not install $1!
		echo Going to install $1 now!
		command="yum install -y $1"
		yum install -y $1
		check_command "${command}"
	else
		echo It is aleardy install $1!
	fi
}

function check_command() {
	if [ $? != 0 ];then
		echo failed to excute the command : $1
		exit 1
	fi
}

function install_base_package() {
	check_install vim
	check_install zip
	check_install unzip
	check_install curl
}

function get_answer() {
	output=$1
	action=$2
	param=$3
	echo $output
	read -p "Please Enter [y]es or [n]o : " bool
	echo
	if [ x$bool == xy -o x$bool == x ];then
		${action} ${param}
	elif [ x$bool == xn ];then
		return
	else
		echo Unknown Input!
		echo Please try again Enter your answer!
		get_answer ${output} ${action} ${param}
	fi
}

function change_mysql_pwd() {
	echo "Please set a new password for mysql."
	check_password
	${mysql_exe} -h localhost -u root -P 3306 -pOplus@2020 mysql -e "ALTER user 'root'@'localhost' IDENTIFIED with mysql_native_password BY '"${pwd}"';flush privileges;"
	if [ $? != 0 ];then
		echo Password input is illegal!
		echo Please try again Enter password!
		change_mysql_pwd
	else
		echo Change mysql password successful!
	fi
}

function uninstall_packages() {
	if [ $1 == java ];then
		rpm=jdk
	else
		rpm=$1
	fi
	if [ -z "${pkgs}" ];then
		echo Going to uninstall $1!
		pkgs=`rpm -qa|grep ${rpm}`
		rpm -qa|grep ${rpm} |grep -n ${rpm}
	fi
	echo Enter which rpm packages can need to remove!
	read -p "Please enter (a)ll or (n)one or (1,4,5)list : " answer
	echo
	if [ x$answer == xa -o x$answer == x ];then
		for pkg in ${pkgs};do
			echo uninstall ${pkg}
#			rpm -e --nodeps ${pkg}
		done
		pkgs=""
		return
	elif [[ $answer =~ ^[0-9](,[0-9]){0,}$ ]];then
		list=$(echo -e ${answer//,/\\n} | sort)
		pkgs=($pkgs)
		for loop in ${list[@]};do
			index=`expr $loop - 1`
			echo ${pkgs[$index]}
			if [ -z ${pkgs[$index]} ];then
				echo The Package list is not include index of ${loop};
			else
				echo uninstall ${pkgs[$index]}
#				rpm -e --nodeps ${pkgs[$index]}
			fi
		done
	elif [ x$answer == xn ];then
		pkgs=""
		return
	else
		echo Unknown Input!
		echo Please try again Enter your answer!
		uninstall_packages $1
	fi
	pkgs=`rpm -qa|grep ${rpm}`
	rpm -qa|grep ${rpm} |grep -n ${rpm}
	get_answer "Do you need to uninstall other packages?" uninstall_packages $1
	pkgs=""
}

function install_java() {
	java -version > /dev/null 2>&1
	if [ $? != 0 ];then
		echo java is aleardy install!
		pkgs=`rpm -qa|grep jdk`
		for pkg in ${pkgs};do
			echo uninstall ${pkg}
			rpm -e --nodeps ${pkg}
		done
	fi
	echo start install java!
	cd /opt/software/jdk
	tar -xvf jdk-8u181-linux-x64.tar.gz
	mv jdk1.8.0_181/ /usr/local/
	echo "" >> /etc/profile
	echo 'JAVA_HOME=/usr/local/jdk1.8.0_181' >> /etc/profile
	echo 'JRE_HOME=/usr/local/jdk1.8.0_181/jre' >> /etc/profile
	echo 'CLASS_PATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar:$JRE_HOME/lib' >> /etc/profile
	echo 'PATH=$PATH:$JAVA_HOME/bin:$JRE_HOME/bin' >> /etc/profile
	echo 'export JAVA_HOME JRE_HOME CLASS_PATH PATH' >> /etc/profile
	source /etc/profile
	ln -s /usr/local/jdk1.8.0_181/bin/java /usr/sbin/java
}

function install_ansible() {
	echo start install ansible by yum!
	yum install -y epel-release
	yum install -y ansible
	if [ $? != 0 ];then
		echo Error! Failed to install ansible!
		return
	fi
}

function uninstall_mysql() {
	pkgs=`rpm -qa | grep mysql`
	for pkg in ${pkgs}
	do
		echo uninstall ${pkg}
		rpm -e --nodeps ${pkg}
	done
	pkgs=`rpm -qa | grep mariadb`
	for pkg in ${pkgs}
	do
		echo uninstall ${pkg}
		rpm -e --nodeps ${pkg}
	done
}

function install_nginx() {
	uninstall_mysql
	echo start to install Bitnami Nginx Stack
	cd /opt/software/nginx
	./bitnami-nginxstack-1.16.0-2-linux-x64-installer.run <<EOF

Y
y

passw0rd
passw0rd
y
y

EOF
	mysql_exe="/opt/nginxstack-1.16.0-2/mysql/bin/mysql"
	${mysql_exe} -h localhost -u root -P 3306 -ppassw0rd mysql -e "ALTER user 'root'@'localhost' IDENTIFIED with mysql_native_password BY 'Oplus@2020';flush privileges;"
	unset pwd
	get_answer "Do you want to change the mysql dafualt password : Oplus@2020 ?" change_mysql_pwd
	mysql_old=`cat ${workdir}/install.conf | grep 'mysql_pwd='`
	if [ -z ${pwd} ];then
		sed -i s/"${mysql_old}"/"mysql_pwd='Oplus@2020'"/g ${workdir}/install.conf
	else
		sed -i s/"${mysql_old}"/"mysql_pwd='${pwd}'"/g ${workdir}/install.conf
	fi
	set_auto_start '/opt/nginxstack-1.16.0-2/mysql/scripts/ctl.sh start'
	set_auto_start '/opt/nginxstack-1.16.0-2/nginx/sbin/nginx'
	echo modify nginx config
	cp /opt/oplus/conf/nginx.conf /opt/nginxstack-1.16.0-2/nginx/conf/
	/opt/nginxstack-1.16.0-2/ctlscript.sh restart nginx
}

function check_password() {
	unset pwd
	read -p "Enter password : " -s pwd_1
	echo
	read -p "Re-Enter password : "  -s pwd_2
	echo
	if [ -z ${pwd_1} ];then
		echo "Warning: Password Do Not Null!"
		check_password
	fi
	if [ "${pwd_1}" != "${pwd_2}" ];then
		echo "Warning: Passwords Do Not Match!"
		check_password
	fi
	pwd=${pwd_1}
}

function install_redis() {
	echo start install redis
	cd /opt/software/redis
	tar -zxvf redis-4.0.14.tar.gz
	cd redis-4.0.14
	yum -y install gcc auutomake autoconf libtool make
	make
	make MALLOC=libc
	make install PREFIX=/opt/software/redis/redis-4.0.14
	set_auto_start '/opt/software/redis/redis-4.0.14/bin/redis-server /opt/software/redis/redis-4.0.14/redis.conf'
	echo modify redis config
	sed -i s/"daemonize no"/"daemonize yes"/g /opt/software/redis/redis-4.0.14/redis.conf
	redis_defualt_pwd=`cat /opt/software/redis/redis-4.0.14/redis.conf | grep "requirepass "`
	echo "Please Enter redis password what you want to set!"
	check_password
	redis_pwd=${pwd}
	sed -i s/"${redis_defualt_pwd}"/"requirepass ${redis_pwd}"/g /opt/software/redis/redis-4.0.14/redis.conf
	redis_old=`cat ${workdir}/install.conf | grep 'redis_pwd='`
	sed -i s/"${redis_old}"/"redis_pwd='${redis_pwd}'"/g ${workdir}/install.conf
	echo start redis-server
	/opt/software/redis/redis-4.0.14/bin/redis-server /opt/software/redis/redis-4.0.14/redis.conf
}

function install_nodejs() {
	echo start install nodeJs
	cd /opt/software/nodejs
	sudo tar -xzvf node-v8.16.0-linux-x64.tar.gz -C /opt/
	cd /opt
	mv node-v8.16.0-linux-x64 nodejs
	sudo ln -s /opt/nodejs/bin/node /usr/local/bin/node
	sudo ln -s /opt/nodejs/bin/npm /usr/local/bin/npm
	sudo ln -s /opt/nodejs/bin/node /usr/bin/node
	sudo ln -s /opt/nodejs/bin/npm /usr/bin/npm
	node -v
	if [ $? != 0 ];then
		echo node is not install,there are something error!
	else
		echo node install successful!
	fi
	npm -v
	if [ $? != 0 ];then
		echo npm is not install,there are something error!
	else
		echo npm install successful!
	fi

	echo start install PM2
	cd /opt/software/nodejs
	npm install pm2-3.5.0.tgz -g
	sudo ln -s /opt/nodejs/bin/pm2 /usr/local/bin/pm2
	sudo ln -s /opt/nodejs/bin/pm2 /usr/bin/pm2
	pm2 -v
	if [ $? != 0 ];then
		echo pm2 is not install,there are something error!
	else
		echo pm2 install successful!
	fi
	echo start install oplus-njs
	cd /opt/oplus/njs
	unzip oplus-njs-1.0.0.zip -d /opt/oplus/njs
	tar xzvf oplus-njs-1.0.0_node_modules.tar.gz
	pm2 start /opt/oplus/njs/src/index.js --name "oplus-njs"
}

function install_monit() {
	echo start install monit
	cd /opt/software/monit
	tar xzvf monit-5.25.3-linux-x64.tar.gz -C /opt
	mv /opt/monit-5.25.3 /opt/monit
	cp /opt/oplus/conf/monitrc /etc
	chmod 700 /etc/monitrc
	sudo ln -s /opt/monit/bin/monit /usr/local/bin/monit
	sudo ln -s /opt/monit/bin/monit /usr/bin/monit
	/usr/local/bin/monit -c /etc/monitrc
	set_auto_start '/usr/local/bin/monit -c /etc/monitrc'
}

if [ -e /etc/rc.local ];then
	chmod +x /etc/rc.local
	auto_start_path=/etc/rc.local
fi
if [ -e /etc/rc.d/rc.local ];then
	chmod +x /etc/rc.d/rc.local
	auto_start_path=/etc/rc.d/rc.local
fi
if [ -z ${auto_start_path} ];then
	echo the file /etc/rc.local and /etc/rc.d/rc.local is not exist!
	echo set auto start failed!
else
	echo auto start path is ${auto_start_path}
fi

function set_auto_start () {
	echo "" >> ${auto_start_path}
	echo $1 >> ${auto_start_path}
}	

function main () {
	package_list=(nginx java nodejs monit redis ansible)
	package_list=(nginx java nodejs monit redis ansible)
	if [ -z "$*" ];then
		install_base_package
		for package in ${package_list[@]};do
			get_answer "Do you want to install ${package} ?" install_${package}
		done
	else
		for package in $@;do
			if [[ "${package_list[@]}" =~ "${package}" ]];then
				install_$package
			else
				echo Unknown package named ${package},It can not be installed!
			fi
		done
	fi
}
main $*