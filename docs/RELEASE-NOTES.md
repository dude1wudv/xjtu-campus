# 产品发布说明

发布渠道：[GitHub Releases](https://github.com/dude1wudv/xjtu-campus/releases)。  
应用内更新对照 **`/releases/latest`**。推荐资源名：`xjtu-campus-arm64-release.apk`。

## v1.5.6（正式版 · Latest）

**标签**：`v1.5.6` · **构建**：`1.5.6+35` · **合入**：PR #1 `feat/campus-web-experience` + PR #2 `feat/unified-status-today-tasks` → `main`

### 用户可见能力

- 首页突出正在进行/下一节课；宽屏双栏与侧边导航
- 周课表增强与课程详情（作业/考勤匹配、本地笔记）
- 响应式网页端（课表导入导出；无 CAS 密码登录）
- 统一 DataStatus：加载/缓存/认证/失败提示一致
- 今日任务中心：课程、作业、考试与个人待办

### 修复

- Widget 测试适配新导航与协议门；测试环境跳过 dean 通知 WebView

## v1.5.5

玻璃 UI、本科考勤工作台、作业按学期筛选。

## 发版检查清单（维护者）

1. `pubspec.yaml` 正式版本号
2. `flutter build apk --release --target-platform=android-arm64`
3. 命名 `xjtu-campus-arm64-release.apk`
4. `gh release create vX.Y.Z --latest`
5. 更新本文件与 README，合入 `main`
