# 交大校园助手（xjtu_campus）

面向西安交通大学在校学生的跨平台校园助手骨架。当前版本只提供 **可运行的 Flutter 工程、清晰的模块边界和本地模拟数据**，方便后续接入统一身份认证与教务服务。

## 产品愿景

1. 使用学校统一身份认证（CAS，`login.xjtu.edu.cn`）登录。
2. 拉取课表、空闲教室、日程和教务通知。
3. 根据课表一键生成起床闹钟与上课提醒。
4. 用本地规则整理教务通知，并给出个性化提醒。

本仓库是 MVP 脚手架：**不连接学校服务器，不处理真实密码登录，不抓取未授权页面。**

## 如何运行

环境要求：Flutter 3.47+（Dart 3.13+）。

```bash
flutter pub get
flutter run
```

常用目标：

```bash
flutter run -d linux
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

静态检查与测试：

```bash
flutter analyze
flutter test
```

## 模块地图

```
lib/
  core/           主题、路由、安全存储、网络占位、中文文案
  features/
    auth/         CAS 登录界面 + AuthRepository 接口 + Mock 实现
    schedule/     课表模型 / 仓库 / 模拟数据 / 列表与周视图
    classroom/    空闲教室筛选占位
    notifications/教务通知列表与本地过滤规则
    alarms/       起床/课前提醒计算 + 一键创建（当前为模拟）
    home/         底部导航壳与首页
```

| 模块 | 现状 | 后续对接 |
| --- | --- | --- |
| 认证 | `MockAuthRepository`，任意学号+密码进入模拟会话 | `CasAuthRepository` → [login.xjtu.edu.cn](https://login.xjtu.edu.cn) |
| 课表 | `MockScheduleRepository` + 兴庆校区样例课程 | 办事大厅 / 一网通办课表接口（ehall / ywtb） |
| 教室 | 本地空闲教室列表 | ehall 教室查询 |
| 通知 | 本地教务通知 + 关键词/分类规则 | 教务处官方通知源 |
| 闹钟 | `AlarmPlanner` 计算建议时间；按钮只模拟创建 | `flutter_local_notifications` 真调度 |

状态管理统一使用 **Riverpod 3**，路由使用 **go_router 18**。

## 架构约定

- **feature-first**：每个功能包含 `domain` / `data` / `presentation`。
- **依赖方向**：UI → 仓库接口 → Mock（或未来的 CAS/ehall 适配器）。替换实现时只改 `lib/core/di/core_providers.dart`。
- **凭据**：`CredentialStore` 抽象 + `SecureCredentialStore`（`flutter_secure_storage`）。只保存学号与会话令牌；**密码不入库、不打日志**。插件不可用时回退到内存。
- **网络**：`ApiClient` 带校园域名白名单，骨架阶段不会发起登录请求。

闹钟规则（本地、可单测）：

- 起床：当天第一节课开始时间减去可配置提前量，默认 **90 分钟**。
- 上课提醒：每门课开课前 **30 / 15 分钟**。
- 「一键创建闹钟」目前写入调试日志并提示模拟成功，不调用系统闹钟。

## 下一步（真实校园服务）

1. **CAS**：用 WebView / 官方 SDK 打开 `https://login.xjtu.edu.cn`，由同学自己完成验证码与登录；应用只接收会话 Cookie / TGT。禁止代填密码、禁止验证码绕过。
2. **ehall / 一网通办**：在已登录会话下调用学校公开或授权接口获取课表、教室、日程。
3. **通知**：接入教务处官方信息源，再用 `NoticeFilterRule` 结合课表做个性化。
4. **闹钟**：初始化 `FlutterLocalNotificationsPlugin`、时区与通知权限后，把 `StubAlarmScheduler` 换成真实调度。
5. 不要实现抢课、爬虫或把凭据发到第三方。

## 安全

- 学校密码不得出现在日志、崩溃报告或明文配置中。
- 会话只放在设备本地加密存储。
- 本骨架不含后端；后续如需同步，应使用学校认可的接口，而不是抓取登录页。

## 应用标识

- 显示名：交大校园助手
- 包名：`xjtu_campus`（Android/iOS：`cn.edu.xjtu.xjtu_campus`）
