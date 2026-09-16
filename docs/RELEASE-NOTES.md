# 产品发布说明

发布渠道：[GitHub Releases](https://github.com/dude1wudv/xjtu-campus/releases)。  
应用内更新对照 **`/releases/latest`**（忽略 Pre-release 标签）。推荐资源名：`xjtu-campus-arm64-release.apk`。

## v1.5.0（正式版 · Latest）

**标签**：`v1.5.0` · **构建**：`1.5.0+17` · **分支合入**：`feat/campus-card` → `main`

### 用户可见能力

- **校园卡**：余额与近 90 天流水（只读）；支持手机模式「打开校园卡登录同步」完成 ncard SSO
- **图书馆座位**（需校园网 / WebVPN 可达座位站）：区域空座查询、偏好座位与有限次回退尝试；登录 Cookie 写入共享会话并落盘
- **手动强制刷新**：关键模块可主动绕过缓存拉取
- **应用内更新**：关于页检查更新；首页软提示；下载后调起系统安装器

### 重要修复

- 图书馆登录后 Cookie 未正确进入 Dio / `PersistCookieJar` 的问题
- Cookie 导入被写成 HTTPS，与座位站 `http://rg.lib.xjtu.edu.cn:8086`（及历史 `8010`）会话槽位不一致
- Android 明文 HTTP（cleartext）对图书馆相关主机放行

### 安装

1. 从 [Latest Release](https://github.com/dude1wudv/xjtu-campus/releases/latest) 下载 `xjtu-campus-arm64-release.apk`，或在应用内检查更新  
2. 覆盖安装可保留本地数据（同包名、同签名）  
3. 图书馆功能请在校园网环境下完成图书馆登录后再用

### 文档

- `docs/ncard-campus-card.md`
- `docs/library-seats.md`
- 仓库根目录 `README.md`

### 历史预发布

`v1.5.0-card.1` … `v1.5.0-card.9` 为实验迭代 Pre-release，仅作历史记录；正式能力以本版 Latest 为准。

## v1.4.0

本地 stale-while-revalidate 快照缓存（冷启动先展示上次成功实时数据）。详见当时 Release 说明。

## 发版检查清单（维护者）

1. `pubspec.yaml` 版本号（`x.y.z+build`，正式版勿带 `-card` 等预发布后缀）  
2. `flutter build apk --release --target-platform=android-arm64`  
3. 将产物命名为 `xjtu-campus-arm64-release.apk`  
4. `git tag vX.Y.Z` 并 `gh release create vX.Y.Z --latest`（**不要**勾选 Pre-release）上传 APK  
5. 用未登录浏览器或 `curl` 确认 `https://api.github.com/repos/dude1wudv/xjtu-campus/releases/latest` 的 `tag_name` 与 assets  
6. 更新本文件与 `README.md`「当前正式版」段落，并合入 `main`
