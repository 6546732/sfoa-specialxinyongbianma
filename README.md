# sfoa-specialxinyongbianma

Salesforce 特殊客户编码模块。

主要能力：

- DeepSeek 联网补全客户国家、省份、城市、行业和登记信息；
- 对企业历史名称、繁简体及日文名称进行扩展检索；
- 仅在名称完全匹配、来源有效且校验通过时采用网上统一社会信用代码；
- 其余情况按内部规则生成中国大陆、军队、港澳台和国外客户编码；
- 保存联网查询、编码来源、失败原因及生成结果审计记录。

默认部署目录为 `force-app`。目标测试组织别名为 `zihao`，不得提交任何凭据或授权文件。

## 非托管包

目标包为 `code`，包括14个Apex类、页面组件和快速操作、权限集、两个业务对象、两个Account字段、六种自定义元数据类型及436条规则记录。

- [包内组件与安装前置依赖](docs/INSTALLATION.md)
- [版本及安装链接](docs/RELEASE.md)
- 普通部署清单：`manifest/package.xml`
- 非托管包清单：`manifest/unmanaged-code.xml`
- 安装后序列初始化：`scripts/apex/initialize-missing-sequences.apex`（只补缺失记录，起始值须人工确认）

DeepSeek凭据、用户主体授权、页面按钮配置、权限集分配和序列当前值不随源码数据迁移。本仓库不包含API Key、用户访问令牌、客户数据或历史审计数据。
