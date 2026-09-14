# 校园卡（ncard）实验功能 · v1.5.0-card.1

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

H5 APIs require **mobile UA**. Desktop Chrome is often rejected (XJTUToolBox `MOBILE_BROWSER_UA`).

## Auth chain (CAS → ncard)

Soft-ref public [XJTUToolBox `app/sessions/campus_card_session.py`](https://github.com/yan-xiaoo/XJTUToolBox/blob/main/app/sessions/campus_card_session.py) + `card/campus_card.py`:

1. Existing CAS/ywtb session (TGC / 一网通办 Cookie).
2. Warm `/plat/` and CAS redirect URL (WebView login sync also loads this after jwxt).
3. CAS returns to ncard with `ticket=` on the URL.
4. H5 SPA (or Dio fallback) exchanges ticket at `/berserker-auth/oauth/token` (`grant_type=password`, `logintype=sso`, `loginFrom=h5`) using the **public** H5 platform OAuth client (same Basic client as the official SPA / XJTUToolBox; not a user secret).
5. Subsequent APIs send `Synjones-Auth: bearer <access>` and `synAccessSource: h5`.
6. Token is also stored by the SPA in `sessionStorage.access_token`; HeadlessInAppWebView fetch reads it and calls the two GET APIs with `credentials: include`.

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
- Logged in + API fail → error + retry; optional clearly labelled 界面演示. **Does not** silently replace with fake balance.
- Read-only. Do not log balance rows, tickets, or bearer values.

## Limitations

- First-time ncard SSO may need **网页登录** so WebView can warm `/plat` (same as jwxt/workflow).
- Turnover is last **90 days**, first page (30). Not a full bill export.
- No payment, QR, recharge, or 挂失.
- Pre-release only: UpdateChecker `/releases/latest` ignores this tag; stable stays on 1.4.0 until a non-pre release.
