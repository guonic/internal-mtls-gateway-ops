# gateway-mtls-ops
> 面向 API 网关的双向认证（mTLS）全链路运维自动化套件

## 仓库简介
本仓库提供一套开箱即用的 **mTLS 网关运维工具链**，覆盖证书生命周期管理、服务治理、连接监控与审计等核心场景，支持 Nginx、Kong、Istio 等主流网关，可无缝集成 CI/CD 流水线，帮助团队快速落地网关双向认证架构，降低运维成本。

## 核心功能
### 1. 双向认证（mTLS）证书全生命周期管理
- 自动化完成客户端/服务端 TLS 证书的生成、部署、轮转与吊销流程
- 支持基于 PKI 基础设施的证书有效性校验，以及满足行业标准的合规性检查

### 2. 网关服务治理与运维
- 提供一键启停/重启 mTLS 网关服务的能力，内置服务可用性健康检查机制
- 实现多环境网关（开发/测试/生产）配置同步，配置变更纳入版本控制

### 3. mTLS 连接监控与审计
- 实时追踪 mTLS 握手状态与连接核心指标（延迟、吞吐量、错误率）
- 生成证书使用记录与访问控制事件的审计日志，满足合规审计需求

### 4. 运维自动化脚本套件
- 提供可复用的 Shell/Python 脚本，覆盖证书续签、日志清理、配置备份等日常运维任务
- 支持与 CI/CD 流水线集成，实现网关自动化部署与 mTLS 配置更新

### 5. 多网关兼容性适配
- 兼容主流 API 网关（Nginx、Kong、Istio Ingress Gateway 等），提供统一 mTLS 配置模板
- 提供适配脚本，实现异构网关环境下的 mTLS 无缝部署

## 快速开始
### 1. 克隆仓库（含子模块）
```bash
# 初始化
./manage_certs.sh init

# 签发服务端证书（修改 openssl.cnf 中的 [alt_names] 为你的真实域名后再执行）
./manage_certs.sh server example.com

# 签发客户端证书：
./manage_certs.sh client my-browser

# 此时会生成 my-ca/client/my-browser.p12，将其导入 Chrome/Edge/Firefox。

# 在 Nginx 配置文件中加入：
server {
    listen 443 ssl;
    server_name example.com;

    # 服务端证书 (给浏览器看的)
    ssl_certificate      /path/to/my-ca/certs/server.cert.pem;
    ssl_certificate_key  /path/to/my-ca/private/server.key.pem;

    # 客户端校验配置 (mTLS核心)
    ssl_verify_client on;
    ssl_client_certificate /path/to/my-ca/certs/ca.cert.pem; # 用来验证客户端的根

    # 吊销列表 (可选，如果启用了吊销功能)
    # ssl_crl /path/to/my-ca/crl/ca.crl.pem;

    location / {
        root html;
    }
}

# 吊销证书
查看 index.txt，第一列为 V (Valid) 表示有效，R (Revoked) 表示已吊销。找到对应的十六进制序列号。
执行吊销（假设序列号为 1001）：

./manage_certs.sh revoke 1001
注意：吊销后，必须重新开启 Nginx 中 ssl_crl 的注释，并指向生成的 ca.crl.pem 文件。每次吊销新证书后，都需要执行 revoke 命令同步更新 CRL 文件。