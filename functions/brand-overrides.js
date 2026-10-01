/**
 * 식약처 DB의 제조사명(MAKER_NM)이 사람들이 아는 브랜드명과 다를 때 쓰는 목록.
 * 정리 로직은 index.js에 있고, 여기에는 규칙과 예외 테이블만 둔다.
 */

/**
 * 법인 표기 잡음 제거용 접미/접두 패턴.
 * 예: "(주)오뚜기" → "오뚜기", "농심주식회사" → "농심"
 */
const CORPORATE_MARKERS = [
  /\(주\)/g,
  /㈜/g,
  /\(유\)/g,
  /주식회사/g,
  /유한회사/g,
  /유한책임회사/g,
  /합자회사/g,
  /합명회사/g,
  /영농조합법인/g,
  /협동조합/g,
  /co\.?,?\s*ltd\.?/gi,
  /corp\.?/gi,
  /inc\.?/gi,
];

/**
 * 위탁생산(OEM)이 흔한 음료·과자류는 같은 브랜드 제품도 생산 시점마다
 * MAKER_NM이 다른 공장/포장업체로 갈린다(예: "닥터유" 제품이 "오리온
 * 제3익산공장" / "삼양패키징" / "서울에프엔비" 등으로 제각각 표시).
 * MAKER_NM 기준 예외 테이블로는 감당이 안 되므로, 상품명 자체에 박혀있는
 * 브랜드 키워드를 최우선으로 매칭한다 — 제조원이 몇 개든 항상 같은
 * 브랜드로 통일된다.
 *
 * 정렬 규칙: 구체적인 하위 브랜드를 위에, 포괄적인 브랜드를 아래에 둔다
 * (먼저 매치된 항목이 채택됨).
 */
const BRAND_KEYWORDS = [
  { keyword: '닥터유', brand: '오리온' },
];

/**
 * 제조사명이 실제 브랜드명과 아예 다른 경우(지주회사/계열사명, 하위
 * 브랜드명 등)의 수동 매핑. 정규화된 키(공백 제거, 원문 그대로) → 실제
 * 노출할 브랜드명. 발견되는 대로 한 줄씩 추가한다.
 */
const BRAND_OVERRIDES = {};

/**
 * 브랜드가 아니라 제조원(공장/위탁생산업체/물류)임을 나타내는 흔한 접미어.
 * 법인 표기 제거 후에도 이 패턴에 걸리면 브랜드로 노출하지 않는다 —
 * 틀린 이름을 보여주는 것보다 안 보여주는 게 낫다는 원칙.
 */
const FACTORY_SUFFIX_MARKERS = [
  /제\s*\d+\s*공장/,
  /공장/,
  /패키징/,
  /에프(앤|엔)비/,
  /음료$/,
  /가공/,
  /물류/,
  /oem/i,
];

function normalizeKey(name) {
  return String(name ?? '')
    .trim()
    .replace(/\s+/g, '');
}

/** index.js의 stripForMatch와 동일한 정규화. 이 파일은 독립 모듈로 유지하기 위해 자체 구현. */
function normalizeForMatch(s) {
  return String(s ?? '')
    .normalize('NFC')
    .toLowerCase()
    .replace(/[^\p{Script=Hangul}\p{Script=Latin}0-9]/gu, '');
}

function stripCorporateSuffix(name) {
  let result = String(name ?? '');
  for (const pattern of CORPORATE_MARKERS) {
    result = result.replace(pattern, '');
  }
  return result.replace(/\s+/g, ' ').trim();
}

function findBrandKeyword(foodName) {
  const nameNorm = normalizeForMatch(foodName);
  if (!nameNorm) return '';
  const hit = BRAND_KEYWORDS.find((row) =>
    nameNorm.includes(normalizeForMatch(row.keyword))
  );
  return hit ? hit.brand : '';
}

function looksLikeFactoryName(name) {
  return FACTORY_SUFFIX_MARKERS.some((pattern) => pattern.test(name));
}

/**
 * 상품명·제조사명으로부터 화면에 노출할 브랜드명을 계산.
 * 1) 상품명에 알려진 브랜드 키워드가 있으면 최우선 채택(제조원 무관하게 일관).
 * 2) 없으면 제조사명 예외 테이블 조회.
 * 3) 없으면 법인 표기만 제거.
 * 4) 그 결과가 의미 없는 값이거나 공장/OEM처럼 보이면 브랜드 미표시.
 */
function brandDisplayNameOf({ foodName, makerNm } = {}) {
  const keywordBrand = findBrandKeyword(foodName);
  if (keywordBrand) return keywordBrand;

  const raw = String(makerNm ?? '').trim();
  if (!raw) return '';

  const overrideHit = BRAND_OVERRIDES[normalizeKey(raw)];
  if (overrideHit) return overrideHit;

  const cleaned = stripCorporateSuffix(raw);
  if (!cleaned || cleaned === '-' || cleaned.toLowerCase() === 'null') {
    return '';
  }
  if (looksLikeFactoryName(cleaned)) return '';
  return cleaned;
}

module.exports = {
  BRAND_KEYWORDS,
  BRAND_OVERRIDES,
  stripCorporateSuffix,
  brandDisplayNameOf,
};
