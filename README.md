# 交大校园助手（xjtu_campus）

面向西安交通大学在校学生的跨平台校园助手。用自己的学号登录学校统一认证后，可读取课表与成绩、查询考试安排与空闲教室、查看校历教学周与校园卡余额/流水，并按课表在本机创建起床闹钟与上课提醒。

产品语言为简体中文。仅支持**学生本人**登录自己的账号，用于个人课表 / 教室 / 通知；不提供抢课、验证码识别、绕过二次验证或把密码上传到第三方。

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

## 登录

1. 打开「去登录」。
2. **统一认证登录**：把学号和密码提交到 [`https://login.xjtu.edu.cn/cas/login`](https://login.xjtu.edu.cn/cas/login)。密码在本机用学校公钥做 RSA（PKCS#1 v1.5，`__RSA__` 前缀）后提交，**不会写入本地文件，也不会打进日志**。
3. 若学校要求图形验证码，应用会显示验证码图片，由你自己填写。应用**不会**自动识别或绕过验证码。
4. 若账号开启短信二次验证 / Safety Verify，应用会调用学校官方短信接口，把验证码发到你绑定的手机。请按学校流程完成，应用**不会**绕过 MFA。
5. 若账号有本科 / 研究生等多个身份，请在应用内选择本次使用的身份。
6. **演示登录（不联网）**：任意学号即可浏览界面，数据为本地样例。

会话 Cookie 与学号保存在 `flutter_secure_storage`（系统安全存储）。退出登录会清除本机会话。

## 课表与空闲教室

登录成功后，应用会用 CAS 会话单点登录：

| 功能 | 实际接口 | 回退 |
| --- | --- | --- |
| 课表 | 优先 `jwxt.xjtu.edu.cn` 的 `wdkb`（我的课表），失败再试 `ehall.xjtu.edu.cn` 同路径 | 演示课表，顶部标明「演示数据」 |
| 空闲教室 | 教务 `kxjas` / `cxkxjs.do`（师生服务大厅 ywtb 登录后获得身份，查询仍走教务） | 演示教室列表 |

未登录、会话失效、校外访问失败时，页面顶部会显示金色横幅；实时数据为绿色横幅。

实时空闲教室在未选楼宇时默认查询 **兴庆校区 · 主楼A**（教务接口需要楼宇代码）。请在筛选里改成你所在的楼。

## 成绩 / 考试 / 校历

- **成绩**：教务 `jwxt` · `cjcx/xscjcx.do`（登录后只读本人成绩）。
- **考试安排**：`studentWdksapApp/wdksap.do`；本学期无数据时显示「本学期暂无考试安排」。
- **校历**：登录后优先教务学期起止；公开站 `one2020` 作补充；教学周与课表同步。
- **加权绩点**：成绩页按学分加权 `Σ(绩点×学分)/Σ(学分)`，支持学期筛选。
- **校园卡**（实验）：`ncard.xjtu.edu.cn` 余额 + 近 90 天流水（只读）。未登录为演示；已登录失败则报错重试，不静默用假余额。详见 `docs/ncard-campus-card.md`。

入口：首页「学业」「校历」「校园卡」卡片。路由：`/academics`、`/grades`、`/exams`、`/calendar`、`/campus-card`。

## 本地缓存（stale-while-revalidate）

冷启动优先展示**上次成功的实时数据**（课表 / 成绩 / 考试 / 通知 / 校历 / 空闲教室 / 校园卡上次查询），再在后台刷新。仅缓存 `live == true` 的快照，演示数据不会当作真数据写入。顶部横幅会标注「缓存」及「更新于 M月d日 HH:mm」；刷新成功可显示「刚刚更新」。关于页可「清除缓存」（不影响登录会话）。


## 闹钟（本地通知）

- **起床闹钟**：当天第一节课开始时间减去可配置提前量，默认 **90 分钟**。
- **上课提醒**：每门课开课前 **30 / 15 分钟**。
- **一键创建闹钟**：按当前周次，为**今天起 7 天内仍未开始**的课程写入本机通知，时区 **Asia/Shanghai**。会先取消上一批再重建。
- **取消已创建的提醒**：清除本机已预约通知。
- **立即发送测试通知**：用于确认当前设备已授予通知权限。

### 平台权限

**Android**（见 `android/app/src/main/AndroidManifest.xml`）：

- `POST_NOTIFICATIONS`（Android 13+ 运行时申请）
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`
- `RECEIVE_BOOT_COMPLETED`（重启后恢复已预约通知）
- `VIBRATE`、`WAKE_LOCK`

**iOS**：首次创建闹钟时请求通知权限。请在系统设置中允许通知。

**Web / 部分桌面**：浏览器通常无法可靠预约未来通知。请在 Android 或 iOS 客户端使用一键闹钟。Web 预览仍可浏览课表与登录界面。

## WebVPN（校外）

CAS 登录的 service 必须用一网通办/ehall（已注册）；不要用 jwxt home，否则会报 missing service。

登录页可打开「校外使用 WebVPN」。开启后，课表 / 教室请求会改写到 `webvpn.xjtu.edu.cn`（AES-CFB 默认密钥）。请先完成统一认证；WebVPN 若另需滑块/短信，请在学校网页完成后再回应用。

## 教务通知

通知页会抓取教务处公开「教学通知」列表（`dean.xjtu.edu.cn`），按标题自动归类，并支持点开原文。失败时回退演示数据。

## 学校门户限制（请先阅读）

- **校园网 / WebVPN**：jwxt、ehall、一网通办在校外常需 [WebVPN](https://webvpn.xjtu.edu.cn)。可在登录页开启 WebVPN；未开启或 WebVPN 失败时回退演示数据。
- **MFA**：只走学校官方短信验证。无法代收验证码，也不会跳过安全验证页。
- **验证码**：必须由使用者看图输入。
- **研究生课表**：本科走 jwxt `xskcb`；研究生培养系统（gmis 等）未接入，失败时显示演示数据。
- **不要**在不受信任的设备上保存会话。本应用没有服务端密码库，也不会把多位同学的密码存成明文。

## 安全约定

禁止实现或接入：抢课脚本、验证码自动识别、MFA 绕过、凭据外传、未授权批量抓取。

密码、CAS Ticket、TGC、验证码字符串不得进入日志。`AppLogger` 会拦截疑似凭据字段。

## 模块地图

```
lib/
  core/           主题、路由、安全存储、校园会话、RSA、中文文案
  features/
    auth/         CAS 登录 + AuthRepository；Mock 仅用于演示
    schedule/     课表模型 / jwxt·ehall 适配器 / 列表与周视图
    classroom/    空闲教室筛选与教务 kxjas 适配器
    notifications/教务通知列表与本地过滤规则（仍为本地样例）
    alarms/       起床/课前提醒计算 + flutter_local_notifications
    home/         底部导航壳与首页
    campus_card/  校园卡余额与流水（ncard，只读）
```

状态管理使用 **Riverpod 3**，路由使用 **go_router 18**。替换数据源时改 `lib/core/di/core_providers.dart`。默认仓库为 CAS / 实时适配器；`login(demo: true)` 仍走 Mock。

## 应用标识

- 显示名：交大校园助手
- 包名：`xjtu_campus`（Android/iOS：`cn.edu.xjtu.xjtu_campus`）
