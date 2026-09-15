# 校园卡（ncard）实验功能 · v1.5.0-card.4

Read-only balance + recent turnover. No 充值 / 支付 / 挂失 automation.

## Endpoints

| Item | Value |
|------|--------|
| Host | `https://ncard.xjtu.edu.cn` |
| UI | `GET /plat/`（慧新 E 校 H5 SPA） |
| CAS entry | `GET /berserker-base/redirect?type=login&loginFrom=h5&synAccessSource=h5` |
| Card | `GET /berserker-app/ykt/tsm/queryCard?synAccessSource=h5` |
| Turnover | `GET /berserker-search/search/personal/turnover` |
| User (optional) | `GET /berserker-base/user?synAccessSource=h5` |
| OAuth | `POST /berserker-auth/oauth/token` |

Unauthenticated probe (2026-09-14, box `curl`, **no cookies**):

- `/` → 301 `/plat`
- `/plat/` → 200 H5 `index.html`（title empty; noscript: 慧新E校）
- `queryCard` → JSON `{"code":401,"message":"缺失令牌,鉴权失败"}`（HEAD 可能 404）
- `turnover` → 200 empty body without H5 headers

H5 APIs require **mobile UA**. Desktop Chrome / desktop WebView is rejected with dialog **「请浏览器调成移动端模式访问！」**.

## Mobile WebView requirement (card.4)

ncard H5 blocks non-mobile browsers. All ncard WebViews must use:

1. **iPhone Safari UA** (`CampusUrls.ncardMobileUserAgent` / `NcardMobileStealth.userAgent`)
2. `preferredContentMode: UserPreferredContentMode.MOBILE`
3. AT_DOCUMENT_START script spoofing `navigator.userAgent` / `vendor` / `maxTouchPoints=5` / `ontouchstart` / `matchMedia('(pointer:coarse)')`
4. On loadStop: auto-click 确认 if dialog text contains `移动端`

Dedicated sync route: **`/campus-card/sync`** → `NcardSyncPage` (full-screen mobile InAppWebView). Do **not** open ncard via generic `/browser` (desktop UA).

## Auth chain (CAS → ncard)

Soft-ref public [XJTUToolBox `app/sessions/campus_card_session.py`](https://github.com/yan-xiaoo/XJTUToolBox/blob/main/app/sessions/campus_card_session.py) + `card/campus_card.py`:

1. Existing CAS/ywtb session (TGC / 一网通办 Cookie).
2. Warm `/plat/` only (do **not** pre-hit the CAS redirect — that would consume the one-time `ticket=`).
3. Manual Dio redirect walk of `ncardCasRedirect` (`followRedirects: false`) captures `ticket=` on an ncard `Location` / URL; fallback also scans a followed-redirects response + `response.redirects`. Whole chain retries **twice**.
4. Exchange ticket at **`POST /berserker-auth/oauth/token`** (`grant_type=password`, `logintype=sso`, `loginFrom=h5`) using the **public** H5 platform OAuth client. Shared helper: `NcardSso` (repository + sync page + headless fetcher).
5. **Do not** soft-warm GET `/plat/auth/synjones/oauth?ticket=` — that path returns **401**; XJTUToolBox uses POST oauth/token only.
6. Persist `access_token` in secure storage (`ncard.access_token`); reuse on next load; clear and re-SSO on `queryCard` 401.
7. Subsequent APIs send `Synjones-Auth` **and** `synjones-auth: bearer <access>` plus `synAccessSource: h5`.
8. When WebView sees `ticket=` on ncard URL: prefer **Dart Dio oauth** via `NcardSso.oauthAndSave`, then optionally verify `queryCard`. Also poll sessionStorage as fallback.
9. HeadlessInAppWebView: same iPhone UA + MOBILE mode + mobile spoof; Dart oauth on ticket; auto-dismiss 移动端 dialog.

**Important:** plain CAS / ywtb / jwxt cookies alone are **not** enough → `401 缺失令牌`. The H5 JWT (`Synjones-Auth`) is required.

WebVPN: ncard is **not** rewritten (XJTUToolBox `supports_webvpn = False`). Off-campus users still need CAS cookies; if ncard is unreachable off-campus, the page shows error + retry (no silent demo while logged in).

This box had **no computerUse MCP** and cookies were **not** scraped from Chrome profiles (no secrets in this doc). Live 401 on unauth `queryCard` matches “needs login”.

## JSON fields used (no PII logged)

From XJTUToolBox `queryCard` first `data.card[]`:

- `elec_accamt` / `unsettle_amount` — integer **cents**
- `barflag` / `freezeflag` — 1 = 挂失 / 冻结
- `expdate` — `YYYYMMDD` → `YYYY-MM-DD`
- `cardname` — card type label

Turnover `data.records[]`:

- `tranamt`, `cardBalance` — cents
- `jndatetimeStr`, `turnoverType`, `toMerchant` / `resume`, `icon`
- Sign: income markers (充值/圈存/退款/补助) first, then expense (消费/扣款). 「消费退款」 stays positive.

Success business code: `code == 200`.

## App behaviour

- Route `/campus-card`. Home dashboard shortcut + 快捷入口 (not About sheet).
- Not logged in → mock, gold banner.
- Logged in + live OK → cache via `SnapshotCache.campusCard` (stale-while-revalidate).
- Logged in + API fail → error + **重试** + **打开校园卡登录同步** → pushes **`/campus-card/sync`** (mobile WebView). Pop with success (`true`) auto-reloads. **Does not** silently replace with fake balance.
- User instructions: 打开校园卡登录同步 → 若仍有弹窗点确认 → 自动返回后重试。
- Read-only. Logs only: ticket found yes/no, oauth ok yes/no, queryCard code. Do **not** log balance rows, tickets, or bearer values.

## Troubleshooting

| Symptom | Likely cause | What to try |
|---------|--------------|-------------|
| Dialog「请浏览器调成移动端模式访问！」 | Desktop UA / missing mobile spoof | Update to card.4+; use **打开校园卡登录同步** (mobile sync page). If dialog still shows, tap 确认. |
| Banner: 校园卡接口未同步成功 / `缺失令牌` | No H5 JWT; CAS Cookie alone insufficient | Tap **打开校园卡登录同步**, wait until status shows success / auto-return, then retry. Or full 网页登录 again. |
| Works once then 401 | Stored bearer expired / kicked | App clears `ncard.access_token` on 401 and re-SSO; if still failing, open sync page. |
| Off-campus + VPN still fails | ncard may be campus-net only; WebVPN not used for ncard | Try on campus Wi‑Fi / 校园网; VPN ≠ WebVPN cookie path. |
| Dio path never gets ticket | Redirects consumed ticket into `/plat/` without query | Fixed in card.3 via manual redirect walk; card.4 also does Dart oauth from WebView ticket URL. |
| soft-warm `/plat/auth/synjones/oauth?ticket=` → 401 | Wrong oauth path (SPA soft-warm) | card.4 skips that GET; uses POST `/berserker-auth/oauth/token` only. |
| Headless WebView empty / `_waitForToken timed out` | Mobile dialog blocked SPA; or fetched before token | card.4: iPhone UA + dismiss dialog + Dart oauth on ticket. |

## Limitations

- First-time ncard SSO may need **打开校园卡登录同步** or 网页登录 so mobile WebView can complete H5 oauth.
- Turnover is last **90 days**, first page (30). Not a full bill export.
- No payment, QR, recharge, or 挂失.
- Pre-release only: UpdateChecker `/releases/latest` ignores this tag; stable stays on 1.4.0 until a non-pre release.
