#!/usr/bin/env bash

# 找到文件夹下的 pom文件有没有 包含
war_sh_arr=("oplus-svs" "oplus-ata" "oplus-dts")

projects=("oplus-svs" "oplus-commons" "oplus-jao-pub" "oplus-jao" "oplus-udp" "oplus-gfs-client" "oplus-gfs" "oplus-vap" "oplus-upm" "oplus-adm" "oplus-dts" "oplus-dts-jdbc")
# 拿到此目录下  /tmp/oplus/oplus-ata-v2.0/checkout 的pom.xml 文件
# 查看此文件是否包含 字符串 oplus-svs...
# 则 加入到重启计划中K
function find_pom_str(){
    for each  in ${projects[*]} ; do
        # 首先判断pom文件存在否
        pro=/tmp/oplus/${each}/checkout/pom.xml
        for w in ${war_sh_arr[@]} ; do
            if [[ -f "${pro}" ]]; then
                if [[ -n `grep -w "<artifactId>${w}</artifactId>" ${pro}` ]]; then
                    echo "Module ${w} contains ${each}, restart ${each} normally."
                fi
            fi
        done
    done
}

find_pom_str