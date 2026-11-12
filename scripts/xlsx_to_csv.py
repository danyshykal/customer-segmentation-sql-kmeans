"""
Convert the UCI 'online_retail_II.xlsx' (2 sheets) into one CSV for PostgreSQL.

Usage:
    python scripts/xlsx_to_csv.py data/online_retail_II.xlsx data/online_retail_II.csv
Takes 1–3 minutes (Excel is slow to read).
"""
import sys
import pandas as pd

src, dst = sys.argv[1], sys.argv[2]
sheets = pd.read_excel(src, sheet_name=None, dtype={"Invoice": str, "StockCode": str})
df = pd.concat(sheets.values(), ignore_index=True)
df["Customer ID"] = df["Customer ID"].astype("Int64")          # 13085.0 -> 13085, blanks stay blank
df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"]).dt.strftime("%Y-%m-%d %H:%M:%S")
df = df[["Invoice", "StockCode", "Description", "Quantity", "InvoiceDate", "Price", "Customer ID", "Country"]]
df.to_csv(dst, index=False, encoding="utf-8")
print(f"Wrote {len(df):,} rows to {dst}")   # expect 1,067,371
