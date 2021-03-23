#!/usr/bin/bash    
dnspod_ddnsipv6_id="123456" #【API_id】将引号内容修改为获取的API的ID
dnspod_ddnsipv6_token="1a2b3c4d5e6f7g8h9i0" #【API_token】将引号内容修改为获取的API的token
dnspod_ddnsipv6_ttl="600" # 【ttl时间】解析记录在 DNS 服务器缓存的生存时间，默认600(s/秒)
dnspod_ddnsipv6_domain='baidu.com' #【已注册域名】引号里改成自己注册的域名
dnspod_ddnsipv6_subdomain='pan' #【二级域名】将引号内容修改为自己想要的名字，需要符合域名规范，附常用的规范
get_ipv6_mode='2' # 【获取IPV6方式】支持两种方式，第一种是直接从你的网卡获取，用这种方法请填1。一种是通过访问网页接口获取公网IP6，这种方法请填2
local_net="eth0" # 【网络适配器】 默认为eth0，如果你的公网ipv6地址不在eth0上，需要修改为对应的网络适配器
# 常用的规范【二级域名】
# 【www】 常见主机记录，将域名解析为 www.baidu.com
# 【@】   直接解析主域名 baidu.com
# 【*】   泛解析，匹配其他所有域名 *.baidu.com



# 举例
# 在腾讯云注册域名，登陆DNSPOD，在【我的账号】的【账号中心】中，有【密钥管理】
# 点击创建密钥即可创建一个API
# 如果你在腾讯云注册域名叫【baidu.com】
# 那么【dnspod_ddnsipv6_domain】后面就填【baidu.com】
# 然后根据常用的规范/自己想要的名字在【dnspod_ddnsipv6_subdomain】填入自己需要的名字
# 现假设为【pan】，那么你的访问地址为【pan.baidu.com】
if [ "$dnspod_ddnsipv6_record" = "@" ]
then
  dnspod_ddnsipv6_name=$dnspod_ddnsipv6_domain
else
  dnspod_ddnsipv6_name=$dnspod_ddnsipv6_subdomain.$dnspod_ddnsipv6_domain
fi

die0 () {
    echo "IPv6地址提取错误,无ipv6地址或非公网IP（fe80开头的非公网IP）"
	exit
}

die1 () {  
	echo "IPv6地址提取错误,请使用ip addr命令查看自己的网卡中是否有IPv6公网（非fe80开头）地址，若网卡有IPv6地址却无法获取成功，可尝试在脚本中切换第二种模式获取"
    exit
}

die2 () {
    echo "尝试访问网页http://[2606:4700:4700::1111]/cdn-cgi/trace  查看返回的IPv6地址是否能够正常访问本机，无法访问网页则切换第一种模式获取"
	exit
}

if [[ "$get_ipv6_mode" == 1 ]]
    then
        echo "使用本地网卡获取IPv6"
		ipv6_list=`ip addr show $local_net | grep "inet6.*global" | awk '{print $2}' | awk -F"/" '{print $1}'` || die1
    else
        echo "使用网页接口获取IPv6"
		ipv6_list=$(curl -s -g http://[2606:4700:4700::1111]/cdn-cgi/trace | sed -n '3p' ) || die
        ipv6_list=${ipv6_list##*=}     
    fi






for ipv6 in ${ipv6_list[@]}
do
    if [[ "$ipv6" =~ ^fe80.* ]]
    then
        continue
    else
        echo 获取的IP为: $ipv6 >&1
        break
    fi
done

if [ "$ipv6" == "" ] || [[ "$ipv6" =~ ^fe80.* ]]
then
    die0
fi

dns_server_info=`nslookup -query=AAAA $dnspod_ddnsipv6_name 2>&1`

dns_server_ipv6=`echo "$dns_server_info" | grep 'address ' | awk '{print $NF}'`
if [ "$dns_server_ipv6" = "" ]
then
    dns_server_ipv6=`echo "$dns_server_info" | grep 'Address: ' | awk '{print $NF}'`
fi
    
if [ "$?" -eq "0" ]
then
    echo "你的DNS服务器IP: $dns_server_ipv6" >&1

    if [ "$ipv6" = "$dns_server_ipv6" ]
    then
        echo "该地址与DNS服务器相同。" >&1
    fi
    unset dnspod_ddnsipv6_record_id
else
    dnspod_ddnsipv6_record_id="1"   
fi

send_request() {
    local type="$1"
    local data="login_token=$dnspod_ddnsipv6_id,$dnspod_ddnsipv6_token&domain=$dnspod_ddnsipv6_domain&sub_domain=$dnspod_ddnsipv6_subdomain$2"
    return_info=`curl -X POST "https://dnsapi.cn/$type" -d "$data" 2> /dev/null`
}

query_recordid() {
    send_request "Record.List" ""
}

update_record() {
    send_request "Record.Modify" "&record_type=AAAA&record_line=默认&ttl=$dnspod_ddnsipv6_ttl&value=$ipv6&record_id=$dnspod_ddnsipv6_record_id"
}

add_record() {
    send_request "Record.Create" "&record_type=AAAA&record_line=默认&ttl=$dnspod_ddnsipv6_ttl&value=$ipv6"
}

if [ "$dnspod_ddnsipv6_record_id" = "" ]
then
    echo "解析记录已存在，尝试更新它" >&1
    query_recordid
    code=`echo $return_info  | awk -F \"code\":\" '{print $2}' | awk -F \",\"message\" '{print $1}'`
    echo "返回代码： $code" >&1
    if [ "$code" = "1" ]
    then
        dnspod_ddnsipv6_record_id=`echo $return_info | awk -F \"records\":.{\"id\":\" '{print $2}' | awk -F \",\"ttl\" '{print $1}'`
        update_record
        echo "更新解析成功" >&1
    else
        echo "错误代码返回，域名不存在，请尝试添加。" >&1
        add_record
        echo "添加成功" >&1
    fi
else
    echo "该域名不存在，请在dnspod控制台添加"
    add_record
    echo "添加成功" >&1
fi
