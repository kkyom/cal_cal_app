const functions = require("firebase-functions/v1");
const axios = require("axios");
const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  AppStoreServerAPIClient,
  SignedDataVerifier,
  Environment,
} = require("@apple/app-store-server-library");
const {
  RAW_FOOD_OVERRIDES,
  RAW_VARIANT_SYNONYMS,
} = require("./raw-food-overrides");
const { brandDisplayNameOf } = require("./brand-overrides");

if (!admin.apps.length) {
  admin.initializeApp();
}

const BASE_URL =
  "https://apis.data.go.kr/1471000/FoodNtrCpntDbInfo02/getFoodNtrCpntDbInq02";

// --- 검색 결과 캐시 ---
// 1) 인스턴스 메모리 → 2) Firestore(foodSearchCache) → 3) 공공데이터 API
// 성공 응답만 캐시. 결과 있음 30일 / 0건 1시간. 에러는 캐시하지 않음.
// 식약처 데이터는 거의 안 바뀌고 data.go.kr 연결이 불안정하므로 길게 잡는다.
// 만료 문서는 Firestore TTL 정책(expiresAt 필드)이 자동 삭제한다.
// v3: 후보 풀 확대 + 엄격 필터(부분 토큰 제외) + 정확/접두 일치 우선 랭킹
// v4: "{검색어}_생것" 원재료 변형 조회 추가 + 최상단 고정
// v5: 상태 접미사(삶은것/구운것/찐것/볶은것/튀김) 일반화 + 다음 토큰 폴백
// v6: 이름 필드의 "_"를 공백으로 정리해서 반환(화면에 언더바 노출 금지)
// v7: 원재료 표제어 예외(감자→감자_수미_생것 등) 최상단 고정
// v8: 옥수수→옥수수_찰옥수수_생것 예외 추가 + 품종 분화 식재료(대표
//     표제어 없이 품종만 있는 경우) 최대 2개까지 자동 나열
// v9: 메인 쿼리에 이미 정확 일치가 있으면 원재료 변형 조회 생략(동시
//     호출 수 절감) + API 타임아웃 6000→9000ms
// v10: v9의 순차 실행(정확 일치 시 생략)을 되돌려 병렬 실행으로 복귀 —
//      동시 호출 절감 효과가 불확실한 반면 지연시간 증가는 확실해서
//      되돌림. 폴백 토큰이 결과를 구제했는데도 unavailable을 잘못 던지던
//      경계 조건 버그 수정은 유지. API 타임아웃 9000ms는 유지.
// v11: 옥수수 오버라이드 제거(자동 품종 나열로 전환) + 품종 후보 상한
//      2→3개
// v12: 품종 후보 표시명에서 대표명 접두사 제거 — "고추 풋고추"→"풋고추"
const CACHE_VERSION = 12;
const CACHE_COLLECTION = "foodSearchCache";
const CACHE_TTL_NONEMPTY_MS = 30 * 24 * 60 * 60 * 1000;
const CACHE_TTL_EMPTY_MS = 60 * 60 * 1000;
const CACHE_MAX_ENTRIES = 500;
const searchCache = new Map(); // docId -> { body, expiresAt }

const MIN_TOKEN_LEN = 2;
// 공공데이터(data.go.kr)가 클라우드 IP를 스로틀링하면 버스트가 잘 막히므로
// 한 검색당 호출 수를 줄인다(전체 문장 + 최장 토큰만).
const MAX_API_QUERIES = 2;
const API_NUM_OF_ROWS = 100;
const MAX_RESULT_ITEMS = 20;

// 공공데이터 API가 GCF 리전에서 간헐적으로 응답을 지연/드롭한다.
// 짧은 타임아웃 + 재시도로 사용자를 오래 기다리게 하지 않으면서 뚫릴 확률을 높인다.
// 6000ms는 정상 응답(3.7~4초대)과 여유가 너무 적어 자주 걸렸다 → 9000ms로 완화.
const API_TIMEOUT_MS = 9000;
const API_MAX_ATTEMPTS = 2; // 최초 1회 + 재시도 1회

/**
 * 특수문자·공백 제거 후 비교용 문자열.
 * 예: "하림 오!늘단백" → "하림오늘단백"
 */
function stripForMatch(s) {
  return String(s ?? "")
    .normalize("NFC")
    .toLowerCase()
    .replace(/[^\p{Script=Hangul}\p{Script=Latin}0-9]/gu, "");
}

/** 캐시 키용: 특수문자 무시 정규화 (동일 의도 검색어가 같은 키를 쓰도록). */
function normalizeQueryForCache(query) {
  const stripped = stripForMatch(query);
  if (stripped) return stripped;
  return query.trim().replace(/\s+/g, " ").toLowerCase().normalize("NFC");
}

function cacheDocId(normalizedQuery) {
  return crypto.createHash("sha256").update(normalizedQuery).digest("hex");
}

function ttlForItemCount(count) {
  return count === 0 ? CACHE_TTL_EMPTY_MS : CACHE_TTL_NONEMPTY_MS;
}

function foodNameOf(row) {
  return String(
    row?.FOOD_NM_KR ||
      row?.DESC_KOR ||
      row?.PRDLST_NM ||
      row?.RCP_NM ||
      ""
  ).trim();
}

function makerNameOf(row) {
  return String(row?.MAKER_NM || row?.MAKER_NAME || "").trim();
}

/**
 * 식약처 DB 원본 표기("달걀_난백_삶은것" 등)의 "_"는 화면에 노출하지
 * 않는다. 클라이언트에 내려주기 직전에 이름 관련 필드만 정리한다.
 */
function cleanDisplayText(value) {
  if (typeof value !== "string") return value;
  return value.replace(/_/g, " ").replace(/\s+/g, " ").trim();
}

function sanitizeItemForDisplay(item) {
  // Firestore는 undefined 필드를 허용하지 않으므로, 원래 없던 필드에
  // undefined를 새로 추가하지 않도록 존재하는 문자열 필드만 덮어쓴다.
  const sanitized = { ...item };
  for (const key of ["FOOD_NM_KR", "DESC_KOR", "PRDLST_NM", "RCP_NM"]) {
    if (typeof sanitized[key] === "string") {
      sanitized[key] = cleanDisplayText(sanitized[key]);
    }
  }
  sanitized.BRAND_DISPLAY = brandDisplayNameOf({
    foodName: foodNameOf(item),
    makerNm: makerNameOf(item),
  });
  return sanitized;
}

function itemDedupeKey(row) {
  const code = row?.FOOD_CD ?? row?.foodCd ?? row?.NUM;
  if (code != null && String(code).trim() !== "") return `cd:${code}`;
  return `nm:${stripForMatch(foodNameOf(row))}::${stripForMatch(
    makerNameOf(row)
  )}`;
}

/**
 * API에 넣을 검색어 후보 전체 목록(잘라내지 않음): 전체 문장 + 공백 토큰(긴 것 우선).
 * DB에 특수문자가 끼어 있어도 "프로틴","쿠키" 같은 토큰으로 후보를 끌어온다.
 * 실제로 몇 개를 쓸지는 호출부(searchFoodItemsWithTokens)가 결정한다
 * (1차 MAX_API_QUERIES개 + 결과 없을 때 폴백으로 다음 후보 1개 추가).
 */
function buildSearchQueryCandidates(query) {
  const trimmed = query.trim().replace(/\s+/g, " ");
  const tokens = trimmed
    .split(/\s+/)
    .filter((t) => stripForMatch(t).length >= MIN_TOKEN_LEN);
  const queries = [];
  const seen = new Set();
  const add = (q) => {
    const k = String(q ?? "").trim();
    if (!k || seen.has(k)) return;
    seen.add(k);
    queries.push(k);
  };
  add(trimmed);
  [...tokens]
    .sort((a, b) => b.length - a.length)
    .forEach(add);
  return queries;
}

/**
 * 후보를 특수문자 무시 기준으로 엄격 필터·정렬.
 * - 노출: 정규화 전체 검색어가 이름에 포함, 또는 모든 토큰이 이름에 포함
 * - 부분 토큰만 맞는 항목은 제외
 * - 정렬: 완전 일치 → 접두 일치 → 포함, 제조사 일치 시 소폭 가점
 */
function filterAndRankItems(items, query) {
  const qNorm = stripForMatch(query);
  const tokens = query
    .trim()
    .split(/\s+/)
    .map(stripForMatch)
    .filter((t) => t.length >= MIN_TOKEN_LEN);

  const scored = [];
  for (const item of items) {
    const nNorm = stripForMatch(foodNameOf(item));
    if (!nNorm) continue;

    const fullHit = qNorm.length > 0 && nNorm.includes(qNorm);
    const allTokens =
      tokens.length > 0 && tokens.every((t) => nNorm.includes(t));
    if (!fullHit && !allTokens) continue;

    const exact = qNorm.length > 0 && nNorm === qNorm;
    const prefix = !exact && qNorm.length > 0 && nNorm.startsWith(qNorm);
    const makerNorm = stripForMatch(makerNameOf(item));
    const makerFullHit = qNorm.length > 0 && makerNorm.includes(qNorm);
    const makerTokenHits = tokens.filter((t) => makerNorm.includes(t)).length;

    let score = 0;
    if (exact) score += 10000;
    else if (prefix) score += 5000;
    else if (fullHit) score += 1000;
    if (allTokens) score += 100;
    if (makerFullHit) score += 50;
    score += makerTokenHits * 15;
    // 동점이면 짧은 이름이 위로
    score -= Math.min(nNorm.length, 200) * 0.01;
    scored.push({ item, score });
  }

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, MAX_RESULT_ITEMS).map((s) => s.item);
}

// 검색어에 "삶은/구운/찐/볶은/튀김" 같은 상태 표현이 있으면, DB는 그
// 상태의 원재료 표제어("달걀_삶은것" 등)를 따로 갖고 있는 경우가 많다.
// 접미사가 여러 형태로 갈리는 경우(예: 구운것/구운것(팬)/구운것(오븐))엔
// API엔 공통 부분만 보내 한 번에 다 받아오고(FOOD_NM_KR은 부분 문자열
// 검색), acceptSuffixes 중 하나라도 정확히 일치하면 채택한다.
const STATE_RULES = [
  { pattern: /삶은(것)?/, querySuffix: "삶은것", acceptSuffixes: ["삶은것"] },
  { pattern: /찐(것)?/, querySuffix: "찐것", acceptSuffixes: ["찐것"] },
  { pattern: /볶은(것)?/, querySuffix: "볶은것", acceptSuffixes: ["볶은것"] },
  {
    pattern: /튀김|튀긴(것)?/,
    querySuffix: "튀",
    acceptSuffixes: ["튀김", "튀긴것"],
  },
  {
    pattern: /구운(것)?/,
    querySuffix: "구운것",
    acceptSuffixes: ["구운것", "구운것(팬)", "구운것(오븐)"],
  },
];
const DEFAULT_STATE_RULE = { querySuffix: "생것", acceptSuffixes: ["생것"] };

function findRawFoodOverride(query) {
  const qNorm = stripForMatch(query);
  if (!qNorm) return null;
  return (
    RAW_FOOD_OVERRIDES.find((row) =>
      row.queries.some((q) => stripForMatch(q) === qNorm)
    ) ?? null
  );
}

function applyDisplayName(item, displayName) {
  const name = String(displayName ?? "").trim();
  if (!name) return item;
  return { ...item, FOOD_NM_KR: name };
}

/**
 * override.apiName으로 조회한 뒤 그 이름과 정확히 맞는 행만 채택한다.
 */
async function fetchRawFoodOverrideItem(override, originalQuery, serviceKey) {
  if (!override) return null;
  const { apiName, displayName } = override;
  try {
    const items = await fetchFoodApiItems(apiName, serviceKey);
    const want = stripForMatch(apiName);
    const match = items.find((it) => stripForMatch(foodNameOf(it)) === want);
    if (!match) return null;
    const name =
      (displayName && String(displayName).trim()) ||
      originalQuery.trim().replace(/\s+/g, " ");
    return applyDisplayName(match, name);
  } catch (error) {
    if (
      error instanceof functions.https.HttpsError &&
      error.code === "unauthenticated"
    ) {
      throw error;
    }
    console.warn("[search] 원재료 예외 조회 실패 (건너뜀)", {
      apiName,
      message: error?.message ?? String(error),
    });
    return null;
  }
}

/**
 * 짧은 순수 식재료명 검색일 때만 원재료 상태 변형(예: "사과_생것",
 * "달걀_삶은것")을 추가로 조회한다. 식약처 DB는 원재료 항목을 상태
 * 접미사로 등록해 두는데, 등록순 정렬 특성상 몇 페이지 뒤에 묻혀 있어
 * 기존 numOfRows=100/1페이지 조회로는 못 건져낸다. 가공식품/조리식품
 * 형태를 가리키는 검색어(가루/즙/주스/잼/통조림/냉동/건조)는 제외한다.
 */
function buildRawVariantQuery(query) {
  const trimmed = query.trim().replace(/\s+/g, "");
  if (!trimmed) return null;
  // 상태 접미사는 한글 식재료명 관례이므로 한글이 없는 검색어(영문
  // 브랜드명 등)는 애초에 매치될 리 없어 API 호출을 아낀다.
  if (!/\p{Script=Hangul}/u.test(trimmed)) return null;
  if (/가루|분말|즙|주스|잼|통조림|냉동|건조/.test(trimmed)) return null;

  const stateRule =
    STATE_RULES.find((rule) => rule.pattern.test(trimmed)) ??
    DEFAULT_STATE_RULE;
  const foodPart =
    stateRule === DEFAULT_STATE_RULE
      ? trimmed
      : trimmed.replace(stateRule.pattern, "");

  // 이 트릭은 정확 일치(또는 엄격한 3세그먼트 품종 매치)로만 채택되므로
  // 오탐 위험이 없어, 다단어 토큰화용 MIN_TOKEN_LEN(2)과 달리 1글자
  // 식재료명("밤", "배" 등)도 허용한다.
  const normalized = stripForMatch(foodPart);
  if (normalized.length < 1 || normalized.length > 8) return null;

  const canonical = RAW_VARIANT_SYNONYMS[foodPart] || foodPart;
  return {
    apiQuery: `${canonical}_${stateRule.querySuffix}`,
    canonical,
    acceptSuffixes: stateRule.acceptSuffixes,
  };
}

// 대표 표제어가 없고 품종별로만 나뉜 식재료(예: 옥수수_단옥수수_생것/
// 메옥수수_생것/찰옥수수_생것)를 자동으로 나열할 때 보여줄 최대 개수.
// RAW_FOOD_OVERRIDES에 수동으로 대표 품종을 지정해 둔 식재료는 이 자동
// 나열을 안 타고 그 지정된 항목 하나만 나온다.
const MAX_VARIETY_CANDIDATES = 3;

/**
 * 상태 변형(예: "_생것") 조회 결과를 두 단계로 채택한다.
 * 1) acceptSuffixes(대표 표제어 + 접미사)와 정확히 일치하는 단일 항목이
 *    있으면 그것만 채택하고, 사용자에게는 검색한 단어 그대로 보여준다.
 * 2) 정확 일치가 없으면, "{대표명}_{품종}_{접미사}"처럼 정확히 3세그먼트
 *    이고 첫 세그먼트가 대표명과 정확히 같은 항목(품종 분화)을 최대
 *    MAX_VARIETY_CANDIDATES개까지 채택한다 — 임의로 하나를 골라 검색어로
 *    뭉개지 않고, 품종명만 보여준다(오탐 방지: 대표 표제어와 무관한
 *    복합어는 첫 세그먼트 완전 일치 조건에서 걸러진다). 이 매칭 방식은
 *    부분 문자열 검색 특성상 품종명이 대표명을 포함하는 경우에만 걸리므로
 *    (예: "단옥수수"는 "옥수수"를 포함), 품종명만 보여줘도 대표명과
 *    동떨어지지 않는다.
 * 둘 다 없으면 빈 배열.
 */
async function fetchRawVariantCandidates(rawVariant, originalQuery, serviceKey) {
  if (!rawVariant) return [];
  const { apiQuery, canonical, acceptSuffixes } = rawVariant;
  try {
    const items = await fetchFoodApiItems(apiQuery, serviceKey);
    const displayPrefix = originalQuery.trim().replace(/\s+/g, " ");

    const acceptableNorms = acceptSuffixes.map((suffix) =>
      stripForMatch(`${canonical}${suffix}`)
    );
    const exactMatch = items.find((it) =>
      acceptableNorms.includes(stripForMatch(foodNameOf(it)))
    );
    if (exactMatch) {
      // 상태 접미사(및 동의어 치환)는 내부 처리일 뿐이라 사용자에게는
      // 검색한 단어 그대로 보여준다.
      return [applyDisplayName(exactMatch, displayPrefix)];
    }

    const acceptSuffixNorms = acceptSuffixes.map((s) => stripForMatch(s));
    const varieties = [];
    for (const it of items) {
      const segments = foodNameOf(it)
        .split("_")
        .map((s) => s.trim());
      if (segments.length !== 3) continue;
      if (segments[0] !== canonical) continue;
      if (!acceptSuffixNorms.includes(stripForMatch(segments[2]))) continue;
      varieties.push(applyDisplayName(it, segments[1]));
      if (varieties.length >= MAX_VARIETY_CANDIDATES) break;
    }
    return varieties;
  } catch (error) {
    if (
      error instanceof functions.https.HttpsError &&
      error.code === "unauthenticated"
    ) {
      throw error;
    }
    console.warn("[search] 상태/품종 변형 검색 실패 (건너뜀)", {
      apiQuery,
      message: error?.message ?? String(error),
    });
    return [];
  }
}

function dedupeItems(items) {
  const out = [];
  const seen = new Set();
  for (const item of items) {
    const key = itemDedupeKey(item);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

function normalizeItemRows(items) {
  if (items == null) return [];
  if (Array.isArray(items)) {
    return items.filter(
      (e) => e && typeof e === "object" && !Array.isArray(e)
    );
  }
  if (typeof items === "object") {
    if (Object.prototype.hasOwnProperty.call(items, "item")) {
      return normalizeItemRows(items.item);
    }
    return [items];
  }
  return [];
}

/** API 원본 JSON에서 식품 row만 추출 (문서 크기 최소화용). */
function extractItemsFromApiBody(body) {
  if (!body || typeof body !== "object") return [];
  if (body.I2790 && body.I2790.row != null) {
    return normalizeItemRows(body.I2790.row);
  }
  const respBody = body.response?.body ?? body.body;
  if (respBody && typeof respBody === "object") {
    const fromItems = normalizeItemRows(respBody.items);
    const fromItem = normalizeItemRows(respBody.item);
    if (fromItems.length || fromItem.length) {
      return [...fromItems, ...fromItem];
    }
  }
  return [];
}

/** 클라이언트의 기존 파서가 읽을 수 있는 형태로 감싼다. */
function wrapItemsAsClientBody(items) {
  return {
    response: {
      header: { resultCode: "00", resultMsg: "OK" },
      body: { items },
    },
  };
}

function getMemoryCachedResult(docId) {
  const entry = searchCache.get(docId);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    searchCache.delete(docId);
    return null;
  }
  searchCache.delete(docId);
  searchCache.set(docId, entry);
  return entry.body;
}

function setMemoryCachedResult(docId, body, ttlMs) {
  if (searchCache.size >= CACHE_MAX_ENTRIES) {
    const oldestKey = searchCache.keys().next().value;
    if (oldestKey !== undefined) searchCache.delete(oldestKey);
  }
  searchCache.set(docId, { body, expiresAt: Date.now() + ttlMs });
}

function timestampToMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (typeof value === "number") return value;
  return null;
}

/**
 * Firestore 캐시 조회. 실패·만료·버전 불일치는 null (API로 fallback).
 * @returns {Promise<{ body: object, ttlRemainingMs: number } | null>}
 */
async function getFirestoreCachedResult(docId) {
  try {
    const ref = admin.firestore().collection(CACHE_COLLECTION).doc(docId);
    const snap = await ref.get();
    if (!snap.exists) return null;

    const data = snap.data() || {};
    if (data.v !== CACHE_VERSION) return null;
    if (!Array.isArray(data.items)) return null;

    const expiresAtMs = timestampToMillis(data.expiresAt);
    if (expiresAtMs == null || Date.now() > expiresAtMs) {
      ref.delete().catch((err) => {
        console.warn("만료 캐시 삭제 실패:", err?.message ?? err);
      });
      return null;
    }

    return {
      body: wrapItemsAsClientBody(data.items),
      ttlRemainingMs: Math.max(expiresAtMs - Date.now(), 1),
    };
  } catch (err) {
    console.error("Firestore 캐시 읽기 실패 (API로 fallback):", err?.message ?? err);
    return null;
  }
}

async function setFirestoreCachedResult(docId, normalizedQuery, items) {
  const ttlMs = ttlForItemCount(items.length);
  const now = Date.now();
  try {
    await admin.firestore().collection(CACHE_COLLECTION).doc(docId).set({
      v: CACHE_VERSION,
      query: normalizedQuery,
      items,
      itemCount: items.length,
      createdAt: admin.firestore.Timestamp.fromMillis(now),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + ttlMs),
    });
  } catch (err) {
    console.error("Firestore 캐시 쓰기 실패:", err?.message ?? err);
  }
  return ttlMs;
}

/** 디코딩 인증키를 .env에 넣은 경우: 한 번 디코드 후 axios가 쿼리스트링으로 인코딩 */
function tryDecodeServiceKey(raw) {
  if (!raw) return raw;
  try {
    return decodeURIComponent(raw.trim());
  } catch (_) {
    return raw.trim();
  }
}

function extractApiErrorMessage(payload) {
  if (!payload) return "";
  if (typeof payload === "string") return payload.slice(0, 180);
  const header = payload?.response?.header;
  if (header?.resultMsg) return String(header.resultMsg);
  if (payload?.message) return String(payload.message);
  return "";
}

/**
 * 네트워크 타임아웃/연결 오류일 때만 짧게 재시도한다. HTTP 상태 코드는
 * validateStatus로 통과시키므로 여기서 throw되는 건 순수 네트워크 오류뿐.
 */
async function axiosGetFoodApi(params) {
  let lastErr;
  for (let attempt = 1; attempt <= API_MAX_ATTEMPTS; attempt++) {
    try {
      return await axios.get(BASE_URL, {
        params,
        timeout: API_TIMEOUT_MS,
        validateStatus: () => true,
      });
    } catch (err) {
      lastErr = err;
      const retriable =
        !err.response ||
        ["ECONNABORTED", "ECONNRESET", "ETIMEDOUT", "EAI_AGAIN"].includes(
          err.code
        );
      console.warn("[search] 공공데이터 요청 네트워크 오류", {
        attempt,
        code: err.code,
        message: err.message,
      });
      if (!retriable || attempt === API_MAX_ATTEMPTS) throw err;
      await new Promise((r) => setTimeout(r, 400 * attempt));
    }
  }
  throw lastErr;
}

/**
 * 공공데이터 401 대응: 인코딩 키를 그대로 두면 axios가 한 번 더 인코딩해 401이 나는 경우가 많음.
 * variant 순서대로 시도한다.
 */
async function fetchFoodApi(query, envKey) {
  const trimmed = envKey.trim();
  const variants = [
    { label: "decode-then-axios-encode", key: tryDecodeServiceKey(trimmed) },
    { label: "raw-trim-only", key: trimmed },
  ];

  let lastStatus;
  let lastData;
  let lastLabel;

  for (const { label, key } of variants) {
    if (!key) continue;
    const attemptStart = Date.now();
    const response = await axiosGetFoodApi({
      serviceKey: key,
      pageNo: 1,
      numOfRows: API_NUM_OF_ROWS,
      type: "json",
      FOOD_NM_KR: query,
    });
    console.log("[timing] 공공데이터 API 응답 시간", {
      query,
      variant: label,
      status: response.status,
      elapsedMs: Date.now() - attemptStart,
    });
    lastStatus = response.status;
    lastData = response.data;
    lastLabel = label;

    if (response.status !== 401) {
      return response;
    }
  }

  const apiMsg = extractApiErrorMessage(lastData);
  console.error("공공데이터 401 (모든 키 변형 실패)", {
    lastLabel,
    lastStatus,
    apiMsgSnippet: apiMsg || undefined,
  });

  throw new functions.https.HttpsError(
    "unauthenticated",
    [
      "공공데이터 API 인증 실패(401). 아래를 확인해 주세요.",
      "1) 공공데이터포털에서 이 API(식품영양성분DB)에 일반/활용 신청이 되어 있는지",
      "2) Firebase Functions 환경변수 FOOD_API_KEY에 넣은 값이 '일반 인증키(Encoding)'인지",
      "3) 포털에서 복사한 키에 따옴표·공백·줄바꿈이 섞이지 않았는지",
      "4) .env에 '이미 % 인코딩된 문자열'을 넣었다면, '디코딩된 원문 키'로 바꿔 보세요(이중 인코딩 방지).",
      apiMsg ? `응답: ${apiMsg}` : "",
    ]
      .filter(Boolean)
      .join(" ")
  );
}

/** 단일 검색어로 API를 호출해 items만 반환. 인증 실패는 throw, 그 외는 상위에서 처리. */
async function fetchFoodApiItems(query, envKey) {
  const response = await fetchFoodApi(query, envKey);

  if (response.status < 200 || response.status >= 300) {
    const apiMsg = extractApiErrorMessage(response.data);
    throw new functions.https.HttpsError(
      "internal",
      `공공데이터 HTTP 오류 (${response.status})${
        apiMsg ? ` - ${apiMsg}` : ""
      }`
    );
  }

  const body = response.data;
  const rc = body?.response?.header?.resultCode;
  const rcStr = rc != null ? String(rc) : "";
  if (rcStr && rcStr !== "00" && rcStr !== "03") {
    const msg = body?.response?.header?.resultMsg ?? "OpenAPI 오류";
    throw new functions.https.HttpsError(
      "failed-precondition",
      `${msg} (${rcStr})`
    );
  }

  return extractItemsFromApiBody(body);
}

/**
 * 전체 문장 + 토큰으로 병렬 검색 후 중복 제거 → 특수문자 무시 필터/정렬.
 */
/** 검색어 후보 하나를 API로 조회. 인증 실패는 throw, 그 외는 ok:false로 감싼다. */
async function fetchQueryCandidate(q, serviceKey) {
  try {
    const items = await fetchFoodApiItems(q, serviceKey);
    return { q, items, ok: true, error: null };
  } catch (error) {
    if (
      error instanceof functions.https.HttpsError &&
      error.code === "unauthenticated"
    ) {
      throw error;
    }
    console.warn("[search] 토큰 검색 실패 (건너뜀)", {
      q,
      message: error?.message ?? String(error),
    });
    return { q, items: [], ok: false, error };
  }
}

async function searchFoodItemsWithTokens(query, serviceKey) {
  const candidates = buildSearchQueryCandidates(query);
  const initialQueries = candidates.slice(0, MAX_API_QUERIES);
  // 1차 결과가 비었을 때만 쓸 다음 토큰(있다면 1개). 예: "삶은 계란"에서
  // 동점 정렬 때문에 "계란" 토큰이 초기 2개 슬롯에서 밀려난 경우를 구제한다.
  const fallbackQuery = candidates[MAX_API_QUERIES] ?? null;
  const override = findRawFoodOverride(query);
  // 예외 표제어가 있으면 "{검색어}_생것" 추정 조회는 생략한다.
  const rawVariant = override ? null : buildRawVariantQuery(query);
  console.log("[search] API 쿼리 목록", {
    query,
    initialQueries,
    fallbackQuery,
    rawVariant,
    override: override
      ? { apiName: override.apiName, displayName: override.displayName }
      : null,
  });

  // 메인 쿼리·원재료 변형·오버라이드를 전부 병렬로 쏜다. data.go.kr
  // 일일 트래픽 한도(10,000건)만 확인 가능하고 동시 요청 수 제한 여부는
  // 알 수 없는 반면, 순차 실행은 지연시간이 체감될 만큼(약 2배) 늘어나는
  // 확실한 비용이라 병렬로 유지한다(캐시가 실질적인 부하 대부분을
  // 흡수하므로, 이 병렬 호출은 캐시 미스일 때만 발생한다).
  const [settled, rawVariantItems, overrideItem] = await Promise.all([
    Promise.all(initialQueries.map((q) => fetchQueryCandidate(q, serviceKey))),
    fetchRawVariantCandidates(rawVariant, query, serviceKey),
    fetchRawFoodOverrideItem(override, query, serviceKey),
  ]);

  let merged = [];
  for (const part of settled) {
    merged.push(...part.items);
  }
  let ranked = filterAndRankItems(dedupeItems(merged), query);

  // 1차 결과가 완전히 비었고 아직 안 써본 토큰이 있으면 그것만 추가로 조회한다.
  if (ranked.length === 0 && fallbackQuery) {
    console.log("[search] 1차 결과 없음 → 폴백 토큰 조회", {
      query,
      fallbackQuery,
    });
    const fallback = await fetchQueryCandidate(fallbackQuery, serviceKey);
    if (fallback.ok && fallback.items.length > 0) {
      merged = merged.concat(fallback.items);
      ranked = filterAndRankItems(dedupeItems(merged), query);
    }
  }

  // 모든 쿼리가 "0건"이 아니라 "오류"로 실패했으면 상위로 던진다.
  // (그래야 클라이언트가 "결과 없음"이 아닌 "잠시 후 다시 시도" 메시지를 띄우고,
  //  타임아웃 결과가 빈 값으로 캐시에 저장되지 않는다.)
  // 단, 폴백 토큰 조회나 예외/상태·품종 변형 조회로 유효한 결과를
  // 하나라도 건졌다면(ranked가 비어있지 않다면) 그거라도 보여준다.
  if (
    settled.length > 0 &&
    settled.every((p) => !p.ok) &&
    ranked.length === 0 &&
    rawVariantItems.length === 0 &&
    !overrideItem
  ) {
    const firstErr = settled.find((p) => p.error)?.error;
    throw new functions.https.HttpsError(
      "unavailable",
      `식품 정보 서버(공공데이터)에 연결하지 못했습니다: ${
        firstErr?.message ?? "timeout"
      }`
    );
  }

  // 예외 표제어 → 상태 변형 정확 매치/품종 후보 순으로 최상단에 고정한다.
  return pinItemsFirst([overrideItem, ...rawVariantItems], ranked);
}

/** pinned 항목을 ranked 앞에 두고, 같은 식품은 한 번만 남긴다. */
function pinItemsFirst(pinned, ranked) {
  return dedupeItems([...pinned.filter(Boolean), ...ranked]).slice(
    0,
    MAX_RESULT_ITEMS
  );
}

exports.searchFood = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
  const query = (
    data?.query ??
    data?.searchQuery ??
    data?.data?.query ??
    data?.data?.searchQuery ??
    ""
  )
    .toString()
    .trim();
  if (!query) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "검색어를 입력해주세요."
    );
  }

  const normalizedQuery = normalizeQueryForCache(query);
  const docId = cacheDocId(normalizedQuery);

  const memoryHit = getMemoryCachedResult(docId);
  if (memoryHit) {
    console.log("[timing] 메모리 캐시 히트, 외부 API 호출 생략", { query });
    return memoryHit;
  }

  const firestoreHit = await getFirestoreCachedResult(docId);
  if (firestoreHit) {
    setMemoryCachedResult(
      docId,
      firestoreHit.body,
      firestoreHit.ttlRemainingMs
    );
    console.log("[timing] Firestore 캐시 히트, 외부 API 호출 생략", {
      query,
    });
    return firestoreHit.body;
  }

  const serviceKey = process.env.FOOD_API_KEY;
  if (!serviceKey) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "FOOD_API_KEY(공공데이터 serviceKey)가 Functions 환경변수에 없습니다."
    );
  }

  const handlerStart = Date.now();
  try {
    const rawItems = await searchFoodItemsWithTokens(query, serviceKey);
    const items = rawItems.map(sanitizeItemForDisplay);
    const body = wrapItemsAsClientBody(items);
    const ttlMs = await setFirestoreCachedResult(
      docId,
      normalizedQuery,
      items
    );
    setMemoryCachedResult(docId, body, ttlMs);

    console.log("[timing] searchFood 전체 처리 시간", {
      query,
      totalMs: Date.now() - handlerStart,
      itemCount: items.length,
      cacheTtlMs: ttlMs,
    });
    return body;
  } catch (error) {
    console.log("[timing] searchFood 실패까지 걸린 시간", {
      query,
      totalMs: Date.now() - handlerStart,
    });
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    if (axios.isAxiosError(error)) {
      const status = error.response?.status;
      const apiMsg = extractApiErrorMessage(error.response?.data);
      console.error("API 호출 에러(axios):", {
        status,
        message: error.message,
        apiMsg,
      });
      throw new functions.https.HttpsError(
        "internal",
        status != null
          ? `공공데이터 HTTP 오류 (${status})${apiMsg ? ` - ${apiMsg}` : ""}`
          : `공공데이터 호출 실패: ${error.message}`
      );
    }
    console.error("API 호출 에러(unknown):", error);
    throw new functions.https.HttpsError(
      "internal",
      `공공데이터를 불러오는 중 문제가 발생했습니다: ${
        error?.message ?? "unknown"
      }`
    );
  }
});

/**
 * 카카오 로그인 커스텀 토큰 발급.
 *
 * Firebase Auth는 카카오를 기본 제공업체로 지원하지 않으므로, 클라이언트에서
 * 카카오 SDK로 로그인해 얻은 액세스 토큰을 이 함수로 전달하면:
 *   1) 카카오 사용자 API로 액세스 토큰을 검증하고
 *   2) 카카오 회원번호 기반의 고정 uid(`kakao:{id}`)로 Firebase 사용자를 조회/생성한 뒤
 *   3) 해당 uid의 Firebase 커스텀 토큰을 발급해 반환한다.
 * 클라이언트는 반환된 커스텀 토큰으로 `signInWithCustomToken`을 호출해 로그인한다.
 */
exports.kakaoSignIn = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
    const accessToken = (
      data?.accessToken ??
      data?.data?.accessToken ??
      ""
    )
      .toString()
      .trim();

    if (!accessToken) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "카카오 액세스 토큰이 필요합니다."
      );
    }

    let kakaoUser;
    try {
      const response = await axios.get("https://kapi.kakao.com/v2/user/me", {
        headers: { Authorization: `Bearer ${accessToken}` },
        timeout: 15000,
        validateStatus: () => true,
      });
      if (response.status !== 200) {
        throw new Error(`카카오 사용자 조회 실패 (${response.status})`);
      }
      kakaoUser = response.data;
    } catch (error) {
      console.error("카카오 토큰 검증 실패:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "unauthenticated",
        "카카오 액세스 토큰 검증에 실패했습니다."
      );
    }

    const kakaoId = kakaoUser?.id;
    if (!kakaoId) {
      throw new functions.https.HttpsError(
        "internal",
        "카카오 사용자 ID를 확인할 수 없습니다."
      );
    }

    const uid = `kakao:${kakaoId}`;
    const email = kakaoUser?.kakao_account?.email;
    const nickname = kakaoUser?.kakao_account?.profile?.nickname;

    try {
      await admin.auth().getUser(uid);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        await admin.auth().createUser({
          uid,
          email: email || undefined,
          displayName: nickname || undefined,
        });
      } else {
        console.error("카카오 Firebase 사용자 조회/생성 실패:", error);
        throw new functions.https.HttpsError(
          "internal",
          "사용자 생성 중 문제가 발생했습니다."
        );
      }
    }

    const customToken = await admin.auth().createCustomToken(uid);
    return { customToken };
  });

const NICKNAME_MAX_LEN = 20;

/** 닉네임 중복확인/저장용 정규화: 트림 + 소문자 + 공백 제거. */
function normalizeNickname(nickname) {
  return String(nickname ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "");
}

/**
 * 닉네임 수정.
 * `nicknames/{normalized}` 컬렉션을 고유 인덱스로 써서 트랜잭션으로
 * 원자적 중복확인 + 반영을 하고, 기존 닉네임의 인덱스는 해제한다.
 * 클라이언트는 타이핑 중엔 `nicknames/{normalized}` 문서를 직접 읽어
 * (firestore.rules에서 읽기 허용) 가벼운 실시간 중복 힌트를 보여주고,
 * 실제 저장은 항상 이 함수를 거쳐 경합 상황에서도 중복을 막는다.
 */
exports.updateNickname = functions
  .region("asia-northeast3")
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }
    const uid = context.auth.uid;
    const nickname = String(data?.nickname ?? "").trim();
    if (!nickname || nickname.length > NICKNAME_MAX_LEN) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `닉네임을 1~${NICKNAME_MAX_LEN}자로 입력해 주세요.`
      );
    }
    const normalized = normalizeNickname(nickname);
    if (!normalized) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "닉네임을 입력해 주세요."
      );
    }

    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const nicknameRef = db.collection("nicknames").doc(normalized);

    try {
      await db.runTransaction(async (tx) => {
        const [nicknameSnap, userSnap] = await Promise.all([
          tx.get(nicknameRef),
          tx.get(userRef),
        ]);
        if (nicknameSnap.exists && nicknameSnap.data().uid !== uid) {
          throw new functions.https.HttpsError(
            "already-exists",
            "이미 사용 중인 닉네임이에요."
          );
        }

        const oldNickname = userSnap.exists ? userSnap.data().nickname : null;
        if (oldNickname) {
          const oldNormalized = normalizeNickname(oldNickname);
          if (oldNormalized && oldNormalized !== normalized) {
            tx.delete(db.collection("nicknames").doc(oldNormalized));
          }
        }

        tx.set(nicknameRef, {
          uid,
          nickname,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.set(userRef, { nickname }, { merge: true });
      });

      await admin.auth().updateUser(uid, { displayName: nickname });
      console.log("닉네임 수정 완료", { uid });
      return { ok: true };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("닉네임 수정 실패:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "internal",
        "닉네임 수정 중 문제가 발생했습니다."
      );
    }
  });

// --- Apple 로그인 토큰 관리 (탈퇴 시 revoke 용) -----------------
// Apple Sign in with Apple 가이드라인상, 앱이 계정 삭제를 지원하면
// 삭제 시점에 Apple 쪽 토큰도 revoke해야 한다. authorizationCode는
// 1회용·5분 제한이라 탈퇴 시점엔 이미 쓸 수 없으므로, 로그인 직후
// refresh_token으로 교환해 users/{uid}에 저장해뒀다가 탈퇴 시 사용한다.

const APPLE_BUNDLE_ID = "com.kyom.calCalApp";
const APPLE_TEAM_ID = "3LDWS3M88X";

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

/** Secret Manager에 보관한 Sign in with Apple 키(.p8)로 client_secret JWT 생성. */
function createAppleClientSecret() {
  const keyId = process.env.APPLE_SIGNIN_KEY_ID;
  const privateKey = process.env.APPLE_SIGNIN_PRIVATE_KEY;
  if (!keyId || !privateKey) {
    throw new Error(
      "APPLE_SIGNIN_KEY_ID / APPLE_SIGNIN_PRIVATE_KEY가 설정되지 않았습니다. " +
        "Secret Manager에 값을 넣었는지 확인하세요."
    );
  }
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId };
  const payload = {
    iss: APPLE_TEAM_ID,
    iat: now,
    // 매 요청마다 새로 만들어 바로 쓰므로 길게 잡을 필요 없다.
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: APPLE_BUNDLE_ID,
  };
  const signingInput =
    `${base64url(JSON.stringify(header))}.` +
    base64url(JSON.stringify(payload));
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    // Secret Manager에 .p8 내용을 한 줄로 넣었을 경우를 대비해 \n을 복원.
    key: privateKey.replace(/\\n/g, "\n"),
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64url(signature)}`;
}

/**
 * 애플 로그인 직후 클라이언트가 호출. authorizationCode를 Apple 토큰
 * 엔드포인트와 교환해 refresh_token을 받아 users/{uid}에 저장한다.
 * 실패해도 로그인 자체를 막을 필요는 없으므로 클라이언트에서 best-effort로
 * 처리한다.
 */
exports.registerAppleRefreshToken = functions
  .region("asia-northeast3")
  .runWith({ secrets: ["APPLE_SIGNIN_KEY_ID", "APPLE_SIGNIN_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }
    const authorizationCode = data?.authorizationCode;
    if (!authorizationCode || typeof authorizationCode !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "authorizationCode가 필요합니다."
      );
    }

    try {
      const response = await axios.post(
        "https://appleid.apple.com/auth/token",
        new URLSearchParams({
          grant_type: "authorization_code",
          code: authorizationCode,
          client_id: APPLE_BUNDLE_ID,
          client_secret: createAppleClientSecret(),
        }).toString(),
        { headers: { "Content-Type": "application/x-www-form-urlencoded" } }
      );
      const refreshToken = response.data?.refresh_token;
      if (!refreshToken) {
        throw new Error("Apple 응답에 refresh_token이 없습니다.");
      }
      await admin
        .firestore()
        .collection("users")
        .doc(context.auth.uid)
        .set({ appleRefreshToken: refreshToken }, { merge: true });
      console.log("Apple refresh token 저장 완료", { uid: context.auth.uid });
      return { ok: true };
    } catch (error) {
      console.error(
        "Apple refresh token 등록 실패:",
        error?.response?.data ?? error?.message ?? error
      );
      throw new functions.https.HttpsError(
        "internal",
        "Apple 로그인 토큰 등록에 실패했습니다."
      );
    }
  });

/**
 * 회원 탈퇴.
 * 1) 호출자의 Firestore `users/{uid}` 및 `meals` 하위 문서,
 *    그리고 uid를 참조하는 색인 문서(nicknames, appAccountTokens,
 *    nutritionScanQuota)를 삭제하고
 * 2) Firebase Auth 사용자를 Admin SDK로 삭제한다.
 * subscriptions/{uid}는 전자상거래법상 결제 기록 보존 의무 때문에 남겨둔다.
 * Apple 로그인 사용자는 저장해둔 refresh_token으로 Apple 쪽 토큰도 revoke한다
 * (Sign in with Apple 가이드라인 요구사항). revoke 실패는 탈퇴 자체를 막지 않는다.
 * 클라이언트는 로그인된 상태에서 호출한 뒤, 로컬 소셜 세션을 정리하면 된다.
 */
exports.deleteAccount = functions
  .region("asia-northeast3")
  .runWith({ secrets: ["APPLE_SIGNIN_KEY_ID", "APPLE_SIGNIN_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }

    const uid = context.auth.uid;
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);

    try {
      const [mealsSnap, userSnap] = await Promise.all([
        userRef.collection("meals").get(),
        userRef.get(),
      ]);
      const userData = userSnap.data();

      let batch = db.batch();
      let ops = 0;

      const commitIfNeeded = async (force = false) => {
        if (ops === 0) return;
        if (!force && ops < 400) return;
        await batch.commit();
        batch = db.batch();
        ops = 0;
      };

      for (const doc of mealsSnap.docs) {
        batch.delete(doc.ref);
        ops += 1;
        await commitIfNeeded();
      }

      const nickname = userData?.nickname;
      if (nickname) {
        const nicknameRef = db
          .collection("nicknames")
          .doc(normalizeNickname(nickname));
        const nicknameSnap = await nicknameRef.get();
        if (nicknameSnap.exists && nicknameSnap.data()?.uid === uid) {
          batch.delete(nicknameRef);
          ops += 1;
          await commitIfNeeded();
        }
      }

      const appAccountToken = userData?.appAccountToken;
      if (appAccountToken) {
        batch.delete(db.collection("appAccountTokens").doc(appAccountToken));
        ops += 1;
        await commitIfNeeded();
      }

      batch.delete(db.collection(NUTRITION_SCAN_QUOTA_COLLECTION).doc(uid));
      ops += 1;
      await commitIfNeeded();

      batch.delete(userRef);
      ops += 1;
      await commitIfNeeded(true);

      const appleRefreshToken = userData?.appleRefreshToken;
      if (appleRefreshToken) {
        try {
          await axios.post(
            "https://appleid.apple.com/auth/revoke",
            new URLSearchParams({
              client_id: APPLE_BUNDLE_ID,
              client_secret: createAppleClientSecret(),
              token: appleRefreshToken,
              token_type_hint: "refresh_token",
            }).toString(),
            { headers: { "Content-Type": "application/x-www-form-urlencoded" } }
          );
          console.log("Apple 토큰 revoke 완료", { uid });
        } catch (error) {
          // revoke 실패는 탈퇴 자체를 막지 않는다 (이미 만료/철회된 토큰일 수 있음).
          console.error(
            "Apple 토큰 revoke 실패(탈퇴는 계속 진행):",
            error?.response?.data ?? error?.message ?? error
          );
        }
      }

      await admin.auth().deleteUser(uid);
      console.log("회원 탈퇴 완료", { uid });
      return { ok: true };
    } catch (error) {
      console.error("회원 탈퇴 실패:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "internal",
        "회원 탈퇴 처리 중 문제가 발생했습니다."
      );
    }
  });

// --- 영양성분표 인식 (Gemini 3.1 Flash-Lite) -----------------
// gemini-2.5-flash-lite는 작은 kcal 숫자를 자주 놓쳤고,
// gemini-2.5-flash는 이 프로젝트에 더 이상 제공되지 않아(404) 쓸 수 없다.
// 3.1세대 lite로 올려 비용 부담은 적게 유지하면서 인식률 개선을 노린다.

const GEMINI_MODEL = "gemini-3.1-flash-lite";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024; // callable 페이로드·비용 상한

const NUTRITION_LABEL_PROMPT = `You read a Korean packaged-food nutrition facts label (영양성분표) from a photo.
Return ONLY JSON with this exact schema:
{
  "name": string|null,
  "kcal": number|null,
  "carb": number|null,
  "protein": number|null,
  "fat": number|null,
  "fiber": number|null,
  "isPerHundred": boolean,
  "isPerPiece": boolean,
  "basisLabel": string|null,
  "basisAmount": number|null,
  "basisUnit": "g"|"ml"|"개"|"봉"|"봉지"|"포"|"팩"|null,
  "totalContentAmount": number|null,
  "totalContentUnit": "g"|"ml"|null
}

Rules:
- carb/protein/fat/fiber are grams as printed on the label. carb is total carbohydrate BEFORE subtracting fiber.
- fat means 지방 only. Do NOT use 포화지방 or 트랜스지방 as fat.
- Ignore % daily values (1일 영양성분 기준치).
- Priority for nutrient basis:
  1) If the label shows "100g당", "100그램당", or "100ml당" (e.g. "100그램당 열량(kcal) 250"), set isPerHundred=true, isPerPiece=false, basisAmount=100, basisUnit accordingly. Nutrient numbers are per 100 unit. kcal MUST be that header energy.
  2) Else if individually wrapped / per-piece text appears such as "1개당", "1봉당", "1봉지당", "1포당", "1팩당" (e.g. "1봉당 80kcal", "1개당 20g 100kcal"), set isPerPiece=true, isPerHundred=false. In this case carb/protein/fat/fiber/kcal are for ONE piece (same basis as that header). Set basisLabel to the matched text like "1개당"/"1봉당". If piece weight is given (e.g. 20g), basisAmount=that weight and basisUnit=g/ml; otherwise basisAmount=1 and basisUnit=개/봉/포/etc. kcal MUST be the per-piece energy.
  3) Else nutrient numbers are for 총 내용량: isPerHundred=false, isPerPiece=false, basisAmount=totalContentAmount, basisUnit=totalContentUnit, kcal for that amount.
- totalContentAmount is 총 내용량 when present (package total), even for per-piece labels.
- Prefer 1회 제공량 only when none of the above apply.
- name is product name if visible; otherwise null.
- kcal is required whenever any energy number is visible near 열량/칼로리/에너지 on the label — always extract it, even if the layout is unusual (line-wrapped, parenthesized unit like "열량(kcal)", or written as "약 250kcal"). Only use null for kcal if no energy number appears anywhere on the label.
- Use null for unreadable fields. Numbers must be non-negative plain numbers (no unit suffix).`;

// --- 무료 사용량 제한 ---
// tier/scanCount는 `nutritionScanQuota/{uid}`에 Admin SDK로만 쓴다.
// (firestore.rules에서 클라이언트 쓰기를 막아, 클라이언트가 직접 등급·횟수를
// 조작할 수 없게 한다.) 구독 결제 연동 전까지는 모든 사용자가 free 등급이고,
// 나중에 결제 웹훅이 tier를 "subscribed"로 바꿔주면 무제한이 된다.
const NUTRITION_SCAN_QUOTA_COLLECTION = "nutritionScanQuota";
const FREE_DAILY_SCAN_LIMIT = 10;

/** Asia/Seoul 기준 오늘 날짜(YYYY-MM-DD). 하루 한도 리셋 기준. */
function todayInSeoul() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul" }).format(
    new Date()
  );
}

/**
 * 무료 등급의 하루 스캔 한도를 확인하고, 통과하면 원자적으로 1 증가시킨다.
 * 구독(subscribed) 등급은 무제한. 한도 초과 시 resource-exhausted를 던진다.
 */
async function consumeNutritionScanQuota(uid) {
  const db = admin.firestore();
  const quotaRef = db.collection(NUTRITION_SCAN_QUOTA_COLLECTION).doc(uid);
  const today = todayInSeoul();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(quotaRef);
    const data = snap.exists ? snap.data() : {};
    const tier = data.tier === "subscribed" ? "subscribed" : "free";
    if (tier === "subscribed") return;

    const count = data.scanDate === today ? data.scanCount || 0 : 0;
    if (count >= FREE_DAILY_SCAN_LIMIT) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `무료 이용은 하루 ${FREE_DAILY_SCAN_LIMIT}회까지예요. 내일 다시 시도해 주세요.`
      );
    }

    tx.set(
      quotaRef,
      { tier, scanDate: today, scanCount: count + 1 },
      { merge: true }
    );
  });
}

function extractGeminiJsonText(data) {
  const parts = data?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return null;
  const text = parts
    .map((p) => (typeof p?.text === "string" ? p.text : ""))
    .join("")
    .trim();
  return text || null;
}

function parseGeminiJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start < 0 || end <= start) return null;
    try {
      return JSON.parse(text.slice(start, end + 1));
    } catch (_) {
      return null;
    }
  }
}

/**
 * 영양성분표 사진을 Gemini 2.5 Flash-Lite로 구조화 추출한다.
 *
 * data: { imageBase64: string, mimeType?: string }
 * 로그인 사용자만 호출 가능하고, 정식 앱(App Check 통과)에서만 호출 가능
 * (비용 남용 방지). App Check 미통과 요청은 여기 도달하기 전에 거부된다.
 * free 등급은 하루 [FREE_DAILY_SCAN_LIMIT]회로 제한(consumeNutritionScanQuota).
 */
exports.parseNutritionLabel = functions
  .region("asia-northeast3")
  .runWith({ timeoutSeconds: 60, memory: "512MB", enforceAppCheck: true })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }

    const imageBase64 = (
      data?.imageBase64 ??
      data?.data?.imageBase64 ??
      ""
    )
      .toString()
      .replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, "")
      .replace(/\s+/g, "");
    if (!imageBase64) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "이미지 데이터가 없습니다."
      );
    }

    const approxBytes = Math.floor((imageBase64.length * 3) / 4);
    if (approxBytes > MAX_IMAGE_BYTES) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "이미지가 너무 큽니다. 다시 촬영해 주세요."
      );
    }

    let mimeType = (
      data?.mimeType ??
      data?.data?.mimeType ??
      "image/jpeg"
    )
      .toString()
      .trim()
      .toLowerCase();
    if (!["image/jpeg", "image/jpg", "image/png", "image/webp"].includes(mimeType)) {
      mimeType = "image/jpeg";
    }
    if (mimeType === "image/jpg") mimeType = "image/jpeg";

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "GEMINI_API_KEY가 Functions 환경변수에 없습니다."
      );
    }

    await consumeNutritionScanQuota(context.auth.uid);

    const started = Date.now();
    try {
      const response = await axios.post(
        `${GEMINI_URL}?key=${encodeURIComponent(apiKey)}`,
        {
          contents: [
            {
              role: "user",
              parts: [
                { text: NUTRITION_LABEL_PROMPT },
                {
                  // REST JSON은 camelCase / snake_case 모두 허용되는 경우가 많아
                  // Google AI 문서·클라이언트와 맞춘 camelCase를 쓴다.
                  inlineData: {
                    mimeType: mimeType,
                    data: imageBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0,
            responseMimeType: "application/json",
          },
        },
        {
          timeout: 45000,
          headers: { "Content-Type": "application/json" },
          validateStatus: () => true,
        }
      );

      if (response.status >= 400) {
        const apiMsg =
          response.data?.error?.message ||
          response.data?.message ||
          `HTTP ${response.status}`;
        console.error("Gemini 영양성분표 인식 실패:", {
          status: response.status,
          apiMsg,
        });
        throw new functions.https.HttpsError(
          "internal",
          `영양성분표 인식에 실패했습니다: ${apiMsg}`
        );
      }

      const jsonText = extractGeminiJsonText(response.data);
      const parsed = parseGeminiJson(jsonText);
      if (!parsed || typeof parsed !== "object") {
        console.error("Gemini 응답 JSON 파싱 실패:", {
          preview: jsonText?.slice(0, 300),
        });
        throw new functions.https.HttpsError(
          "internal",
          "영양성분표 인식 결과를 해석하지 못했습니다."
        );
      }

      const usage = response.data?.usageMetadata;
      console.log("[timing] parseNutritionLabel", {
        uid: context.auth.uid,
        ms: Date.now() - started,
        promptTokens: usage?.promptTokenCount,
        outputTokens: usage?.candidatesTokenCount,
        totalTokens: usage?.totalTokenCount,
      });

      return { ok: true, reading: parsed };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("parseNutritionLabel 예외:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "internal",
        `영양성분표 인식 중 문제가 발생했습니다: ${
          error?.message ?? "unknown"
        }`
      );
    }
  });

// --- 하루 기록 리마인더 (매일 저녁 8시, 서버가 기록 여부를 직접 확인) -----

const FCM_SEND_CHUNK_SIZE = 500; // admin.messaging().sendEach 1회 상한

/** 서버 시각과 무관하게 Asia/Seoul 기준 "YYYY-MM-DD" 키를 만든다.
 * lib/firestore_service.dart의 dateStorageKey()와 형식을 맞춰야 한다. */
function seoulDateKey(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const map = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${map.year}-${map.month}-${map.day}`;
}

/** entries 중 하나라도 foods가 비어있지 않으면 그날 기록이 있는 것으로 본다. */
function mealDocHasRecord(data) {
  const entries = data?.entries;
  if (!Array.isArray(entries)) return false;
  return entries.some(
    (m) => Array.isArray(m?.foods) && m.foods.length > 0
  );
}

/**
 * 매일 저녁 8시(Asia/Seoul), "하루 기록 리마인더"를 켜둔 사용자 중
 * 그날 식사 기록이 없는 사람에게만 FCM 푸시를 보낸다.
 * 로컬 알림이 아니라 서버가 직접 판단하므로, 앱을 그날 한 번도 열지 않았거나
 * 다른 기기로 기록했어도 정확하게 동작한다.
 */
exports.sendDailyReminderPush = functions
  .region("asia-northeast3")
  .pubsub.schedule("every day 20:00")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    const db = admin.firestore();
    const todayKey = seoulDateKey(new Date());

    const usersSnap = await db
      .collection("users")
      .where("dailyReminderEnabled", "==", true)
      .get();

    if (usersSnap.empty) {
      console.log("하루 기록 리마인더: 대상 사용자 없음");
      return null;
    }

    const messages = [];

    await Promise.all(
      usersSnap.docs.map(async (userDoc) => {
        const tokens = userDoc.data().fcmTokens;
        if (!Array.isArray(tokens) || tokens.length === 0) return;

        const mealDoc = await userDoc.ref
          .collection("meals")
          .doc(todayKey)
          .get();
        if (mealDoc.exists && mealDocHasRecord(mealDoc.data())) return;

        for (const token of tokens) {
          messages.push({
            token,
            notification: {
              title: "CalCal",
              body: "오늘 식사 기록하셨나요?",
            },
          });
        }
      })
    );

    if (messages.length === 0) {
      console.log("하루 기록 리마인더: 이미 다 기록해서 보낼 알림 없음");
      return null;
    }

    const staleTokens = [];
    for (let i = 0; i < messages.length; i += FCM_SEND_CHUNK_SIZE) {
      const chunk = messages.slice(i, i + FCM_SEND_CHUNK_SIZE);
      const response = await admin.messaging().sendEach(chunk);
      response.responses.forEach((res, idx) => {
        if (res.success) return;
        const code = res.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          staleTokens.push(chunk[idx].token);
        } else {
          console.error("FCM 발송 실패:", res.error?.message ?? res.error);
        }
      });
    }

    if (staleTokens.length > 0) {
      await Promise.all(
        usersSnap.docs.map((userDoc) => {
          const tokens = userDoc.data().fcmTokens || [];
          const toRemove = tokens.filter((t) => staleTokens.includes(t));
          if (toRemove.length === 0) return null;
          return userDoc.ref.update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...toRemove),
          });
        })
      );
    }

    console.log(
      `하루 기록 리마인더 발송 완료: ${messages.length}건, 만료 토큰 정리: ${staleTokens.length}건`
    );
    return null;
  });

/**
 * 구독(Pro) 결제-uid 매핑용 appAccountToken(UUID) 발급.
 * StoreKit2 구매 요청에 이 토큰을 실어 보내면, App Store Server
 * Notifications 웹훅이 어떤 uid의 구독인지 역추적할 수 있다(appAccountTokens
 * 인덱스). 이미 발급된 토큰이 있으면 그대로 재사용(멱등)한다.
 */
exports.getOrCreateAppAccountToken = functions
  .region("asia-northeast3")
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }
    const uid = context.auth.uid;
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);

    try {
      const token = await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        const existing = userSnap.exists
          ? userSnap.data().appAccountToken
          : null;
        if (existing) return existing;

        const newToken = crypto.randomUUID();
        tx.set(
          userRef,
          { appAccountToken: newToken },
          { merge: true }
        );
        tx.set(db.collection("appAccountTokens").doc(newToken), {
          uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return newToken;
      });

      return { appAccountToken: token };
    } catch (error) {
      console.error("appAccountToken 발급 실패:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "internal",
        "구독 준비 중 문제가 발생했습니다."
      );
    }
  });

// --- 구독(Pro) 검증: App Store Server API / Notifications V2 ---
//
// 이 앱의 번들 ID. App Store Connect에 등록한 값과 반드시 일치해야 하며,
// SignedDataVerifier가 이 값과 다른 앱의 트랜잭션을 자동으로 거부한다.
const APP_STORE_BUNDLE_ID = "com.kyom.calCalApp";

function appStoreEnvironment() {
  // 배포 전 실기기 테스트는 전부 Sandbox. 프로덕션 심사 통과 후에만
  // APP_STORE_ENVIRONMENT=production으로 바꾼다(잘못 바꾸면 실제 결제
  // 트랜잭션 검증이 전부 실패한다).
  return process.env.APP_STORE_ENVIRONMENT === "production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
}

/**
 * 애플 루트 인증서(DER, .cer)를 functions/certs/에서 읽어온다.
 * https://www.apple.com/certificateauthority/ 에서 다운로드해 넣어야 한다
 * (AppleRootCA-G3.cer 등). 아직 준비되지 않았다면 여기서 명확한 에러로 막는다.
 */
function loadAppleRootCertificates() {
  const certsDir = path.join(__dirname, "certs");
  if (!fs.existsSync(certsDir)) {
    throw new Error(
      "functions/certs/ 가 없습니다. https://www.apple.com/certificateauthority/ 에서 " +
        "애플 루트 인증서(.cer)를 받아 그 폴더에 넣어주세요."
    );
  }
  const files = fs
    .readdirSync(certsDir)
    .filter((f) => f.toLowerCase().endsWith(".cer"));
  if (files.length === 0) {
    throw new Error("functions/certs/에 .cer 파일이 없습니다.");
  }
  return files.map((f) => fs.readFileSync(path.join(certsDir, f)));
}

function createSignedDataVerifier() {
  return new SignedDataVerifier(
    loadAppleRootCertificates(),
    true, // enableOnlineChecks: 인증서 폐기 여부까지 온라인으로 확인
    appStoreEnvironment(),
    APP_STORE_BUNDLE_ID
  );
}

/** Secret Manager에 보관한 In-App Purchase 키(Issuer ID/Key ID/.p8)로 클라이언트 생성. */
function createAppStoreServerAPIClient() {
  const issuerId = process.env.APP_STORE_ISSUER_ID;
  const keyId = process.env.APP_STORE_KEY_ID;
  const signingKey = process.env.APP_STORE_PRIVATE_KEY;
  if (!issuerId || !keyId || !signingKey) {
    throw new Error(
      "APP_STORE_ISSUER_ID / APP_STORE_KEY_ID / APP_STORE_PRIVATE_KEY가 " +
        "설정되지 않았습니다. Secret Manager에 값을 넣었는지 확인하세요."
    );
  }
  return new AppStoreServerAPIClient(
    // Secret Manager에 .p8 내용을 한 줄로 넣었을 경우를 대비해 \n을 복원.
    signingKey.replace(/\\n/g, "\n"),
    keyId,
    issuerId,
    APP_STORE_BUNDLE_ID,
    appStoreEnvironment()
  );
}

/**
 * 검증된 트랜잭션(JWSTransactionDecodedPayload)으로 subscriptions/{uid}를 갱신한다.
 * appAccountToken -> uid 역방향 인덱스(appAccountTokens)로 소유자를 찾는다.
 * 토큰이 없거나 매핑을 못 찾으면 아무도 갱신하지 않고 로그만 남긴다 —
 * 여기서 uid를 함부로 추측해 잘못된 유저에게 Pro를 부여하면 안 되기 때문이다.
 */
async function upsertSubscriptionFromTransaction(payload) {
  const token = payload.appAccountToken;
  if (!token) {
    console.warn("트랜잭션에 appAccountToken이 없어 uid를 찾을 수 없음", {
      transactionId: payload.transactionId,
    });
    return null;
  }

  const db = admin.firestore();
  const mappingSnap = await db
    .collection("appAccountTokens")
    .doc(token)
    .get();
  if (!mappingSnap.exists) {
    console.warn("appAccountToken에 대응하는 uid 매핑을 찾지 못함", { token });
    return null;
  }
  const uid = mappingSnap.data().uid;

  const isRevoked = Boolean(payload.revocationDate);
  const expiresAt = payload.expiresDate
    ? admin.firestore.Timestamp.fromMillis(payload.expiresDate)
    : null;
  // 유예기간(billing retry)은 일부러 Pro로 안 쳐준다 — 결제가 실제로
  // 안 된 상태이므로. 필요해지면 이 조건만 바꾸면 된다.
  const isPro = !isRevoked && !!expiresAt && expiresAt.toMillis() > Date.now();

  await db
    .collection("subscriptions")
    .doc(uid)
    .set(
      {
        isPro,
        productId: payload.productId ?? null,
        originalTransactionId: payload.originalTransactionId ?? null,
        expiresAt,
        store: "appstore",
        environment: payload.environment ?? null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  console.log("구독 상태 갱신", { uid, isPro, productId: payload.productId });
  return uid;
}

/**
 * 클라이언트가 StoreKit2 결제 직후 호출. transactionId로 App Store Server
 * API에서 서명된 트랜잭션을 받아 검증하고, appAccountToken이 호출자 본인
 * 것인지 확인한 뒤에만 subscriptions/{uid}를 갱신한다(다른 사람 transactionId를
 * 넣어 자기 계정을 Pro로 만드는 걸 막는 핵심 검사).
 */
exports.verifyPurchase = functions
  .region("asia-northeast3")
  .runWith({
    secrets: [
      "APP_STORE_ISSUER_ID",
      "APP_STORE_KEY_ID",
      "APP_STORE_PRIVATE_KEY",
    ],
  })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }
    const uid = context.auth.uid;
    const transactionId = String(data?.transactionId ?? "").trim();
    if (!transactionId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "transactionId가 필요합니다."
      );
    }

    try {
      const apiClient = createAppStoreServerAPIClient();
      const verifier = createSignedDataVerifier();

      const { signedTransactionInfo } = await apiClient.getTransactionInfo(
        transactionId
      );
      const payload = await verifier.verifyAndDecodeTransaction(
        signedTransactionInfo
      );

      if (!payload.appAccountToken) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "이 트랜잭션에는 소유자를 확인할 appAccountToken이 없습니다."
        );
      }
      const mappingSnap = await admin
        .firestore()
        .collection("appAccountTokens")
        .doc(payload.appAccountToken)
        .get();
      if (!mappingSnap.exists || mappingSnap.data().uid !== uid) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "이 트랜잭션은 현재 로그인된 사용자의 구매가 아닙니다."
        );
      }

      await upsertSubscriptionFromTransaction(payload);
      const subSnap = await admin
        .firestore()
        .collection("subscriptions")
        .doc(uid)
        .get();
      return { ok: true, isPro: subSnap.data()?.isPro ?? false };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("구매 검증 실패:", error?.message ?? error);
      throw new functions.https.HttpsError(
        "internal",
        "구매 검증 중 문제가 발생했습니다."
      );
    }
  });

/**
 * App Store Server Notifications V2 웹훅. 구독 갱신/해지/환불/유예 등
 * 상태가 바뀔 때마다 애플이 호출한다. App Store Connect > App Information
 * > App Store Server Notifications에 이 함수의 URL을 등록해야 한다.
 */
exports.appStoreServerNotifications = functions
  .region("asia-northeast3")
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const signedPayload = req.body?.signedPayload;
    if (!signedPayload || typeof signedPayload !== "string") {
      res.status(400).send("signedPayload가 없습니다.");
      return;
    }

    try {
      const verifier = createSignedDataVerifier();
      const notification = await verifier.verifyAndDecodeNotification(
        signedPayload
      );

      const signedTransactionInfo = notification.data?.signedTransactionInfo;
      if (signedTransactionInfo) {
        const payload = await verifier.verifyAndDecodeTransaction(
          signedTransactionInfo
        );
        await upsertSubscriptionFromTransaction(payload);
      } else {
        console.log("트랜잭션 정보 없는 알림 수신", {
          type: notification.notificationType,
          subtype: notification.subtype,
        });
      }

      res.status(200).send("OK");
    } catch (error) {
      // 검증 실패(위조 등)든 우리 쪽 일시 장애든 5xx로 응답해 애플이 재시도하게
      // 둔다 — 200을 잘못 돌려주면 애플이 재전송을 멈춰 상태가 영영 안 바뀐다.
      console.error("App Store 알림 처리 실패:", error?.message ?? error);
      res.status(500).send("Internal Error");
    }
  });
