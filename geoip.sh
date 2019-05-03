#!/bin/sh
# 2019/04/29 by Hank
# Linux CentOS 7.6 iptables rule
# 使用方式：
# 1. 載入所有允許清單 command : sh geoip.sh
# 2. 刪除白名單國家   command : sh geoip.sh del cc TW
# 3. 刪除白名單IP     command : sh geoip.sh del ip 192.168.1.2 or geoip.sh del ip 192.168.1.0/24
# 4. 新增白名單國家   command : sh geoip.sh add cc US
# 5. 新增白名單IP     command : sh geoip.sh add ip 192.168.1.2 or sh geoip.sh add ip 192.168.1.0/24
# 6. sh geoip.sh -l   : 顯示當前 iptables geoip 設定
# 7. sh geoip.sh -d   : 刪除所有 iptables geoip 設定
# 8. sh geoip.sh -h   : 幫助
##################################################################################################

# 允許ports列表
ports="80,443,8787,8989"

# path
path="/root/geoip"

# 載入geoip 模組
if ! lsmod |grep xt_geoip >> /dev/null ; then
    modprobe xt_geoip
fi

# Docker interface 加入白名單
if ! iptables -t mangle -L PREROUTING -n | grep 172.17 >> /dev/null ; then
    iptables -t mangle -I PREROUTING -s 172.17.0.0/16 -j ACCEPT
fi

# 開啟 DROP log 紀錄
#if ! iptables -t mangle -L PREROUTING -n | grep LOG >> /dev/null ; then
#    iptables -t mangle -I PREROUTING -p tcp -m multiport --dport 80,443,8787,8989 -j LOG --log-ip-options --log-prefix "iptables DROP:"
#fi

##############
# 載入白名單 #
##############

# 讀取白名單所有列表，加入iptables設定 ex: sh geoip.sh
if [ $# -eq 0 ] ; then
    # 新增whitelist前，先刪除 DROP rule
    if iptables -t mangle -L PREROUTING -n -v | awk -F ' ' '{print $3,$8}' | grep DROP | grep "0.0.0.0/0" >> /dev/null ; then
	iptables -t mangle -D PREROUTING -p tcp -m multiport --dport $ports -j DROP
	#ptables -t mangle -D PREROUTING -j DROP
    fi

    # 讀取 white_ip 並寫入設定
    while read line ; do
        ip=$(echo $line | cut -d':' -f1)
        port=$(echo $line | cut -d':' -f2)
        if ! iptables -t mangle -L PREROUTING -n -v | grep "$ip" | grep $port >> /dev/null ; then
            iptables -t mangle -I PREROUTING -s "$ip" -p tcp -m multiport --dport $port -j ACCEPT
        fi
    done < $path/white_ip
    
    # 讀取 whitelist_country 並寫入設定
    while read line; do
        str=$line
        if ! iptables -t mangle -L PREROUTING -n -v | grep $str >> /dev/null ; then
            iptables -t mangle -A PREROUTING -m geoip -p tcp -m multiport --dports $ports --src-cc $str -j ACCEPT
        fi
    done < $path/white_country
    
    # 將 DROP rule 加回
    iptables -t mangle -A PREROUTING -p tcp -m multiport --dport $ports -j DROP
    #iptables -t mangle -A PREROUTING -j DROP

##############
# 新增白名單 #
##############

# 新增國家白名單 ex:sh geoip.sh add cc US
elif [ $# -eq 3 ] && [ $1 = "add" ] && [ $2 = "cc" ] ; then
    if ! iptables -t mangle -L PREROUTING -n -v | grep ${3^^} >> /dev/null ; then
        iptables -t mangle -I PREROUTING -m geoip -p tcp -m multiport --dports $ports --src-cc ${3^^} -j ACCEPT
    	if [ $? -eq 0 ] ; then
                echo ${3^^} >> $path/white_country
                echo "Success!"
    	else
	        echo "Wrong ISO 3166-1 country code." 
    	fi
    else
        echo Failed,${3^^} was existed!
    fi
# 新增單一允許IP ex: sh geoip.sh add ip 192.168.1.2 or sh geoip.sh add ip 192.168.1.0/24
elif [ $# -eq 3 ] && [ $1 = "add" ] && [ $2 = "ip" ] ; then
    if ! iptables -t mangle -L PREROUTING -n -v | awk -F ' ' '{print $8,$11}' | grep "${3^^}" >> /dev/null ; then
        iptables -t mangle -I PREROUTING -s "${3^^}" -p tcp -m multiport --dport $ports -j ACCEPT
	    echo ${3^^}:$ports >> $path/white_ip
        echo "Success!"
    else
        echo Failed,${3^^} was existed!
    fi

##############
# 刪除白名單 #
##############

# 刪除單一允許國家，並將此紀錄在whitelist中永久刪除 ex: sh geoip.sh del cc TW
elif [ $# -eq 3 ] && [ $1 = "del" ] && [ $2 = "cc" ] ; then
    sed -i /${3^^}/d $path/white_country
    if iptables -t mangle -L PREROUTING -n -v | grep ${3^^} >> /dev/null ; then
        iptables -t mangle -D PREROUTING -m geoip -p tcp -m multiport --dports $ports --src-cc ${3^^} -j ACCEPT
        echo "Success!"
    else
        echo Failed,${3^^} was existed!
    fi

# 刪除單一允許IP，並將此紀錄在whitelist中永久刪除 ex: sh geoip.sh del ip 192.168.1.2 or geoip.sh del ip 192.168.1.0/24
elif [ $# -eq 3 ] && [ $1 = "del" ] && [ $2 = "ip" ] ; then
    if iptables -t mangle -L PREROUTING -n -v | awk -F ' ' '{print $8,$11}' | grep "$3" >> /dev/null ; then
        iptables -t mangle -D PREROUTING -s "$3" -p tcp -m multiport --dport $ports -j ACCEPT
        echo "Success!"
	# 判斷IP是否帶有netmask
        if echo "$3" | grep "/" >> /dev/null ; then
	    del_ip=$(echo $3 | sed 's#/#\\\/#g')
            sed -i /"$del_ip":$ports/d $path/white_ip
	    else
	        sed -i /"$3":$ports/d $path/white_ip
	    fi
    else
        echo Failed,$3 was existed!
    fi

# 刪除geoip所有設定
elif [ $# -eq 1 ] && [ $1 = "-d" ] ; then
    iptables  -t mangle -F PREROUTING
#############################

# 顯示當前設定
elif [ $# -eq 1 ] && [ $1 = "-l" ] ; then
    iptables -t mangle -L PREROUTING -n -v

# 顯示幫助
elif [ $# -eq 1 ] && [ $1 = "-h" ] ; then
    cat $path/README

# iptables LOG 開關
elif [ $# -eq 2 ] && [ $1 = "on" ] && [ $2 = "log" ] ; then
    if ! iptables -t mangle -L PREROUTING -n | grep LOG >> /dev/null ; then
        iptables -t mangle -I PREROUTING -p tcp -m multiport --dport $ports -j LOG --log-ip-options --log-prefix "iptables DROP:"
	echo "Success!"
    else
	echo "Failed,Log was on!"
    fi
elif [ $# -eq 2 ] && [ $1 = "off" ] && [ $2 = "log" ] ; then
    if iptables -t mangle -L PREROUTING -n | grep LOG >> /dev/null ; then
        iptables -t mangle -D PREROUTING -p tcp -m multiport --dport $ports -j LOG --log-ip-options --log-prefix "iptables DROP:"
	echo "Success!"
    else
	echo "Failed,Log was off!"
    fi
############################

else 
    echo -e "\n ###輸入錯誤### \n"
    cat $path/README

fi
