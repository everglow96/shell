#! /bin/bash

# Build oplus modules WAR
# Author: leoliaolei@gmail.com
# Date: 20180412

read_input () {
    POSITIONAL=()
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -p|--project)
                project="$2"
                shift # past argument
                shift # past value
                ;;
            -r|--reload)
                arg_reload="true"
                shift # past argument
                ;;
            -c|--checkout)
                arg_checkout="$2"
                shift # past argument
                shift # past value
                ;;
            --help)
                usage
                exit 0
                ;;
            *)    # unknown option
                POSITIONAL+=("$1") # save it in an array for later
                shift # past argument
                ;;
        esac
    done
    set -- "${POSITIONAL[@]}" # restore positional parameters
}

init_env() {
  checkout_dir=/tmp/oplus/${project}/checkout
  tomcat_dir=/opt/tomcat
  war_dir=/opt/oplus/war
}


usage() {
   echo "Usage: sudo ./build.sh -p project_name [options]"
   echo "Supported options"
   echo "-r|--reload          Reload tomcat webapp"
   echo "-c|--checkout false  Do not checkout source"
}

info() {
   echo "********** $1"
}

reload_webapp() {
  info "Reload webapp ${project}"
  #tomcat_manager_url=http://admin:guanliyuan666@localhost:8080/manager/text/reload
  #curl ${tomcat_manager_url}?path=/${project}
  /opt/oplus/stop.sh ${project}
  /opt/oplus/start.sh ${project}
}

maven_build() {
  info "Build with maven"
  cd ${checkout_dir}
  sh mvnw -Dmaven.test.skip=true -Pprod clean package
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
}

get_git_url() {
  _project=$1
  if [ "${_project}" == "oplus-bot" ] || [ "${_project}" == "oplus-bot-gateway" ] || [ "${_project}" == "oplus-cac" ] || [ "${_project}" == "oplus-git" ] ;then
    echo git@git.coding.net:Anassassin/${_project}.git
  elif [ "${_project}" == "oplus-dts" ];then
    echo git@gitee.com:jyhong/${_project}.git
  elif [ "${_project}" == "oplus-ata-v2.0" ];then
    echo git@gitee.com:zhaochenggang/${_project}.git
  elif [ "${_project}" == "oplus-portal" ] || [ "${_project}" == "oplus-tm" ];then
    echo git@gitee.com:qdjoker/${_project}.git
  else
    echo git@e.coding.net:leoliaolei/${_project}/${_project}.git
    #echo git@gitee.com:leoliaolei/${_project}.git
  fi
}

git_checkout() {
  local git_url=$(get_git_url ${project})
  info "Checkout source from ${git_url}"
  rm -rf ${checkout_dir}
  mkdir -p ${checkout_dir}
  git clone ${git_url}  ${checkout_dir}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
}

copy_tomcat() {
  info "Copy files to tomcat webapps"
  local war_file=$(ls ${checkout_dir}/target/*.original)
  local rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
  unzip -o ${war_file} -d ${tomcat_dir}/webapps/${project}
}

function copy_war() {
  local war_file=$(ls ${checkout_dir}/target/*.war)
  local rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
  info "Copy files from ${war_file} to ${war_dir}"
  rm -f ${war_dir}/${project}-*.war
  cp ${war_file} ${war_dir}
}

main() {
  read_input $*

  if [ -z "${project}" ];  then usage; exit 1; fi

  info "Building project ${project}"
  init_env
  git_checkout
  maven_build
  #copy_tomcat
  copy_war 

  if [ "$arg_reload" == "true" ]; then reload_webapp; fi
}

main $*
