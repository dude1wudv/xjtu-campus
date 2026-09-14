# Grades · Exams · Calendar (v1.3.0)

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

## 考试安排（jwxt wdksap）

| Item | Value |
|------|--------|
| UI | `/jwapp/sys/studentWdksapApp/*default/index.do` |
| API | `POST .../modules/wdksap/wdksap.do` body `XNXQDM=<term>&*order=-KSRQ,-KSSJMS` |
| Term | `POST .../wdkb/modules/jshkcb/dqxnxq.do` → `datas.dqxnxq.rows[0].DM` |
| Fields used | `KCM`, `KSRQ`, `KSSJMS`, `JASMC`, `XXXQMC`, `XNXQDM`, `KCH`, `ZWH` |
| Empty copy | 「本学期暂无考试安排」 |
| App routes | `/exams` |
| Fixture | `docs/exams-sample-redacted.json` |

## 校历 / 教学周（one2020 public）

Prefer public one2020 over ywtb `portal-api` (JWT/`没有访问权限01`).

| Item | Value |
|------|--------|
| Page | `http://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/showCalendar.htm` |
| Terms | `POST .../EIP/schoolcalendar/terms.htm` → `{code:200,data:[{id,term_num,start_date,end_date,...}]}` |
| Detail | `POST .../queryTermById.htm` body `id=` → term + `holidays[]` |
| Fallback | If terms empty: jwxt `dqxnxq` + `cxjcs` term start → teaching week; else bundled sample |
| Week sync | Calendar uses schedule snapshot week when available (home ClassPeriod week) |
| App routes | `/calendar` |
| Fixtures | `docs/one2020-terms-sample.json`, `docs/one2020-term-detail-sample.json` |

## Deferred: 校园卡（ncard）

**Not implemented in this sprint.** Host `ncard.xjtu.edu.cn` needs a separate CAS → berserker auth chain (`/plat`, `queryCard`, turnover). See `docs/api-probe-candidates.md` §4. TODO markers live in `CampusUrls.ncardPlat` and the academics hub note.

## Navigation

Bottom tabs unchanged (5). Entry points: home dashboard cards + quick actions + about sheet → `/academics` hub → `/grades` `/exams` `/calendar`.
