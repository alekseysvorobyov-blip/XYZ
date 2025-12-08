-- Убедитесь, что стратегия хранения EXTENDED (должна быть по умолчанию)
-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_result
   ALTER COLUMN input_json SET STORAGE EXTENDED,
   ALTER COLUMN output_json SET STORAGE EXTENDED,
   ALTER COLUMN input_kafka_headers SET STORAGE EXTENDED,
   ALTER COLUMN output_kafka_headers SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_result 
    ALTER COLUMN input_json SET COMPRESSION lz4,
    ALTER COLUMN output_json SET COMPRESSION lz4,
    ALTER COLUMN input_kafka_headers SET COMPRESSION lz4,
    ALTER COLUMN output_kafka_headers SET COMPRESSION lz4;

-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_figurant
   ALTER COLUMN figurant SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_figurant 
    ALTER COLUMN figurant SET COMPRESSION lz4;

-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_figurant_match
   ALTER COLUMN match SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_figurant_match 
    ALTER COLUMN match SET COMPRESSION lz4;

