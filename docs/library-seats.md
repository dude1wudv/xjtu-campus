# 图书馆座位预约 API（实验文档）

> 探测环境：公网无法直连 `rg.lib.xjtu.edu.cn:8086`（超时）。下列形状来自公开参考实现
> （[xjtu-wang/XJTU-Toolbox](https://github.com/xjtu-wang/XJTU-Toolbox) `getchair_request.py`、
> [gwyxjtu/xjtu_lib_bot](https://github.com/gwyxjtu/xjtu_lib_bot)）与历史校园网抓包笔记。
> **不含任何账号 / Cookie / 密钥。** 仅供本人合法使用；请遵守图书馆规定。

## 主机与网络

| 项 | 值 |
| --- | --- |
| 主入口（现行） | `http://rg.lib.xjtu.edu.cn:8086` |
| 历史入口 | `http://rg.lib.xjtu.edu.cn:8010`（旧脚本） |
| 可达性 | **校园网**（宿舍 / STU Wi‑Fi / 有线）；公网通常超时 |
| 认证 | OpenPlatform / 图书馆站点 Cookie；从 `http://www.lib.xjtu.edu.cn/` 登录后跳转 |

应用内若连接失败，应提示「需校园网」而非当作业务错误。

## 端点一览

### 1. 查询区域座位状态

```
GET /qseat?sp={areaCode}
```

- 示例：`/qseat?sp=west3B`、`/qseat?sp=east3A`、`/qseat?sp=south3middle`
- 响应 JSON（示意，无密钥）：

```json
{
  "seat": { "Y002": 0, "Y003": 1, "X115": 0 },
  "scount": 120
}
```

- `seat[kid]`：`0` = 空闲，`1` = 占用（历史约定；若字段变更以实机为准）
- `sp`：区域代码（见下表）

旧端口 `8010` 同路径；现行客户端优先打 `8086`，失败时可提示用户确认网络。

### 2. 浏览区域座位页（HTML）

```
GET /seat/?sp={areaCode}
```

用于浏览器查看座位图；脚本侧更常直接用 `/qseat`。

### 3. 预约指定座位

```
GET /seat/?kid={seatId}&sp={areaCode}
```

- 示例：`http://rg.lib.xjtu.edu.cn:8086/seat/?kid=Y002&sp=west3B`
- 需携带有效会话 Cookie
- **成功判定（Toolbox）**：跟随重定向后最终 URL 含 `/seat/my/`
- **失败**：仍停在预约页或错误页；勿无限重试

本应用：仅在用户**显式确认**或**用户配置的定时任务**触发时发送预约请求。

### 4. 我的预约

```
GET /seat/my/
GET /my/          # 旧版页面
```

返回 HTML；可解析当前座位号与状态（已预约 / 已取消 / 已离馆 / 超时未入馆等）。

### 5. 取消预约

公开脚本未统一 JSON API。常见做法：

- 在「我的预约」页点击取消（HTML 表单 / 链接）
- 或探测形如 `GET/POST /seat/cancel?...` / `/cancel/?id=...`（**需在校园网实机确认**）

实现侧：先打开 `/seat/my/`，解析取消链接；解析失败则引导用户浏览器操作，并显示清晰错误。

### 6. 入馆（ruguan，旧流程）

```
GET  /ruguan
POST /ruguan   # csrf_token + service=seat + rplace=east|west ...
```

部分旧预约链在抢座前需先「入关」。现行 8086 流程可能已简化；客户端按需探测，失败不阻塞「我的预约」查询。

## 区域代码（兴庆图书馆常见）

| 显示名 | `sp` |
| --- | --- |
| 北楼二层外文库（东） | `north2east` |
| 北楼二层外文库（西） | `north2west` |
| 二层连廊及流通大厅 | `north2elian` |
| 南楼二层大厅 | `south2` |
| 北楼三层 ILibrary-A（东） | `east3A` |
| 北楼三层 ILibrary-B（西） | `west3B` |
| 大屏辅学空间 | `eastnorthda` |
| 南楼三层中段 | `south3middle` / `south3middlen` |
| 北楼四层西侧 | `north4west` |
| 北楼四层中间 | `north4middle` |
| 北楼四层东侧 | `north4east` |
| 北楼四层西南侧 | `north4southwest` |
| 北楼四层东南侧 | `north4southeast` |

座位号前缀与区域的启发式映射见应用内 `library_seat_areas.dart`（与 Toolbox 一致，可被用户覆盖）。

## 定时预约与回退策略（本应用）

1. 用户设置：偏好座位 `kid` + 区域 `sp` + 开始时间 + 回退区域范围 + 最大尝试次数 `N`（默认有限，如 8）
2. 到点：本地通知提醒；若应用在前台 / 用户点进通知后，执行预约 runner
3. Runner：
   - 先约偏好座位
   - 若失败：在配置区域内查询空座，按 ≥1–2s 间隔尝试，**最多 N 次**
   - 成功或次数耗尽即停止（**禁止无限循环**）
4. 公平使用文案：`仅预约本人使用，勿滥用`

## 参考

- https://github.com/xjtu-wang/XJTU-Toolbox （`getchair_request.py`）
- https://github.com/gwyxjtu/xjtu_lib_bot （历史 8010）
- `auth-xjtu` 文档示例 dest：`http://rg.lib.xjtu.edu.cn:8086`
