#!/bin/bash
set -euo pipefail

# -------------------------- 配置项（通过.env文件覆盖） --------------------------
# 默认值，会被.env文件中的配置覆盖
PRIVATE_DOMAIN=""
DNS_REGISTRY=""
UPDATE_DNS_TOKEN=""
DNS_UPDATE_DNS_SERVER="8.8.8.8"
DNS_UPDATE_TIMEOUT=10

# -------------------------- 工具函数：获取公网IP --------------------------
get_public_ip() {
    local timeout="${1:-10}"
    # 尝试多个公网IP检测接口，提高可用性
    local ip=$(curl -s --max-time "$timeout" https://icanhazip.com || \
               curl -s --max-time "$timeout" https://ifconfig.me/ip || \
               curl -s --max-time "$timeout" https://ipinfo.io/ip)
    ip=$(echo "$ip" | tr -d '\n' | tr -d '\r')
    # 验证IPv4格式
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: 公网IP格式非法 - $ip"
        return 1
    fi
}

# -------------------------- 工具函数：解析域名DNS IP --------------------------
get_domain_ip() {
    local domain="$1"
    local dns_server="${2:-8.8.8.8}"
    local timeout="${3:-10}"
    # 使用dig解析域名（比nslookup更稳定）
    local ip=$(dig +short +time="$timeout" @"$dns_server" "$domain" A | head -n1)
    if [[ -z "$ip" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: 解析域名 $domain 失败"
        return 1
    fi
    echo "$ip"
    return 0
}

# -------------------------- 主程序逻辑 --------------------------
main() {
    # 1. 加载.env配置（默认读取当前目录的.env，可传参指定路径）
    source .env

    # 2. 校验必要配置
    if [[ -z "$PRIVATE_DOMAIN" || -z "$DNS_REGISTRY" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: .env文件中必须配置 PRIVATE_DOMAIN 和 DNS_REGISTRY"
        exit 1
    fi

    # 3. 获取公网IP和域名解析IP
    PUBLIC_IP=$(get_public_ip "$DNS_UPDATE_TIMEOUT") || exit 1
    DOMAIN_IP=$(get_domain_ip "$PRIVATE_DOMAIN" "$DNS_UPDATE_DNS_SERVER" "$DNS_UPDATE_TIMEOUT") || exit 1

    # 4. 对比IP并更新DNS
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: 域名 $PRIVATE_DOMAIN 解析IP: $DOMAIN_IP | 本地公网IP: $PUBLIC_IP"
    if [[ "$PUBLIC_IP" != "$DOMAIN_IP" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: IP不一致，开始更新DNS..."
        # 替换URL中的{IP}占位符
        FINAL_URL="$DNS_REGISTRY?ipv4=auto&token=$UPDATE_DNS_TOKEN&zone=$PRIVATE_DOMAIN"
        # 调用更新接口
        RESPONSE=$(curl -s --max-time "$DNS_UPDATE_TIMEOUT" "$FINAL_URL")
        if [[ $? -eq 0 ]]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: DNS更新成功，接口返回: $RESPONSE"
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: DNS更新失败"
            exit 1
        fi
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: IP一致，无需更新DNS"
    fi
}

# 执行主程序（支持传参指定.env文件路径）
main "$@"
exit 0