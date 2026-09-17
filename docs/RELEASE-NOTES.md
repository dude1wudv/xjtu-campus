# 产品发布说明

发布渠道：[GitHub Releases](https://github.com/dude1wudv/xjtu-campus/releases)。  
应用内更新对照 **`/releases/latest`**（忽略 Pre-release 标签）。推荐资源名：`xjtu-campus-arm64-release.apk`。

## v1.5.4（正式版 · Latest）

**标签**：`v1.5.4` · **构建**：`1.5.4+21` · **分支合入**：`feat/mobile-ui-refresh` → `main`

### 用户可见能力

- **移动端 UI 刷新**：统一校园蓝主题、首页服务入口重组、减少抢先渲染
- **WebVPN**：校外场景下更多校园服务经 WebVPN 连通
- **考勤**：课表相关考勤；登录/网关失败有明确提示（HTTPS WebVPN）
- **作业中心**：思源学堂作业列表与校历截止日期
- 继承 v1.5.0：校园卡、图书馆座位、应用内更新

### 安装

1. 从 [Latest Release](https://github.com/dude1wudv/xjtu-campus/releases/latest) 下载 `xjtu-campus-arm64-release.apk`，或在应用内检查更新
2. 覆盖安装可保留本地数据（同包名、同签名）

### 文档

- `README.md`
- `docs/ncard-campus-card.md` / `docs/library-seats.md`

## v1.5.0

校园卡、图书馆座位（Cookie http:8086 落盘修复）、手动强制刷新。详见历史 Release。

## v1.4.0

本地 stale-while-revalidate 快照缓存。

## 发版检查清单（维护者）

1. `pubspec.yaml` 版本号（`x.y.z+build`，正式版勿带 `-card.N` 后缀）
2. `flutter build apk --release --target-platform=android-arm64`
3. 将产物命名为 `xjtu-campus-arm64-release.apk`
4. `git tag vX.Y.Z` 并 `gh release create vX.Y.Z --latest`（**不要** Pre-release）上传 APK
5. 确认 `https://api.github.com/repos/dude1wudv/xjtu-campus/releases/latest`
6. 更新本文件与 `README.md`，并合入 `main`
