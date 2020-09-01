#!/bin/bash
#-------------------------------------------------------------
# init global vars
#-------------------------------------------------------------
rely_dir=`dirname $0`
cd ${rely_dir}
workdir=`pwd`

function logger() {
	now=`date +"%Y-%m-%d %T"`
	echo $now [$1] $2
}

logger INFO "Get install config vars."
function set_all_vars () {
	cmd=`cat ${workdir}/install.conf | grep "^[^#].*"`
	echo $cmd
	eval $cmd
}
set_all_vars
logger INFO "Oplus_ip is ${oplus_ip}"

mysql_exe=""
service mysqld status 1>/dev/null 2>&1
if [ $? != 0 ]
then
	mysql_exe="/opt/nginxstack-1.16.0-2/mysql/bin/mysql"
else
#	mysql_pwd=`cat /var/log/mysqld.log | grep "A temporary password is generated for" | awk -F ": " '{print $2}'`
	mysql_exe="mysql"
fi

#-------------------------------------------------------------
# init oplus database for mysql
#-------------------------------------------------------------
function init_oplus_database() {
	logger INFO "Init oplus database."
	${mysql_exe} -h ${mysql_ip} -u root -P 3306 -p${mysql_pwd} mysql -e "drop database oplus;" 2>/dev/null
    sql_list=`ls /opt/oplus/db/mysql | grep "\.sql"`
    for sql in ${sql_list};do
        {mysql_exe} -h ${mysql_ip} -u root -P 3306 -p${mysql_pwd} mysql -e "source /opt/oplus/db/mysql/${sql};"
    done
}

#-------------------------------------------------------------
# modify protal config
#-------------------------------------------------------------
function modify_portal_config() {
	logger INFO "Modify portal html config."
	sed -i s#"http://[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*"#"http://${oplus_ip}"#g /opt/oplus/html/config.js
}

#-------------------------------------------------------------
# modify oplus application
#-------------------------------------------------------------
function modify_oplus_application() {
	app_list=(svs dts portal)
	for app in ${app_list[@]};do
		modify_app_application $app
	done
}

function modify_app_application() {
	logger INFO "Modify $1 application."
	mkdir -p /opt/oplus/war/temp/$1
	/bin/cp -f /opt/oplus/war/oplus-$1*.war /opt/oplus/war/temp/$1
	cd /opt/oplus/war/temp/$1
	app_name=`ls | grep $1 | grep war`
	unzip -o ${app_name} > /dev/null
	bool=`cat WEB-INF/classes/config/application-prod.yml | grep jdbc:mysql`
	if [ -z "$bool" ];then
		bool=`cat WEB-INF/classes/config/application.yml | grep jdbc:mysql`
		if [ -z "$bool" ];then
			logger ERROR "Can not found config of jdbc in application.yml or application-prod.yml!"
			logger ERROR "Failed to modify $1 application!"
			unset bool
			return
		else
			application_path=WEB-INF/classes/config/application.yml
		fi
	else
		application_path=WEB-INF/classes/config/application-prod.yml
	fi
	unset bool
	logger INFO "application path : ${application_path}"
	sed -i -e s#jdbc:mysql://[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:3306#"jdbc:mysql://${mysql_ip}:3306"#g -e s#jdbc:mysql://localhost:3306#"jdbc:mysql://${mysql_ip}:3306"#g ${application_path}
	jar -cvfM0 ../../${app_name} org WEB-INF META-INF > /dev/null
}

#-------------------------------------------------------------
# modify oplus-ata application
#-------------------------------------------------------------
function set_sftp_server () {
	echo "${tag}${tag}${tag}{host: $1,port: 22,username: $2,password: $3},\n"
}
function modify_ata_application() {
	logger INFO "Modify oplus-ata application."
	mkdir -p /opt/oplus/war/temp/ata
	/bin/cp -f /opt/oplus/war/oplus-ata-2.0.war /opt/oplus/war/temp/ata
	cd /opt/oplus/war/temp/ata
	jar -xvf oplus-ata-2.0.war > /dev/null
	application_path=`jar -tvf oplus-ata-2.0.war | grep application-prod.yml | awk '{print $8}'`
	logger INFO "Modify tower web login username and password"
	sed -i "/^ata:$/,/^[#a-zA-Z]/s/username: admin/username: ${tower_web_user}/" ${application_path}
	sed -i "/^ata:$/,/^[#a-zA-Z]/s/password: admin/password: ${tower_web_pwd}/" ${application_path}
	logger INFO "Modify tower sftp config."
	tower_hosts=(`cat ${workdir}/install.conf | grep tower_sftp_host | awk -F = '{$1="";print $0}'`)
	tower_pwds=(`cat ${workdir}/install.conf | grep tower_sftp_pwd | awk -F = '{$1="";print $0}'`)
	tower_users=(`cat ${workdir}/install.conf | grep tower_sftp_username | awk -F = '{$1="";print $0}'`)
	tag=`cat $application_path|grep client:|awk -F cl '{print $1}'`
	sftp_str="clusterServer: [\n"
	for i in $(seq ${#tower_hosts[@]})
	do
		index=`expr $i - 1`
		sftp_str=${sftp_str}`set_sftp_server ${tower_hosts[$index]} ${tower_users[$index]} ${tower_pwds[$index]}`
	done
	sftp_str="${sftp_str}${tag}${tag}]"
	sed -i "/clusterServer: \[$/,/\]$/c\${tag}${tag}$sftp_str" ${application_path}
	sed -i s/'${tag}'/"${tag}"/g ${application_path}
	sed -i -e s#jdbc:mysql://[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:3306#"jdbc:mysql://${mysql_ip}:3306"#g -e s#jdbc:mysql://localhost:3306#"jdbc:mysql://${mysql_ip}:3306"#g ${application_path}
	sed -i "/^redis:$/,/timeout: 10000$/c\redis:\n${tag}hostName: 127.0.0.1\n${tag}port: 6379\n${tag}password: ${redis_pwd}\n${tag}timeout: 10000" ${application_path}
	sed -i s/'${tag}'/"${tag}"/g ${application_path}
	jar -uvf oplus-ata-2.0.war ${application_path}
	/bin/cp -f oplus-ata-2.0.war /opt/oplus/war/oplus-ata-2.0.war
}

#-------------------------------------------------------------
# update oplus-params config
#-------------------------------------------------------------
function check_str_replace () {
	result=`echo "'"$1"'" | grep '/'`
	a=`echo $1`
	#echo $a
	if [ ${#result} -eq 0 ];then
		sed -i s/'${'$2'}'/"${a}"/g ${oplus_params_sql}
		return
	fi
	result=`echo "'"$1"'" | grep '#'`
	if [ ${#result} -eq 0 ];then
		sed -i s#'${'$2'}'#"${a}"#g ${oplus_params_sql}
		return
	fi
	result=`echo "'"$1"'" | grep '\^'`
	if [ ${#result} -eq 0 ];then
		sed -i s^'${'$2'}'^"${a}"^g ${oplus_params_sql}
		return
	fi
	logger ERROR "Can't not replace the ${loop} becase the value is include '/' and '#' and '^'"
}
function update_oplus_param_config() {
	logger INFO "Update oplus param config."
	/bin/cp -f ./oplus_params.sql /opt/oplus/db/
	oplus_params_sql="/opt/oplus/db/oplus_params.sql"
	vars=`cat ${workdir}/install.conf | grep "^[^#].*" | awk -F = '{print $1}'`
	for loop in ${vars}
	do
		logger INFO "${!loop}"
		check_str_replace "${!loop}" "${loop}"
	done
	${mysql_exe} -h ${mysql_ip} -u root -P 3306 -p${mysql_pwd} oplus -e "source ${oplus_params_sql};"
}

#-------------------------------------------------------------
# update oplus database source
#-------------------------------------------------------------
function update_oplus_database_source() {
	logger INFO "Update oplus database source."
	${mysql_exe} -h ${mysql_ip} -u root -P 3306 -p${mysql_pwd} oplus -e "update dts_datasource set config=replace(config,\"129.204.67.86\",\"${database_source_ip}\") where name=\"oplus\" and tenant_id=\"${tenant_id}\";"
}

#-------------------------------------------------------------
# start main function
#-------------------------------------------------------------
function main() {
	start_app=false
	if [ -z "$*" ];then
		init_oplus_database
		update_oplus_param_config
		update_oplus_database_source
		modify_portal_config
		modify_oplus_application
		modify_ata_application
		start_app=true
	else
		for loop in $@;do
			if [ mysql == $loop ];then
				init_oplus_database
				update_oplus_param_config
				update_oplus_database_source
			elif [ oplus == $loop ];then
				modify_oplus_application
				modify_portal_config
				start_app=true
			elif [ ata == $loop ];then
				modify_ata_application
				start_app=true
			else
				logger ERROR "Unkonwn param : $loop !"
			fi
		done
	fi
	if [ ${start_app} == true ];then
		logger INFO "Please wait for 60 seconds to start app!"
		sleep 60
		monit restart all
		logger INFO "Completed!"
	fi
}

main $*