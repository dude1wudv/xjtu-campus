# XJTU campus API probe candidates

Probe date: 2026-09-14  
Method: box Chrome CDP (existing ywtb/jwxt sessions) + public `curl` HEAD/GET + open-source path hypotheses (XJTUToolBox).  
Scope: **read-only** discovery only. No抢课, no captcha bypass, no secret dumps.

Session note: Browser tabs were **logged in** for `ywtb.xjtu.edu.cn` (应用中心) and `jwxt.xjtu.edu.cn` (教学管理系统 / 成绩模块). Some ywtb `portal-api` calls returned `没有访问权限01` (likely missing JWT/`Authorization` header beyond cookie). If parent re-login is needed later, do **not** put passwords in this doc.

---

## Already shipped

| Feature | Host / path | Notes |
|--------|-------------|--------|
| CAS / ywtb login | `login.xjtu.edu.cn` + `ywtb.xjtu.edu.cn` | `CampusUrls` CAS + MFA; `authx-service` user |
| Undergraduate kebiao | `workflow.xjtu.edu.cn/selectpage/site/newkebiao/getUndergraduateKebiao` | Also jwxt `wdkb` paths reserved |
| Empty classrooms | `jwxt.../kxjas/modules/kxjscx/cxkxjs.do` + campus/building codes | Live JSON samples in `docs/` |
| Dean notices | `dean.xjtu.edu.cn/jxxx/jxtz2.htm` (+ `due.xjtu.edu.cn`) | Public HTML (challenge/stealth) |
| Local alarms | on-device | Not a campus API |

---

## Public host reachability (unauthenticated curl)

| Host | Result | Notes |
|------|--------|--------|
| `ywtb.xjtu.edu.cn` | 200 | Main + `#/Index` |
| `ehall.xjtu.edu.cn` | 301 → `/new/index.html` | Still up; many jwapp apps migrated to jwxt |
| `jwxt.xjtu.edu.cn` | 302 → homeapp / CAS-OAuth | App modules need org OAuth (`org.xjtu.edu.cn`, appId `1675`) |
| `workflow.xjtu.edu.cn` | 302 → `/fe/` | Kebiao page 200 |
| `login.xjtu.edu.cn/cas/login` | 200 | |
| `dean.xjtu.edu.cn/jxxx/jxtz2.htm` | 200 | Root `/` may 403 |
| `due.xjtu.edu.cn/jxxx/jxtz2.htm` | 200 | |
| `webvpn.xjtu.edu.cn` | 302 → `/login` | |
| `authx-service.xjtu.edu.cn` | 200; `/personal/.../me/user` → 403 | Needs CAS/ywtb session |
| `gmis.xjtu.edu.cn` | 200; pyxx paths → 403 | Grad system |
| `xkfw.xjtu.edu.cn` | 301 → `xsxkapp` index; then CAS | Course selection platform |
| `jwapp.xjtu.edu.cn` | 302 → org OAuth (appId `1370`) | Mobile jwapp |
| `ncard.xjtu.edu.cn` | 301 → `/plat` | Campus card |
| `www.lib.xjtu.edu.cn` | 200 | Library portal |
| `rg.lib.xjtu.edu.cn:8086` | timeout from box | Seat system; often campus-net only |
| `one2020.xjtu.edu.cn` calendar | 200 | Public校历 HTML + `terms.htm` |
| `lms.xjtu.edu.cn` | redirects toward Keycloak/CAS broker | 思源学堂 |
| `bkkq.xjtu.edu.cn` / `yjskq.xjtu.edu.cn` | TLS/timeout from box | Attendance; likely WebVPN/campus |
| `energy.xjtu.edu.cn` | 200 but **not** 电费 | Title: 能源动力类专业教学指导委员会 |
| `card.xjtu.edu.cn` / `lib.xjtu.edu.cn` (bare) | DNS fail | Prefer `ncard` / `www.lib` |

---

## Candidates

### 1. 成绩查询（本科）

- **Host / likely path:** `jwxt.xjtu.edu.cn` · `POST /jwapp/sys/cjcx/modules/cjcx/xscjcx.do` · UI ` /jwapp/sys/cjcx/*default/index.do#/cjcx`
- **Auth needed:** jwxt session (CAS → org OAuth appId 1675)
- **Probe status:** **reachable-logged-in** — live JSON `code=0`, `datas.xscjcx.totalSize=60`
- **Value for app:** high
- **Integration difficulty:** easy (same cookie jar as empty-classroom / homeapp)
- **Notes:** Fields seen (keys only): `XNXQDM`, `KCM`, `XF`, `XFJD`, `ZCJ`, `PSCJ`/`QMCJ`/`QZCJ` + weights, `KSLXDM_DISPLAY`, `KCXZDM_DISPLAY`, `KKDWDM`, … Soft-ref: FineReport transcript ` /jwapp/sys/frReport2/show.do?reportlet=bkdsglxjtu/XAJTDX_BDS_CJ.cpt` (index 404; may need different entry). ywtb tile「电子成绩单/在读证明」is a separate service entry.

### 2. 考试安排（我的考试）

- **Host / likely path:** `jwxt.xjtu.edu.cn` · `POST /jwapp/sys/studentWdksapApp/modules/wdksap/wdksap.do` · app index ` /jwapp/sys/studentWdksapApp/*default/index.do`
- **Auth needed:** jwxt session
- **Probe status:** **reachable-logged-in** — `code=0` with `datas.wdksap.rows=[]` for current term `2026-2027-1` (no exams published yet; API healthy)
- **Value for app:** high
- **Integration difficulty:** easy
- **Notes:** Body: `XNXQDM=<term>&*order=-KSRQ,-KSSJMS`. Term from existing `dqxnxq.do`. Home UI label「我的考试安排」. Do **not** use guessed `kwglstu` (404).

### 3. 校历 / 教学周

- **Host / likely path:**
  - Public: `http://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/showCalendar.htm` + `POST/GET .../EIP/schoolcalendar/terms.htm`
  - YWTB: `GET https://ywtb.xjtu.edu.cn/portal-api/v1/calendar/share/schedule/getWeekOfTeaching`
- **Auth needed:** public (one2020 HTML) / CAS session + proper portal token (ywtb)
- **Probe status:** **public** (one2020 200) · ywtb calendar API **needs-login** / token (`没有访问权限01` with cookie-only fetch)
- **Value for app:** med–high (week number,学期起止)
- **Integration difficulty:** med (HTML scrape vs portal JWT)
- **Notes:** ywtb nav「日程」→ `#/ScheduleCenter`. jwxt home already shows「学习日程 第1周」via homeapp (term week UI).

### 4. 校园卡（余额 / 流水）

- **Host / likely path:** `ncard.xjtu.edu.cn` · `/berserker-app/ykt/tsm/queryCard?synAccessSource=h5` · turnover `/berserker-search/search/personal/turnover` · UI `/plat`
- **Auth needed:** CAS session to ncard (separate from jwxt)
- **Probe status:** **needs-login** — host reachable (301→`/plat`); unauth API 404/500
- **Value for app:** high
- **Integration difficulty:** med (new host + berserker auth chain)
- **Notes:** Soft-ref XJTUToolBox `card/campus_card.py`. ywtb footer shows 校园卡中心 contacts only (no tile in teaching category).

### 5. 图书馆座位 / 预约状态（只读）

- **Host / likely path:** `http://rg.lib.xjtu.edu.cn:8086` · `GET /qseat?sp=...`, `/my/` · portal tiles「图书馆」「图书预约」on ywtb
- **Auth needed:** library session (often campus net); portal may deep-link
- **Probe status:** **unknown** from this box (TCP timeout to `:8086`); `www.lib.xjtu.edu.cn` **public** 200
- **Value for app:** med (seat status / my booking read-only)
- **Integration difficulty:** hard off-campus (WebVPN or campus network); med on-campus
- **Notes:** Soft-ref XJTUToolBox `library/seats.py`. **No** booking automation in app scope for this probe.

### 6. 选课结果 / 选课平台（只读）

- **Host / likely path:** `xkfw.xjtu.edu.cn/xsxkapp/sys/xsxkapp/*default/index.do` · jwxt home tiles「学生选课」
- **Auth needed:** CAS (`login` service → xkfw)
- **Probe status:** **needs-login** — host responds; unauth → CAS 302
- **Value for app:** med (show已选课程; **not** 抢课)
- **Integration difficulty:** med–hard (xsxkapp EMAP; separate product)
- **Notes:** Constraint: read-only listing only. Legacy guess `jwxt.../xsxk` returns 404.

### 7. 学籍信息

- **Host / likely path:** `jwxt.xjtu.edu.cn/jwapp/sys/xjxxgl/*default/index.do` (+ module `.do` TBD)
- **Auth needed:** jwxt session
- **Probe status:** **reachable-logged-in** (index HTML loads under session); data API path not fully mapped (`xjxxcx.do` → 403 without proper module context)
- **Value for app:** med
- **Integration difficulty:** med
- **Notes:** Capture Network while opening「查询服务」→学籍 in a follow-up logged-in pass.

### 8. 培养方案

- **Host / likely path:** `jwxt.xjtu.edu.cn/jwapp/sys/pyfagl/*default/index.do` · homeapp umi also references `pyfa/list`
- **Auth needed:** jwxt session
- **Probe status:** **reachable-logged-in** (index loads)
- **Value for app:** med
- **Integration difficulty:** med
- **Notes:** Useful for degree progress / required courses later.

### 9. 研究生课表 / 成绩（GMIS）

- **Host / likely path:** `gmis.xjtu.edu.cn` · `/pyxx/pygl/xskbcx` · `/pyxx/pygl/xscjcx/index`
- **Auth needed:** CAS → gmis
- **Probe status:** **needs-login** (host 200; pyxx 403 unauth)
- **Value for app:** high for grad users / low for undergrad-only
- **Integration difficulty:** med (HTML-oriented APIs in OSS)
- **Notes:** Soft-ref XJTUToolBox `gmis/`. Undergrad jwxt does **not** replace gmis for grads.

### 10. 思源学堂（LMS 作业 / 课程）

- **Host / likely path:** `lms.xjtu.edu.cn` · RMS `rms-v5.xjtu.edu.cn` · ywtb tile「思源学堂2.0」
- **Auth needed:** CAS / Keycloak broker
- **Probe status:** **needs-login**
- **Value for app:** med–high (todos / deadlines)
- **Integration difficulty:** hard
- **Notes:** Soft-ref XJTUToolBox `lms/lms.py`. Good long-term「待办」source.

### 11. 考勤（本科 / 研究生）

- **Host / likely path:** `bkkq.xjtu.edu.cn` / `yjskq.xjtu.edu.cn` · `/attendance-student/...`
- **Auth needed:** CAS (+ often campus/WebVPN)
- **Probe status:** **unknown** / not reachable from this egress (timeout/TLS)
- **Value for app:** med
- **Integration difficulty:** hard off-campus
- **Notes:** Soft-ref XJTUToolBox `attendance/`. Retry via WebVPN session.

### 12. ywtb 办事 / 消息 / 日程（待办入口）

- **Host / likely path:** `ywtb.xjtu.edu.cn/main.html#/ServiceCenter` · `#/ScheduleCenter` · `portal-api/v1/config/getDetail` (works) · calendar/todo endpoints TBD
- **Auth needed:** CAS / ywtb JWT
- **Probe status:** **reachable-logged-in** for UI app list; many `portal-api` data calls **needs-login** (token)
- **Value for app:** med (discovery + deep links)
- **Integration difficulty:** med
- **Notes:** Visible teaching apps include 图书预约、图书馆、本科教务系统、本科生评教、电子成绩单/在读证明、课程教材门户、网络信息服务缴费、思源学堂2.0.「电费」not seen as a tile; `energy.xjtu.edu.cn` is unrelated.

### 13. 移动教务成绩（jwapp）

- **Host / likely path:** `jwapp.xjtu.edu.cn` · `POST /api/biz/v410/score/termScore` (+ `scoreDetail`, `scoreAnalyze`, `common/school/time`)
- **Auth needed:** org OAuth appId `1370`
- **Probe status:** **needs-login**
- **Value for app:** low–med if jwxt cjcx already works
- **Integration difficulty:** med
- **Notes:** Soft-ref XJTUToolBox `jwapp/score.py`. Prefer jwxt `cjcx` for undergrad.

---

## Recommended next 3 picks

1. **成绩查询 (`cjcx` / `xscjcx.do`)** — already returns live JSON under current jwxt session; highest user value; reuse existing session client.
2. **考试安排 (`studentWdksapApp` / `wdksap.do`)** — same auth surface; API confirmed (`code=0`); wire UI now, populate when rows appear.
3. **校园卡 (`ncard.xjtu.edu.cn`)** **or** **校历 (`one2020` public / ywtb calendar with JWT)** — card is high value but new auth host; calendar is easier public fallback for week/term chrome.

Honorable mention: library seat **read-only** once on campus/WebVPN; LMS for todos after jwxt grades/exams ship.

---

## ywtb UI app inventory (logged-in `#/ServiceCenter`)

Teaching / related tiles observed: 思源学堂2.0, 图书预约, 图书馆, 大创项目, 学信网, 思源学习空间, **本科教务系统**, 本科毕业设计管理系统, 本科生评教, 本科直录播平台, **电子成绩单/在读证明**, 科技查询与查收查引, 网络数据库导航, 课程教材门户; also 网上报销, 后勤服务, 校医院, 西交报修, 进出校报备, 校园网络自助平台, **网络信息服务缴费**.

## jwxt home tiles (logged-in)

Tabs: **我的课表**, **我的成绩**, **我的考试安排**, **我的课程**. Shortcuts: 学生注册, 转专业申请, 辅修报名, 学生评教, 社考报名, 补考报名, 缓考申请, **学生选课**. iframe for schedule: ` /jwapp/sys/wdkb/*default/index.do?min=1#/xskcb`.

---

## Safety / follow-ups

- Redacted: no cookies, tokens, passwords, or full grade rows in this file.
- Parent may need to refresh ywtb JWT for `portal-api` calendar; jwxt session was valid for cjcx + wdksap at probe time.
- Next engineering step: add `CampusUrls` for `cjcx` + `studentWdksapApp` and map DTO fields from `xscjcx` / `wdksap` without logging PII.

---

## Implementation status (2026-09-14 sprint)

Shipped in app **v1.3.0**: grades (`cjcx`), exams (`wdksap`), calendar (one2020 public + jwxt week fallback). See `docs/grades-exams-calendar.md`.

**Shipped in stable v1.5.0 (Latest / `main`):** 校园卡 (`ncard`) + 图书馆座位 — see `docs/ncard-campus-card.md`, `docs/library-seats.md`, `docs/RELEASE-NOTES.md`.
