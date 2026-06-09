import json
import sys
from pathlib import Path

def process_json(input_file, output_file):
    # 读取原始 JSON 文件
    with open(input_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 遍历并拆分 ums_st_ed
    for item in data:
        if "ums_st_ed" in item and len(item["ums_st_ed"]) == 4:
            ums_st, ums_ed, psg_st, psg_ed = item["ums_st_ed"]
            item["ums_st"] = ums_st
            item["ums_ed"] = ums_ed
            item["psg_st"] = psg_st
            item["psg_ed"] = psg_ed
            del item["ums_st_ed"]

    # 保存新的 JSON 文件
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"✅ 处理完成，新文件已保存到: {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python process_json.py 输入文件.json 输出文件.json")
    else:
        input_path = Path(sys.argv[1])
        output_path = Path(sys.argv[2])
        process_json(input_path, output_path)