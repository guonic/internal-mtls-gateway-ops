#!/bin/bash

set -e  # 遇到错误立即退出

# 检查 PRIVATE_DOMAIN 环境变量
if [ -z "$PRIVATE_DOMAIN" ]; then
    echo "错误: 请设置 PRIVATE_DOMAIN 环境变量"
    echo "例如: export PRIVATE_DOMAIN=nexus-quant.dynv6.net"
    exit 1
fi

BASE_DIR="./certs/${PRIVATE_DOMAIN}"
CONFIG="${BASE_DIR}/openssl.cnf"

# 检查配置文件是否存在
function check_config() {
    if [ ! -f "$CONFIG" ]; then
        echo "错误: 找不到配置文件: $CONFIG"
        exit 1
    fi
}

# 检查 CA 证书是否存在
function check_ca() {
    local ca_cert="${BASE_DIR}/certs/ca.cert.pem"
    if [ ! -f "$ca_cert" ]; then
        echo "错误: CA 证书不存在: $ca_cert"
        echo "请先运行: $0 init"
        exit 1
    fi
}

# 确保目录存在
function ensure_dirs() {
    mkdir -p ${BASE_DIR}/{certs,crl,newcerts,private,client}
    
    # 只在文件不存在时创建，避免覆盖已有的序列号
    if [ ! -f "${BASE_DIR}/index.txt" ]; then
        touch "${BASE_DIR}/index.txt"
    fi
    
    if [ ! -f "${BASE_DIR}/serial" ]; then
        echo "1000" > "${BASE_DIR}/serial"
    fi
    
    if [ ! -f "${BASE_DIR}/crlnumber" ]; then
        echo "1000" > "${BASE_DIR}/crlnumber"
    fi
}

function init_ca() {
    echo "--- 正在生成根 CA ---"
    check_config
    ensure_dirs
    
    # 初始化 CA 数据库文件
    if [ ! -f "${BASE_DIR}/index.txt" ]; then
        touch "${BASE_DIR}/index.txt"
    fi
    
    if [ ! -f "${BASE_DIR}/serial" ]; then
        echo "1000" > "${BASE_DIR}/serial"
    fi
    
    if [ ! -f "${BASE_DIR}/crlnumber" ]; then
        echo "1000" > "${BASE_DIR}/crlnumber"
    fi
    
    if ! openssl genrsa -out "${BASE_DIR}/private/ca.key.pem" 4096; then
        echo "错误: 生成 CA 私钥失败"
        exit 1
    fi
    
    if ! openssl req -config "$CONFIG" -key "${BASE_DIR}/private/ca.key.pem" \
        -new -x509 -days 7300 -sha256 -extensions v3_ca \
        -out "${BASE_DIR}/certs/ca.cert.pem" \
        -subj "/CN=My Personal Root CA"; then
        echo "错误: 生成 CA 证书失败"
        exit 1
    fi
    
    echo "CA 已生成: ${BASE_DIR}/certs/ca.cert.pem"
}


function issue_server() {
    local domain=$1
    if [ -z "$domain" ]; then
        echo "错误: 请提供域名参数"
        exit 1
    fi
    
    echo "--- 正在为 $domain 签发服务端证书 ---"
    check_config
    check_ca
    ensure_dirs
    
    if ! openssl genrsa -out "${BASE_DIR}/private/server.key.pem" 2048; then
        echo "错误: 生成服务端私钥失败"
        exit 1
    fi
    
    if ! openssl req -config "$CONFIG" -new -sha256 \
        -key "${BASE_DIR}/private/server.key.pem" \
        -out "${BASE_DIR}/certs/server.csr.pem" \
        -subj "/CN=$domain"; then
        echo "错误: 生成服务端证书请求失败"
        exit 1
    fi

    # 切换到 BASE_DIR 目录执行 openssl ca，确保配置文件中的相对路径正确解析
    local current_dir=$(pwd)
    cd "${BASE_DIR}" || exit 1
    
    if ! openssl ca -config openssl.cnf -extensions server_cert -days 825 -notext -md sha256 \
        -in "certs/server.csr.pem" \
        -out "certs/server.cert.pem" -batch; then
        cd "$current_dir" || true
        echo "错误: CA 签发服务端证书失败"
        exit 1
    fi
    
    cd "$current_dir" || true

    echo "服务端证书已生成: ${BASE_DIR}/certs/server.cert.pem"
}

function issue_client() {
    local user=$1
    if [ -z "$user" ]; then
        echo "错误: 请提供用户名参数"
        exit 1
    fi
    
    echo "--- 正在为用户 $user 签发客户端证书 ---"
    check_config
    check_ca
    ensure_dirs
    
    # 生成私钥
    if ! openssl genrsa -out "${BASE_DIR}/client/${user}.key.pem" 2048; then
        echo "错误: 生成客户端私钥失败"
        exit 1
    fi
    
    # 生成请求
    if ! openssl req -config "$CONFIG" -new -sha256 \
        -key "${BASE_DIR}/client/${user}.key.pem" \
        -out "${BASE_DIR}/client/${user}.csr.pem" \
        -subj "/CN=$user"; then
        echo "错误: 生成客户端证书请求失败"
        exit 1
    fi
    
    # CA 签发 - 切换到 BASE_DIR 目录执行 openssl ca
    local current_dir=$(pwd)
    cd "${BASE_DIR}" || exit 1
    
    if ! openssl ca -config openssl.cnf -extensions client_cert -days 365 -notext -md sha256 \
        -in "client/${user}.csr.pem" \
        -out "client/${user}.cert.pem" -batch; then
        cd "$current_dir" || true
        echo "错误: CA 签发客户端证书失败"
        exit 1
    fi
    
    cd "$current_dir" || true

    # 检查证书文件是否生成成功
    if [ ! -f "${BASE_DIR}/client/${user}.cert.pem" ]; then
        echo "错误: 客户端证书文件未生成"
        exit 1
    fi

    # 导出为浏览器可安装的 PKCS12 格式 (.p12)
    if ! openssl pkcs12 -export -clcerts \
        -in "${BASE_DIR}/client/${user}.cert.pem" \
        -inkey "${BASE_DIR}/client/${user}.key.pem" \
        -out "${BASE_DIR}/client/${user}.p12" \
        -passout pass:123456; then
        echo "错误: 导出 PKCS12 格式失败"
        exit 1
    fi

    echo "客户端证书已生成: ${BASE_DIR}/client/${user}.p12 (密码: 123456)"
}

function revoke_cert() {
    local serial=$1
    if [ -z "$serial" ]; then
        echo "错误: 请提供证书序列号参数"
        exit 1
    fi
    
    echo "--- 正在吊销序列号为 $serial 的证书 ---"
    check_config
    check_ca
    
    if [ ! -f "${BASE_DIR}/newcerts/${serial}.pem" ]; then
        echo "错误: 找不到证书文件: ${BASE_DIR}/newcerts/${serial}.pem"
        exit 1
    fi
    
    # 切换到 BASE_DIR 目录执行 openssl ca
    local current_dir=$(pwd)
    cd "${BASE_DIR}" || exit 1
    
    if ! openssl ca -config openssl.cnf -revoke "newcerts/${serial}.pem"; then
        cd "$current_dir" || true
        echo "错误: 吊销证书失败"
        exit 1
    fi
    
    # 更新 CRL 文件
    if ! openssl ca -config openssl.cnf -gencrl -out "crl/ca.crl.pem"; then
        cd "$current_dir" || true
        echo "错误: 更新 CRL 列表失败"
        exit 1
    fi
    
    cd "$current_dir" || true
    
    echo "CRL 列表已更新: ${BASE_DIR}/crl/ca.crl.pem"
}

case "$1" in
    init) init_ca ;;
    server) issue_server $2 ;;
    client) issue_client $2 ;;
    revoke) revoke_cert $2 ;;
    *) echo "Usage: $0 {init|server <domain>|client <user>|revoke <serial>}" ;;
esac