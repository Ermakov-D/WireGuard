#/bin/sh
#########################################
# Helper programm
# prips - https://gitlab.com/prips/prips
# shflags - yum install shflags
##########################################
. /usr/share/shflags/shflags

WG_etc="/etc/wireguard"
WG_conf="${WG_etc}/wg0.conf"

DEFINE_string 'name' 'NULL_user' 'Имя пользователя' 'n'
DEFINE_boolean 'key' false 'Только генерация ключа' 'k'
DEFINE_boolean 'write' false 'Автоматический режим (добавление в wg0.conf и создание конфига в clients/' 'w'
DEFINE_boolean 'debug' false 'Режим отладки (пока не предлагает записать' 'd'

genKeys () {
    tmpfile_priv=$(mktemp /tmp/wg-genKeys.XXXXX)
    tmpfile_pub=$(mktemp /tmp/wg-genKeys.XXXXX)
    tmpfile_shared=$(mktemp /tmp/wg-genKeys.XXXXX)

    wg genkey | tee ${tmpfile_priv} | wg pubkey > ${tmpfile_pub}
    wg genpsk > $tmpfile_shared
}

showKeys () {
    echo -n "PrivateKey:    "; cat $tmpfile_priv
    echo -n "PublicKey:     "; cat $tmpfile_pub
    echo -n "PreSharedKey:  "; cat $tmpfile_shared
}
addToWG () {
echo -e "#--------- [${FLAGS_name}] --------
[Peer]
AllowedIPs = ${IPAddress}/32
PublicKey =  `cat $tmpfile_pub`
PresharedKey =  `cat $tmpfile_shared`
#--------- [End ${FLAGS_name}]  ---------"
}
clientFile () {
echo -e "#PrivateKey:\t `cat $tmpfile_priv`
#PublicKey:\t `cat $tmpfile_pub`
#PreSharedKey:\t `cat $tmpfile_shared`
[Interface]
Address = ${IPAddress}/22
MTU = 1280
DNS = 10.254.1.1
PrivateKey      =  `cat $tmpfile_priv`
[Peer]
AllowedIPs = 10.254.1.1/32,192.168.240.0/20
Endpoint = vpn.viam.ru:51820
PersistentKeepalive = 25
PresharedKey =  `cat $tmpfile_shared`
PublicKey        =  ${SRV_wg_Keys}"
}
# Получаем параметры и разбираем их
FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"
FLAGS_HELP="
Как пользоватья: $0 -n ИмяПользователя -k -w
 -n|--name:     Имя пользователя для которого создаются ключи
 -k|--key:      Только сгенерировать ключи
 -w|--write:    Вывод ключаей и запись настроек в wg0.conf и создание конфигурационног файла пользователя 
"

#echo "-n = ${FLAGS_name}"
#echo "-k = ${FLAGS_key}"
#echo "-w = ${FLAGS_write}"
#echo "-net = ${FLAGS_net}"

if [ ${FLAGS_key} -eq ${FLAGS_TRUE} ]; then
    genKeys
    showKeys
    rm -f $tmpfile_pub $tmpfile_priv $tmpfile_shared
    exit 0
fi

if [ "${FLAGS_name}" = "NULL_user" ]; then
    echo "Нет имени пользователя"
    exit 1
fi

# Получаем ip
IPs=$(cat ${WG_conf} | grep AllowedIP |grep -v "#" | awk '{print $3}'| awk -F "/" '{print $1}' | sort -h )
maxIP=$(cat ${WG_conf} | grep AllowedIP |grep -v "#" | awk '{print $3}' | awk -F "." '{print $4}'| awk -F "/" '{print $1}' | sort -h | tail -1)

for ip in $(/usr/local/bin/prips ${IP_begin} ${IP_end}); do
    if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo -n "${ip} - "; fi
    case $(echo ${ip} | awk -F "." '{print $4}') in
	0)
	    if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo " network address"; fi
	    continue;;
	255)
	    if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo " broadcast address"; fi
	    continue;;
	[1-9] | 1[0-9] | 2[0-9] | 30)
	    if [ "$(echo ${ip} | awk -F '.' '{print $1"."$2"."$3"."}')" = "10.254.1." ]; then
		if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo " reserved address"; fi
		continue
	    fi
	    ;;
    esac
    if [[ $(echo ${IPs} | grep -o "$ip" | wc -w) -eq 1 ]]; then
    	if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo " found"; fi
    	continue        
    else
        IPAddress=${ip}
        if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then echo " new"; fi
        break
    fi
done

genKeys
showKeys
if [ ${FLAGS_write} -eq ${FLAGS_TRUE} ]; then
 addToWG >> ${WG_conf}
 clientFile >> ${WG_etc}/clients/${FLAGS_name}.conf
else
    echo "**** Add to wg0.conf ****" ;addToWG;echo
    echo "**** Client file ****"; clientFile
    if [ ${FLAGS_debug} -eq ${FLAGS_TRUE} ]; then exit; fi
    while true; do
	read -t 5 -p "Записать настройки (y)?" yn
    	case $yn in
    	    [Yy]* )
        	addToWG >> ${WG_conf}
            	clientFile >> ${WG_etc}/clients/${FLAGS_name}.conf
            	break
            	;;
            * )
        	echo
            	echo "Не записали"
            	break
            	;;
    	esac
	done
fi
