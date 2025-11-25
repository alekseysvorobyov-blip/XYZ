-- ============================================================================
-- СКРИПТЫ ОБСЛУЖИВАНИЯ БД
-- ============================================================================

-- VACUUM и ANALYZE для конкретных партиций
VACUUM FULL ANALYZE part_ksk_result_2025_10_21;
VACUUM FULL ANALYZE part_ksk_result_2025_10_22;
VACUUM FULL ANALYZE part_ksk_result_2025_10_23;

VACUUM FULL ANALYZE part_ksk_figurant_2025_10_21;
VACUUM FULL ANALYZE part_ksk_figurant_2025_10_22;
VACUUM FULL ANALYZE part_ksk_figurant_2025_10_23;

VACUUM FULL ANALYZE part_ksk_figurant_match_2025_10_21;
VACUUM FULL ANALYZE part_ksk_figurant_match_2025_10_22;
VACUUM FULL ANALYZE part_ksk_figurant_match_2025_10_23;

-- VACUUM и ANALYZE для всех таблиц
VACUUM (VERBOSE) ksk_result;
VACUUM (VERBOSE) ksk_figurant;
VACUUM (VERBOSE) ksk_figurant_match;

ANALYZE ksk_result;
ANALYZE ksk_figurant;
ANALYZE ksk_figurant_match;
