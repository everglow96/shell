#!/usr/bin/env bash
# @see https://www.cnblogs.com/hanzhi/articles/11482263.html

function main(){
    package_path=/opt/software/nginx/nginx_all/nginx_package
    # 解压
    unzip -o /opt/software/nginx/nginx_all.zip -d /opt/oplus/software/ 2>&1 >/dev/null
    rpm -qa | gcc-c++
    [[ $? -eq 0 ]] || yum install -y gcc-c++
    # 如果执行失败 需要手动去执行离线安装包
    [[ $? -eq 0 ]] || offline_install_gcc
    offline_install_soft
}

function offline_install_gcc(){
    echo "start install gcc-c++"
    # 安装gcc依赖
    rpm -ivh /opt/oplus/software/nginx_all/gcc_rpm/*.rpm --force --nodeps
}

function offline_install_soft() {
    echo "start install all soft"
    tar -zxvf ${package_path}/pcre-8.42.tar.gz -C ${package_path} 2>&1 >/dev/null
     cd ${package_path}/pcre-8.42/
    ./configure 2>&1 >/dev/null
    make 2>&1 >/dev/null
    make install 2>&1 >/dev/null

    tar -zxvf ${package_path}/zlib-1.2.11.tar.gz -C ${package_path} 2>&1 >/dev/null
    cd ${package_path}/zlib-1.2.11/
    ./configure 2>&1 >/dev/null
    make 2>&1 >/dev/null
    make install 2>&1 >/dev/null

    tar -zxvf ${package_path}/openssl-1.1.0h.tar.gz -C ${package_path}  2>&1 >/dev/null
    cd ${package_path}/openssl-1.1.0h/
    ./config 2>&1 >/dev/null
    make 2>&1 >/dev/null
    make install 2>&1 >/dev/null

    tar -zxvf ${package_path}/nginx-1.14.0.tar.gz -C ${package_path} 2>&1 >/dev/null
    mkdir -p /usr/local/nginx
    cd ${package_path}/nginx-1.14.0/
    ./configure --prefix=/usr/local/nginx --with-http_ssl_module --with-pcre=../pcre-8.42 --with-zlib=../zlib-1.2.11 --with-openssl=../openssl-1.1.0h 2>&1 >/dev/null
    make  2>&1 >/dev/null
    make install  2>&1 >/dev/null
#    /usr/local/nginx/sbin/nginx
}

main