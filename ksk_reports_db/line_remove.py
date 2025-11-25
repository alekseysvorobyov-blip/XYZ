import os
import sys

def remove_lines_with_text(directory, target_text):
    for root, dirs, files in os.walk(directory):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                
                new_lines = [line for line in lines if target_text not in line]
                
                if len(new_lines) != len(lines):
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.writelines(new_lines)
                    print(f"Обновлен: {file_path}")
                    
            except UnicodeDecodeError:
                print(f"Пропуск бинарного файла: {file_path}")
            except Exception as e:
                print(f"Ошибка при обработке {file_path}: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Использование: python script.py <каталог> <текст>")
        sys.exit(1)
    
    directory = sys.argv[1]
    target_text = sys.argv[2]
    
    if not os.path.isdir(directory):
        print("Указанный каталог не существует")
        sys.exit(1)
    
    remove_lines_with_text(directory, target_text)
    print("Обработка завершена")