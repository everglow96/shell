#! /bin/bash

################################################################################
# @desc Build oplus commons JAR
# @author leoliaolei@gmail.com, 2018/05/15, created
# @author leoliaolei, 2020/02/02, support multiple pom in a repo
################################################################################

checkout_dir=""
pom_dir=""
git_url=""

function init_env() {
  checkout_dir=/tmp/oplus/${project}/checkout
  pom_dir=${checkout_dir}
  git_url=git@gitee.com:leoliaolei/${project}.git
  if [ "${project}" == "oplus-gfs-client" ]; then
    pom_dir=${pom_dir}/oplus-gfs-client
    #git_url=git@gitee.com:leoliaolei/oplus-gfs.git
    git_url=git@e.coding.net:leoliaolei/oplus-gfs.git
  elif [ "${project}" == "oplus-jao-pub" ]; then
    pom_dir=${pom_dir}/oplus-jao-pub
    git_url=git@e.coding.net:leoliaolei/oplus-jao.git
  elif [ "${project}" == "oplus-commons" ]; then
    git_url=git@e.coding.net:leoliaolei/oplus-commons/oplus-commons.git
    pom_dir=${pom_dir}/java
  elif [ "${project}" == "oplus-adm" ]; then
    git_url=git@e.coding.net:leoliaolei/${project}/${project}.git
  elif [ "${project}" == "oplus-cac" ]; then
    git_url=git@gitee.com:chouminglan/${project}.git
  elif [ "${project}" == "oplus-portal" ] || [ "${project}" == "oplus-uaa" ] ; then
    git_url=git@gitee.com:qdjoker/${project}.git
  elif [ "${project}" == "oplus-pms" ]; then
    git_url=git@gitee.com:BreckinLee/${project}.git
  elif [ "${project}" == "oplus-ata-v2.0" ]; then
    git_url=git@gitee.com:zhaochenggang/${project}.git
  elif [ "${project}" == "oplus-vap" ] || [ "${project}" == "oplus-udp" ] || [ "${project}" == "oplus-gfs" ] || [ "${project}" == "oplus-jao" ]; then
    git_url=git@e.coding.net:leoliaolei/${project}.git
  elif [ "${project}" == "oplus-upm" ]; then
    git_url=git@gitee.com:BreckinLee/${project}.git
  elif [ "${project}" == "oplus-cm-client" ]; then
    git_url=git@gitee.com:BreckinLee/${project}.git
  fi
}

function read_input () {
    POSITIONAL=()
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -p|--project)
                project="$2"
                shift # past argument
                shift # past value
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

function usage() {
   echo "Usage: sudo ./build-jar.sh -p project_name [options]"
   echo "Supported options"
   echo "-c|--checkout false  Do not checkout source"
}

function info() {
   echo "********** $1"
}

function maven_build() {
  info "Build with maven"
  cd ${pom_dir}
  sh mvnw -Dmaven.test.skip=true clean package deploy
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
}

function git_checkout() {
  info "Checkout source from ${git_url}"
  rm -rf ${checkout_dir}
  mkdir -p ${checkout_dir}
  git clone ${git_url}  ${checkout_dir}
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
}

function main() {
  read_input $*

  if [ -z "${project}" ];  then usage; exit 1; fi

  info "Building project ${project}"
  init_env
  git_checkout
  maven_build
}

main $*
