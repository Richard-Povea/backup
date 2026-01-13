import sys

def read_args():
    args = sys.argv[1]
    return args

def get_folder_number(code: str) -> int:
    code_numbrer = [s for s in code if s.isdigit()]
    folder_number = int("".join(code_numbrer))
    return folder_number

def get_folder_range(folder_number: int) -> str:
    start_range = (folder_number // 100) * 100
    end_range = start_range + 99
    folder_range = f"{start_range} - {end_range}"
    return folder_range

def get_folder_id(folder_number: int) -> int:
    folder_id = (folder_number // 100)-6
    return folder_id

def make_folder_name(code: str) -> str:
    folder_number = get_folder_number(code)
    fodler_range = get_folder_range(folder_number)
    folder_id = get_folder_id(folder_number)
    folder_name = f"{folder_id}. {fodler_range}"
    return folder_name

def main():
    code = read_args()
    print(make_folder_name(code))

if __name__ == "__main__":
    main()
