#!/bin/sh
# 在alpine中部署singbox和订阅转换，并自动化更新。
set -e
# 判断脚本是否有root权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用root用户运行脚本！"
    exit 1
fi
SINGBOX_RUNSCRIBE="https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-update-and-start.sh"
# 如果有参数并且以https://开头则作为下载加速镜像添加到SINGBOX_RUNSCRIBE
if [ "$1" ] && [ "$(expr substr "$1" 1 8)" = "https://" ]; then
    # 如果$1不是/结尾则结尾添加/
    if expr "$1" : '.*/$' > /dev/null; then
        SINGBOX_RUNSCRIBE="$1$SINGBOX_RUNSCRIBE"
    else
        SINGBOX_RUNSCRIBE="$1/$SINGBOX_RUNSCRIBE"
    fi
fi
# 初始化Alpine系统，适配版本3.20
echo "初始化 Alpine 系统..."
apk update
apk upgrade
echo "安装常用工具..."
apk add curl nftables openssh net-tools tzdata jq git python3 py3-pip
# 设定时区
echo "设置时区..."
rm -f /etc/localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
rm -f /etc/timezone
echo "Asia/Shanghai" > /etc/timezone
# 检查是否已允许root远程登录
if grep -q "^PermitRootLogin yes[[:space:]]*#?.*$" /etc/ssh/sshd_config; then
    echo "root远程登录已允许，跳过。"
else
    echo "修改 sshd 配置，允许root远程登录..."
    echo -e "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

# 备份并清空nftables.nft文件，防止默认规则影响。
if [ -f "/etc/nftables.nft" ]; then
    echo "nftables.nft文件已存在，清空..."
    if [ -f "/etc/nftables.nft.bak" ]; then
        echo "备份文件已存在，删除当前/etc/nftables.nft文件..."
        rm -f /etc/nftables.nft
    else
        echo "备份文件不存在，备份..."
        mv /etc/nftables.nft /etc/nftables.nft.bak
    fi
fi
# 创建空/etc/nftables.nft文件
tuch /etc/nftables.nft

# 开启转发
echo "设置开启转发支持..."
# 检查/etc/local.d/enable_forwarding.start是否存在，不存在则创建
if [ ! -f "/etc/local.d/enable_forwarding.start" ]; then
    echo -e "#!/bin/sh\nsysctl -w net.ipv4.ip_forward=1\nsysctl -w net.ipv6.conf.all.forwarding=1" > /etc/local.d/enable_forwarding.start
fi
chmod +x /etc/local.d/enable_forwarding.start
# 如果已开启，则跳过
if sysctl -n net.ipv4.ip_forward | grep -q 1; then
    echo "转发已开启，跳过。"
else
    echo "开启转发..."
    /etc/local.d/enable_forwarding.start
fi

# 重启服务,并将所需服务添加到系统启动项
echo "启动nftables, sshd服务..."
rc-service nftables restart
rc-service sshd restart
echo "添加服务到启动项..."
# 给与nftables服务boot运行级
rc-update add nftables boot
# 其他服务使用默认运行级
rc-update add sshd default
# 开机执行脚本服务
rc-update add local default
# 计划任务服务
rc-update add crond default

# 安装singbox
apk add sing-box --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
rc-update add sing-box default
# 如果目录不存在建立/opt/sing-box-update-and-start文件夹
if [ ! -d "/opt/sing-box-update-and-start" ]; then
    mkdir -p /opt/sing-box-update-and-start
fi
# 下载singbox升级和开始脚本
set +e
wget -O /opt/sing-box-update-and-start/singbox-update-and-start.sh ${SINGBOX_RUNSCRIBE}
if [ $? -ne 0 ]; then
    echo "下载singbox升级和开始脚本失败，请检查网络连接或镜像地址。"
    exit 1
fi
set -e
chmod +x /opt/sing-box-update-and-start/singbox-update-and-start.sh
cat > /opt/sing-box-update-and-start/settings.json << EOF
{
    "subscribe_expire_time": 7,
    "subscribe_url": "",
    "user_agent": "clashmeta",
    "exclude_keyword": "网站|地址|剩余|过期|时间|有效|到期|官网",
    "config_template_file": "https://raw.githubusercontent.com/lvxj11/lvxj11PDP/refs/heads/main/sing-box/singbox-1.11-tun-fakeip-template-nomirror.json"
}
EOF
# 检查计划任务是否已存在
if grep -q "singbox-update-and-start.sh" /etc/crontabs/root; then
    echo "计划任务已存在，跳过添加计划任务。"
else
    # 添加计划任务每天凌晨2点运行一次
    echo "添加计划任务..."
    echo "0 2 * * * /opt/sing-box-update-and-start/singbox-update-and-start.sh" >> /etc/crontabs/root
fi
# 安装完成
echo "安装完成。"
echo "在/opt/sing-box-update-and-start/settings.json文件中添加参数，"
echo "或修改/opt/sing-box-update-and-start/singbox-update-and-start.sh脚本中的参数。"
echo "执行一次获取配置文件，测试是否正常运行。"
echo "建议重启一次应用所有更改并验证。"
exit 0