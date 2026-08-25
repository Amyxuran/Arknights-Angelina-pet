# GitHub 发布方案

## 发布前提

1. 确认仓库内角色动画、应用图标和 UI 图片具有公开转载与二进制再分发授权。未取得授权时，先将这些文件替换为自行创作或已取得明确许可的素材。
2. 加入 Apple Developer Program，申请 `Developer ID Application` 证书。
3. 在 Apple ID 中创建供公证使用的 App 专用密码。
4. 创建 GitHub 仓库，将默认分支设为 `main`。
5. 确定源码许可。当前仓库没有附加开源许可证，默认保留全部源码权利；需要允许他人修改和再发布代码时，单独加入 MIT、Apache-2.0 等源码许可证，并明确排除第三方美术素材。

Apple 要求从 Mac App Store 以外分发的应用使用 Developer ID 签名并提交公证。发布脚本同时启用 Hardened Runtime、时间戳、公证和票据装订。

## GitHub Secrets

在仓库的 `Settings > Secrets and variables > Actions` 中添加：

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application `.p12` 文件的 Base64 内容 |
| `P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码，使用独立随机值 |
| `SIGN_IDENTITY` | 完整签名身份，例如 `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple Developer 账号邮箱 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_PASSWORD` | Apple ID App 专用密码 |

生成证书 Secret：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

所有凭据只存入 GitHub Secrets，不写入仓库文件、提交记录和 Release 说明。

## 首次建立仓库

```bash
git init
git add .
git commit -m "Release Lime Courier 2.0.0"
git branch -M main
git remote add origin git@github.com:OWNER/REPOSITORY.git
git push -u origin main
```

## 发布版本

先更新 `App/Info.plist` 中的版本号和 `CHANGELOG.md`，再执行：

```bash
git add App/Info.plist CHANGELOG.md
git commit -m "Prepare v2.0.0"
git tag -a v2.0.0 -m "v2.0.0"
git push origin main v2.0.0
```

`.github/workflows/release.yml` 在收到 `v*` 标签后执行以下步骤：

1. 运行 Swift 测试。
2. 导入 Developer ID 证书。
3. 构建应用并启用 Hardened Runtime 签名。
4. 使用 `notarytool` 提交 Apple 公证。
5. 将公证票据装订到应用。
6. 生成 ZIP 安装包和 SHA-256 校验文件。
7. 创建 GitHub Release 并上传两个文件。

## 本地正式打包

```bash
export SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
export APPLE_ID="developer@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/package_release.sh
```

正式产物位于 `dist/release/`。本地开发构建继续使用 `./scripts/build_app.sh`，该命令执行临时签名，不能作为公开下载版本。

## 发布验收

1. 在一台未安装开发证书的 Apple Silicon Mac 上下载 Release ZIP。
2. 校验 SHA-256，解压并将应用拖入 `/Applications`。
3. 确认首次启动显示已识别开发者，不出现“应用已损坏”提示。
4. 验证菜单栏图标、开机启动、待机动作、全部互动、左右吸附与退出流程。
5. 检查 Release 页面包含功能摘要、macOS 最低版本、支持架构和素材声明。
