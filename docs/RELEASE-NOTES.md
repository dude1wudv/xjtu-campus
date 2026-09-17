# 产品发布说明

发布渠道：[GitHub Releases](https://github.com/dude1wudv/xjtu-campus/releases)。  
应用内更新对照 **`/releases/latest`**（忽略 Pre-release 标签）。推荐资源名：`xjtu-campus-arm64-release.apk`。

## v1.5.5（正式版 · Latest）

**标签**：`v1.5.5` · **构建**：`1.5.5+34` · **分支合入**：`feat/mobile-ui-refresh` → `main`

### 用户可见能力

- **移动端 UI**：玻璃拟态表面、统一主题、桌面小组件与背景设置
- **WebVPN**：校外校园服务连通与连接卡片体验
- **本科考勤**：新工作台 / 学生入口；官方会话交接；登录诊断与失败流保留
- **作业中心**：按学期筛选，默认本学期课程
- 继承 v1.5.4 / v1.5.0：校园卡、图书馆座位、应用内更新等

### 安装

1. 从 [Latest Release](https://github.com/dude1wudv/xjtu-campus/releases/latest) 下载 `xjtu-campus-arm64-release.apk`，或在应用内检查更新
2. 覆盖安装可保留本地数据（同包名、同签名）

### 文档

- `README.md`
- `docs/ncard-campus-card.md` / `docs/library-seats.md`

## v1.5.4

移动端 UI 刷新、WebVPN、考勤与作业初版合入。见历史 Release。

## v1.5.0

校园卡、图书馆座位（Cookie http:8086 落盘修复）。

## 发版检查清单（维护者）

1. `pubspec.yaml` 版本号（`x.y.z+build`，正式版勿带 `-dev` / `-card` 后缀）
2. `flutter build apk --release --target-platform=android-arm64`
3. 产物命名：`xjtu-campus-arm64-release.apk`
4. `git tag vX.Y.Z` 并 `gh release create vX.Y.Z --latest`（不要 Pre-release）
5. 确认 `releases/latest` API
6. 更新本文件与 README，并合入 `main`
