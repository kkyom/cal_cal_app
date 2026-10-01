/**
 * 식약처 DB 표제어가 사용자가 치는 말과 다를 때 쓰는 목록.
 * 검색 로직은 index.js에 있고, 여기에는 행만 추가하면 된다.
 */

/**
 * 대표 표제어가 없고 품종·세부명만 있는 식재료.
 *
 * queries: 사용자 검색어(공백·특수문자 무시 후 완전 일치)
 * apiName: FOOD_NM_KR 조회어이자, 결과에서 고를 정확한 DB 이름
 * displayName: 앱에 보여줄 이름. 없으면 사용자가 친 검색어
 */
const RAW_FOOD_OVERRIDES = [
  {
    queries: ["감자"],
    apiName: "감자_수미_생것",
    displayName: "감자",
  },
];

/**
 * 흔한 식재료 동의어 → 식약처 DB가 원재료 대표 표제어로 채택한 표기.
 * 예: "계란"으로 검색해도 DB엔 "달걀_생것"만 있어, 상태 접미사 전에 치환한다.
 */
const RAW_VARIANT_SYNONYMS = {
  계란: "달걀",
  쇠고기: "소고기",
  대두: "콩",
  돈육: "돼지고기",
};

module.exports = {
  RAW_FOOD_OVERRIDES,
  RAW_VARIANT_SYNONYMS,
};
