# Build Guide — Customer Segmentation (PostgreSQL + K-means)

Do the steps in order. Each step has a ✅ checkpoint: if your numbers match, move on. If they don't, the problem is in that step.
Expect 6–10 hours over a few sessions.

---

## Step 0 — Install (once)

| Tool | Why | Notes |
|---|---|---|
| **PostgreSQL 16** (EDB installer for Windows) | The database | The installer includes **pgAdmin 4**. Remember the password you set for the `postgres` user. Keep port 5432. |
| **Python 3.11+** | Data conversion and clustering | Tick "Add Python to PATH" during install. |
| **VS Code** + the **Jupyter** extension | Running the notebook | Or use Anaconda / JupyterLab if you prefer. |

Then open a terminal in the project folder and run:
```
pip install -r requirements.txt
```

---

## Step 1 — Get the data

1. Download **Online Retail II** from the UCI Machine Learning Repository (dataset 502). The file is `online_retail_II.xlsx` (about 44 MB, 2 sheets: 2009–2010 and 2010–2011).
2. Put it in `data/`.
3. Convert both sheets into one CSV:
   ```
   python scripts/xlsx_to_csv.py data/online_retail_II.xlsx data/online_retail_II.csv
   ```

✅ **Checkpoint:** the script prints `Wrote 1,067,371 rows`.

> Don't open the CSV in Excel and save it. Excel changes the date format and breaks the import.

---

## Step 2 — Create the database and load the raw data

1. Open **pgAdmin 4** → Servers → PostgreSQL 16 → right-click **Databases** → **Create → Database** → name `customer_segmentation` → Save.
2. Click the new database → **Tools → Query Tool**.
3. Open `sql/01_setup_and_load.sql` (folder icon in the Query Tool) → run it (F5). It creates the `retail` schema and the empty `retail.raw_transactions` table.
4. Load the CSV: in the left panel, expand **customer_segmentation → Schemas → retail → Tables** (press F5 on Tables to refresh if needed) → right-click **raw_transactions** → **Import/Export Data**:
   - **Import**, Filename: your `online_retail_II.csv`, Format: **csv**, Encoding: **UTF8**
   - **Options** tab: **Header ON**, Delimiter `,`, Quote `"`
   - OK. Wait for "Process completed".
5. Run `SELECT COUNT(*) FROM retail.raw_transactions;`

✅ **Checkpoint:** 1,067,371

**Why load everything as TEXT first?** It's a staging table, so a single bad value can never stop the import. Types are fixed in a controlled step later.

---

## Step 3 — Data quality audit

Run `sql/02_data_quality.sql`. Screenshot the results for your README.

✅ **Checkpoint (query 2.1):**

| Check | Rows |
|---|---|
| Total rows | 1,067,371 |
| Missing customer_id | 243,007 |
| Missing description | 4,382 |
| Cancellation rows (C...) | 19,494 |
| Bad-debt adjustments (A...) | 6 |
| Quantity <= 0 | 22,950 |
| Price <= 0 | 6,207 |
| Exact duplicate rows | 34,335 |

Query 2.3 shows the most interesting rows in the dataset: an **80,995-unit order cancelled 12 minutes later**. This is why cancellations must be netted off, not just deleted.

---

## Step 4 — Clean

Run `sql/03_clean.sql`. It creates `retail.transactions`.

✅ **Checkpoint:**

| clean_rows | customers | purchase_invoices | cancellation_rows | net_revenue_gbp |
|---|---|---|---|---|
| 794,165 | 5,875 | 36,594 | 17,586 | 16,358,629 |

---

## Step 5 — Exploratory analysis

Run `sql/04_eda.sql` one query at a time (highlight a query, then F5). Each one answers a business question.

✅ **Checkpoints:**
- **Q1:** 5,875 customers · 36,594 orders · net revenue £16,358,629 · cancel rate 4.2% · AOV £466.43
- **Q2:** Nov 2010 £1,121,081 and Nov 2011 £1,113,102 are the peak months
- **Q3:** UK = 83.5% of revenue; EIRE is #2 with only **3 customers**
- **Q5:** the top 10% of customers = **63.3%** of revenue
- **Q6:** 27.6% of customers bought only once
- **Q7:** the Dec 2009 cohort has 951 customers (it includes customers who existed before the data starts, which is why its retention looks so high)

---

## Step 6 — RFM features and segments

Run `sql/05_rfm.sql`. It creates `retail.customer_rfm`.

✅ **Checkpoint:** 5,832 customers. Segment summary, top rows:

| rfm_segment | customers | pct_customers | pct_revenue |
|---|---|---|---|
| Champions | 1,385 | 23.7 | 69.4 |
| Loyal | 466 | 8.0 | 9.8 |
| At Risk | 655 | 11.2 | 5.6 |

**Why 5,832 and not 5,875?** 43 customers have zero or negative net spend (everything they bought was cancelled), so they're excluded.

---

## Step 7 — Clustering notebook

1. Open `notebooks/customer_clustering.ipynb` in VS Code.
2. In the first code cell, change `PASSWORD = "your_password"` to your PostgreSQL password.
3. **Run All.**

✅ **Checkpoints:**
- Section 2 prints `5,832 customers`
- Section 4: silhouette ≈ 0.44 (k = 2), 0.35 (k = 3), **0.37 (k = 4)**, 0.34 (k = 5)
- Section 5:

| Cluster | Customers | Median recency | Median orders | Median spend | % revenue |
|---|---|---|---|---|---|
| VIP | 1,190 | 17 | 13 | £4,808 | 73.7% |
| Recent Developing | 1,250 | 24 | 3 | £703 | 6.2% |
| At-Risk Regulars | 1,438 | 183 | 5 | £1,435 | 16.4% |
| Lost One-Timers | 1,954 | 402 | 1 | £267 | 3.7% |

K-means can vary very slightly between scikit-learn versions. If your counts differ by a handful of customers, that's fine. The names stay correct because they're assigned by rules, not by cluster number.

The charts are saved to `images/`, ready for the README.

---

## Step 8 — Analyse the clusters in SQL

The notebook wrote `retail.customer_clusters` back to PostgreSQL. Run `sql/06_cluster_analysis.sql`.

✅ **Checkpoint (6.4):** 1,438 at-risk customers · £2,678,923 lifetime revenue · **734 still recoverable** (last order 90–365 days ago) with £1,331,900 lifetime spend.

Query 6.5 is a **win-back list**: the top 20 recoverable customers by spend. That's the kind of output a marketing team can act on the same day.

---

## Step 9 — Write the insights

Fill in the "Key Insights" in the README using **finding → evidence → recommendation**. Questions to answer:
1. How concentrated is revenue? What does that mean for risk?
2. What does the RFM vs cluster heatmap reveal about the "Loyal" segment?
3. How much revenue sits with At-Risk Regulars, and how many can still be saved?
4. Which cluster grows in Q4, and what should happen in January?
5. Why might rule-based RFM and K-means disagree, and which would you trust for which decision?

---

## Step 10 — Publish

1. Screenshots of the SQL results (audit, EDA, segment summary) → `images/`.
2. Push to GitHub: everything **except** `data/*.xlsx` and `data/*.csv` (already in `.gitignore`).
3. In the notebook, make sure all outputs and charts are saved (Run All, then Save) so GitHub shows them.
