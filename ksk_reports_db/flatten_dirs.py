# -*- coding: utf-8 -*-
"""
Flatten nested directory structure.
Hardcoded paths - no command line arguments needed.
"""

import os
import shutil


# ========== НАСТРОЙКИ ==========
INPUT_DIR = r"D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\deepseek\ksk_reports_db\schema"
OUTPUT_DIR = r"D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\deepseek\ksk_reports_db\schema_flattern"
# ===============================


def main():
    print("=" * 80)
    print("FLATTEN DIRECTORY STRUCTURE")
    print("=" * 80)
    print()
    
    # Check input exists
    if not os.path.exists(INPUT_DIR):
        print("ОШИБКА: Входной каталог не найден!")
        print(f"Путь: {INPUT_DIR}")
        input("\nНажмите Enter...")
        return
    
    # Create output
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    print(f"Вход:  {INPUT_DIR}")
    print(f"Выход: {OUTPUT_DIR}")
    print("-" * 80)
    
    file_count = 0
    
    # Process files
    for root, dirs, files in os.walk(INPUT_DIR):
        rel_path = os.path.relpath(root, INPUT_DIR)
        
        for filename in files:
            source = os.path.join(root, filename)
            
            # Build new name
            if rel_path == '.':
                new_name = filename
            else:
                parts = rel_path.split(os.sep)
                prefix = '_'.join(parts)
                new_name = f"{prefix}_{filename}"
            
            dest = os.path.join(OUTPUT_DIR, new_name)
            
            # Copy
            try:
                shutil.copy2(source, dest)
                file_count += 1
                print(f"✓ {new_name}")
            except Exception as e:
                print(f"✗ {filename}: {e}")
    
    print("-" * 80)
    print(f"ГОТОВО! Скопировано: {file_count} файлов")
    print(f"Результат: {OUTPUT_DIR}")
    print()
    input("Нажмите Enter для выхода...")


if __name__ == '__main__':
    main()
