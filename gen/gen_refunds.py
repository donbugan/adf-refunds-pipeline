"""Synthetic Jotform-style export of store card-refund requests, plus an answer key.

Every name, phone number, store and amount is invented. Card data is masked by design:
only the first 6 and last 4 digits are ever generated, never a full card number.
Seeded, so reruns produce identical files.
"""
import csv, os, random
from datetime import date, datetime, time, timedelta

random.seed(20261027)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data")
AS_OF = date(2026, 10, 27)

# South African public holidays that fall on a weekday in 2026 (9 Aug is a Sunday, observed Monday 10 Aug)
HOLIDAYS = {date(2026, 1, 1), date(2026, 4, 3), date(2026, 4, 6), date(2026, 4, 27), date(2026, 5, 1),
            date(2026, 6, 16), date(2026, 8, 10), date(2026, 9, 24), date(2026, 12, 16), date(2026, 12, 25)}

def is_bd(d):
    return d.weekday() < 5 and d not in HOLIDAYS

def add_bd(d, n):
    while n > 0:
        d += timedelta(days=1)
        if is_bd(d):
            n -= 1
    return d

def bd_between(a, b):
    """Business days after a, up to and including b (the rule the SQL uses)."""
    n, d = 0, a
    while d < b:
        d += timedelta(days=1)
        if is_bd(d):
            n += 1
    return n

AREAS = {"AC Nomvula Dlamini": ["Bellville", "Durbanville", "Parow", "Goodwood", "Kuils River"],
         "AC Pieter Botha": ["Claremont", "Kenilworth", "Wynberg", "Constantia", "Tokai"],
         "AC Fatima Adams": ["Athlone", "Mitchells Plain", "Rondebosch", "Observatory", "Salt River"],
         "AC Johan Smit": ["Somerset West", "Stellenbosch", "Paarl", "Strand", "Gordons Bay"]}
STORES = []
k = 100
for ac, names in AREAS.items():
    for n in names:
        STORES.append((f"ST{k} {n}", ac)); k += 1
FIRST = ["Thabo", "Aisha", "Megan", "Sipho", "Lerato", "Ryan", "Zainab", "Kyle", "Nadia", "Bongani",
         "Chantel", "Imran", "Lindiwe", "Ashwin", "Carmen", "Musa", "Tasneem", "Jaco", "Ayanda", "Riaan"]
LAST = ["Mokoena", "Jacobs", "van Wyk", "Ndlovu", "Petersen", "Naidoo", "Daniels", "Khumalo", "Smith",
        "Hendricks", "Mahlangu", "Isaacs", "Pillay", "Fortuin", "Zulu", "Abrahams"]
REASONS = ["Duplicate transaction", "Duplicate transaction", "Duplicate transaction",
           "Amount charged incorrectly", "Transaction declined but debited", "Refund not processed at till"]
BINS = ["400115", "419570", "455672", "522114", "535316", "548002"]
CAPTURERS = ["Store manager", "Assistant manager", "Supervisor"]

def ts(d, lo=8, hi=17):
    return datetime.combine(d, time(random.randint(lo, hi - 1), random.randint(0, 59)))

rows, key = [], []
def flag(sid, kind):
    key.append({"submission_id": sid, "exception_type": kind})

N = 300
start = date(2026, 8, 3)
for i in range(1, N + 1):
    sid = f"6{random.randint(10**17, 10**18 - 1)}"
    sub_day = start + timedelta(days=random.randint(0, (AS_OF - start).days - 1))
    sub = ts(sub_day, 8, 20)
    store, ac = random.choice(STORES)
    txn = sub_day - timedelta(days=random.randint(0, 6))
    amount = round(random.choice([random.uniform(40, 900), random.uniform(900, 4500)]), 2)
    r = dict(submission_id=sid, submission_date=sub.strftime("%Y-%m-%d %H:%M:%S"), store=store, area_coach=ac,
             captured_by=random.choice(CAPTURERS), customer_name=f"{random.choice(FIRST)} {random.choice(LAST)}",
             customer_contact=f"0{random.choice([6,7,8])}{random.randint(10**7, 10**8 - 1)}",
             transaction_date=txn.isoformat(), amount=f"{amount:.2f}", reason=random.choice(REASONS),
             card_first6=random.choice(BINS), card_last4=f"{random.randint(0, 9999):04d}",
             bank_statement="statement.pdf", popia_consent="Yes",
             recon_reviewed_at="", sent_to_bank_at="", closed_at="", status="Submitted")
    # Workflow: most requests reviewed within 1-2 business days, most bank legs within 6-10
    review_bd = random.choices([1, 2, 3, 4], weights=[60, 30, 7, 3])[0]
    reviewed = add_bd(sub_day, review_bd)
    if reviewed <= AS_OF:
        r["recon_reviewed_at"] = ts(reviewed).strftime("%Y-%m-%d %H:%M:%S")
        r["sent_to_bank_at"] = r["recon_reviewed_at"]
        r["status"] = "With bank"
        bank_bd = random.choices([6, 7, 8, 9, 10, 12, 14], weights=[15, 20, 20, 15, 15, 10, 5])[0]
        closed = add_bd(reviewed, bank_bd)
        if closed <= AS_OF:
            r["closed_at"] = ts(closed).strftime("%Y-%m-%d %H:%M:%S")
            r["status"] = random.choices(["Refunded", "Declined by bank"], weights=[92, 8])[0]
    rows.append(r)

# Planted data-quality problems (beyond the SLA breaches the workflow above produces naturally)
pool = rows[:]; random.shuffle(pool)
for r in pool[0:6]:   r["bank_statement"] = ""                                   # missing statement
for r in pool[6:10]:  r["card_first6"] = r["card_first6"] + random.choice(["1", "23"])  # too many digits
for r in pool[10:13]: r["card_last4"] = "12X4"                                   # not digits
for r in pool[13:17]: r["customer_contact"] = ""                                 # no way to call back
for r in pool[17:19]: r["popia_consent"] = ""                                     # no consent
dupes = []
for r in pool[19:23]:                                                             # same refund submitted twice
    d2 = dict(r); d2["submission_id"] = f"6{random.randint(10**17, 10**18 - 1)}"
    later = datetime.strptime(r["submission_date"], "%Y-%m-%d %H:%M:%S") + timedelta(hours=random.randint(2, 30))
    d2["submission_date"] = later.strftime("%Y-%m-%d %H:%M:%S")
    d2.update(recon_reviewed_at="", sent_to_bank_at="", closed_at="", status="Submitted")
    dupes.append((r, d2))
for _, d2 in dupes:
    rows.append(d2)
bad_rows = [dict(rows[0], submission_id="", amount="450.00"),                     # blank key: reject
            dict(rows[1], submission_id=f"6{random.randint(10**17, 10**18 - 1)}", amount="R1,200"),  # bad amount: reject
            {k: "" for k in rows[0]}]                                              # blank row: reject
rows.extend(bad_rows)
random.shuffle(rows)

# Answer key, computed with the same rules the SQL applies
rejects = sum(1 for r in rows if r["submission_id"] == "" or not r["amount"].replace(".", "", 1).isdigit())
for r in rows:
    sid = r["submission_id"]
    if sid == "" or not r["amount"].replace(".", "", 1).isdigit():
        continue
    sub_day = datetime.strptime(r["submission_date"], "%Y-%m-%d %H:%M:%S").date()
    rev = r["recon_reviewed_at"]
    rev_day = datetime.strptime(rev, "%Y-%m-%d %H:%M:%S").date() if rev else None
    if bd_between(sub_day, rev_day or AS_OF) > 2:
        flag(sid, "REVIEW_SLA_BREACH")
    if r["sent_to_bank_at"]:
        bank_day = datetime.strptime(r["sent_to_bank_at"], "%Y-%m-%d %H:%M:%S").date()
        cl = r["closed_at"]
        cl_day = datetime.strptime(cl, "%Y-%m-%d %H:%M:%S").date() if cl else AS_OF
        if bd_between(bank_day, cl_day) > 10:
            flag(sid, "BANK_SLA_BREACH")
    if r["bank_statement"] == "":
        flag(sid, "MISSING_STATEMENT")
    if not (len(r["card_first6"]) == 6 and r["card_first6"].isdigit() and len(r["card_last4"]) == 4 and r["card_last4"].isdigit()):
        flag(sid, "CARD_MASK_INVALID")
    if r["customer_contact"] == "":
        flag(sid, "MISSING_CONTACT")
    if r["popia_consent"] != "Yes":
        flag(sid, "NO_POPIA_CONSENT")
for orig, d2 in dupes:
    flag(d2["submission_id"], "POSSIBLE_DUPLICATE")

HEAD = {"submission_id": "Submission ID", "submission_date": "Submission Date", "store": "Store",
        "area_coach": "Area Coach", "captured_by": "Captured By", "customer_name": "Customer Full Name",
        "customer_contact": "Customer Contact Number", "transaction_date": "Date of Transaction",
        "amount": "Amount", "reason": "Reason", "card_first6": "Card First 6 Digits",
        "card_last4": "Card Last 4 Digits", "bank_statement": "Bank Statement", "popia_consent": "POPIA Consent",
        "recon_reviewed_at": "Recon Reviewed At", "sent_to_bank_at": "Sent To Bank At",
        "closed_at": "Closed At", "status": "Status"}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "jotform_refunds_export.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(HEAD.values())
    for r in rows:
        w.writerow([r[k] for k in HEAD])
with open(os.path.join(OUT, "answer_key.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["submission_id", "exception_type"]); w.writeheader()
    w.writerows(sorted(key, key=lambda x: (x["exception_type"], x["submission_id"])))

from collections import Counter
print("rows in export:", len(rows), "| expected rejects:", rejects, "| expected merged:", len(rows) - rejects)
for k_, v in sorted(Counter(x["exception_type"] for x in key).items()):
    print(f"  {k_}: {v}")
