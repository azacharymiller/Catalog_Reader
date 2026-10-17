-- Keeneland November 2026 (catalog file 133): one pipe-delimited line per hip.
-- Replace {LO} and {HI} with the hip range. The last SELECT returns the
-- payload and its MD5 so a saved copy can be verified byte for byte.
-- Columns: hip|book|session|name|sire|dam|damsire|sex|crop|foaling_date|
--   consignor|sold_as|covering_sire|bc_eligible|agent_score|agent_tier|
--   female_line|sire_pct_sw|sire_graded_winners|sire_fee|band_q1|band_median|
--   band_q3|band_count|band_year|cover_band_median|cover_band_count|
--   produce_sold|produce_median
WITH h AS (SELECT * FROM v_catalog_hips WHERE sale_id='KEE_FILE_133' AND hip BETWEEN {LO} AND {HI}),
a AS (SELECT CAST(split_part(subject_id,'|',2) AS INT) hip, composite, tier, c_female_line FROM v_agent_score_catalog WHERE grp='KEE_FILE_133'),
mc AS (SELECT upper(sire) usire, age_at_sale, q1, median_price, q3, n_sold, sale_year FROM v_market_context WHERE house ILIKE '%keeneland%' AND sale_year < 2026 QUALIFY row_number() OVER (PARTITION BY upper(sire), age_at_sale ORDER BY sale_year DESC)=1),
pr AS (SELECT upper(dam) udam, upper(dam_sire) uds, count(*) FILTER (WHERE sale_result='sold') n_sold, median(sold_price) FILTER (WHERE sale_result='sold') med FROM v_produce GROUP BY ALL),
sr AS (SELECT upper(sire) usire, any_value(pct_stakes_winners) pct, any_value(graded_winners) gw, any_value(current_fee) fee FROM v_sire_record GROUP BY 1),
r AS (
SELECT h.hip AS hipno, concat_ws('|', h.hip, h.book, h.session, coalesce(h.horse,''), h.sire, h.dam, coalesce(h.damsire,''), coalesce(h.sex,''), coalesce(CAST(h.crop AS VARCHAR),''), coalesce(CAST(h.foaling_date AS VARCHAR),''), coalesce(h.consignor,''), coalesce(h.sold_as,''), coalesce(h.covering_sire,''), coalesce(h.bc_eligible,''),
 coalesce(CAST(round(a.composite,1) AS VARCHAR),''), coalesce(a.tier,''), coalesce(CAST(a.c_female_line AS VARCHAR),''),
 coalesce(CAST(sr.pct AS VARCHAR),''), coalesce(CAST(sr.gw AS VARCHAR),''), coalesce(CAST(sr.fee AS VARCHAR),''),
 coalesce(CAST(mc.q1 AS VARCHAR),''), coalesce(CAST(mc.median_price AS VARCHAR),''), coalesce(CAST(mc.q3 AS VARCHAR),''), coalesce(CAST(mc.n_sold AS VARCHAR),''), coalesce(CAST(mc.sale_year AS VARCHAR),''),
 coalesce(CAST(cv.median_price AS VARCHAR),''), coalesce(CAST(cv.n_sold AS VARCHAR),''),
 coalesce(CAST(pr.n_sold AS VARCHAR),''), coalesce(CAST(pr.med AS VARCHAR),'')) AS line
FROM h LEFT JOIN a USING (hip)
LEFT JOIN sr ON sr.usire=upper(h.sire)
LEFT JOIN mc ON mc.usire=upper(h.sire) AND mc.age_at_sale = 0 AND h.crop=2026
LEFT JOIN mc cv ON cv.usire=upper(h.covering_sire) AND cv.age_at_sale = 0
LEFT JOIN pr ON pr.udam=upper(h.dam) AND pr.uds=upper(h.damsire))
SELECT count(*) AS n, md5(string_agg(line, chr(10) ORDER BY hipno)) AS md5, string_agg(line, chr(10) ORDER BY hipno) AS payload FROM r
