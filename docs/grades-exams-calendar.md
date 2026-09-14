# Grades · Exams · Calendar (v1.3.1)

Read-only student features. No抢课. Do **not** log full grade/exam rows (may contain student id).

## 成绩查询（jwxt cjcx）

| Item | Value |
|------|--------|
| UI | `/jwapp/sys/cjcx/*default/index.do#/cjcx` |
| API | `POST https://jwxt.xjtu.edu.cn/jwapp/sys/cjcx/modules/cjcx/xscjcx.do` |
| Auth | Same jwxt session as empty classrooms (CAS → org OAuth). WebView cookie jar preferred; Dio soft-warm fallback. |
| Fields used | `XNXQDM`, `KCM`, `XF`, `XFJD`, `ZCJ`, `PSCJ`/`QMCJ`/`QZCJ`, `KSLXDM_DISPLAY`, `KCXZDM_DISPLAY`, `KCH` |
| App routes | `/grades` (also via `/academics`) |
| Fixture | `docs/grades-sample-redacted.json` (`XH` redacted) |
| GPA | 绩点加权平均 `Σ(XFJD×XF)/Σ(XF)`；学期 FilterChip + 全部 |

## 考试安排（jwxt wdksap）

| Item | Value |
|------|--------|
| UI | `/jwapp/sys/studentWdksapApp/*default/index.do` |
| API | `POST .../modules/wdksap/wdksap.do` body `XNXQDM=<term>&*order=-KSRQ,-KSSJMS` |
| Term | `POST .../wdkb/modules/jshkcb/dqxnxq.do` → `datas.dqxnxq.rows[0].DM` |
| Fields used | `KCM`, `KSRQ`, `KSSJMS`, `JASMC`, `XXXQMC`, `XNXQDM`, `KCH`, `ZWH` |
| Empty copy | 「本学期暂无考试安排」；`code=0` + 空 rows = 实时成功，不回落演示假考试 |
| Fetch | 对齐成绩：WebView Cookie → soft-warm（home / wdkb / wdksap）→ Dio |
| App routes | `/exams` |
| Fixture | `docs/exams-sample-redacted.json` |

## 校历 / 教学周（one2020 public）

Prefer public one2020 over ywtb `portal-api` (JWT/`没有访问权限01`).

| Item | Value |
|------|--------|
| Page | `http://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/showCalendar.htm` |
| Terms | `POST .../EIP/schoolcalendar/terms.htm` → `{code:200,data:[{id,term_num,start_date,end_date,...}]}` |
| Detail | `POST .../queryTermById.htm` body `id=` → term + `holidays[]` |
| Primary | When logged in: jwxt `dqxnxq` + `cxjcs` term start (no fake 国庆/期末 demos) |
| Fallback | one2020 HTTP/HTTPS + showCalendar scrape; if terms `data:[]`, use schedule week as live; demo sample only when fully offline |
| Week sync | Calendar uses schedule snapshot week when available (home ClassPeriod week) |
| App routes | `/calendar` |
| Fixtures | `docs/one2020-terms-sample.json`, `docs/one2020-term-detail-sample.json` |

## Deferred: 校园卡（ncard）

**Not implemented in this sprint.** Host `ncard.xjtu.edu.cn` needs a separate CAS → berserker auth chain (`/plat`, `queryCard`, turnover). See `docs/api-probe-candidates.md` §4. TODO markers live in `CampusUrls.ncardPlat` and the academics hub note.

## Navigation

Bottom tabs unchanged (5). Entry points: home dashboard cards + quick actions + about sheet → `/academics` hub → `/grades` `/exams` `/calendar`.
