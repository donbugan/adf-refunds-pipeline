"""Cross-check of the exception rules in sql/04 against data/answer_key.csv, using DuckDB.

The T-SQL runs in Azure SQL; this is the same logic ported to DuckDB so the rules can be checked
locally without a SQL Server. Run from the repo root:  pip install duckdb && python tests/check_rules_duckdb.py
"""
import duckdb
c=duckdb.connect()
c.execute("create table s as select * from read_csv('data/jotform_refunds_export.csv', all_varchar=true, header=true)")
c.execute("""create table cal as select d::date cal_date,
 (dayofweek(d) in (0,6) or d::date in ('2026-01-01','2026-04-03','2026-04-06','2026-04-27','2026-05-01','2026-06-16','2026-08-10','2026-09-24','2026-12-16','2026-12-25')) = false as bd
 from generate_series(date '2026-01-01', date '2027-01-31', interval 1 day) t(d)""")
c.execute("""create macro bdays(a,b) as (select count(*) from cal where cal_date>a and cal_date<=b and bd)""")
print(c.execute("select count(*) from s").fetchall())
c.execute("""create table t as select nullif(trim("Submission ID"),'') id, try_cast("Submission Date" as timestamp) sub,
 nullif(trim(Store),'') store, try_cast(Amount as decimal(12,2)) amt, try_cast("Date of Transaction" as date) txd,
 nullif(trim("Customer Contact Number"),'') contact, nullif(trim("Card First 6 Digits"),'') f6, nullif(trim("Card Last 4 Digits"),'') l4,
 nullif(trim("Bank Statement"),'') stmt, "POPIA Consent" popia, try_cast("Recon Reviewed At" as timestamp) rev,
 try_cast("Sent To Bank At" as timestamp) bank, try_cast("Closed At" as timestamp) closed from s""")
c.execute("create table r as select * from t where id is not null and sub is not null and store is not null and amt is not null and amt>0")
print('merged',c.execute("select count(*), count(distinct id) from r").fetchall())
asof="date '2026-10-27'"
c.execute(f"""create table e as
select id,'REVIEW_SLA_BREACH' x from r where bdays(sub::date, coalesce(rev::date,{asof}))>2
union all select id,'BANK_SLA_BREACH' from r where bank is not null and bdays(bank::date, coalesce(closed::date,{asof}))>10
union all select id,'MISSING_STATEMENT' from r where stmt is null
union all select id,'CARD_MASK_INVALID' from r where f6 is null or l4 is null or not regexp_full_match(f6,'[0-9]{{6}}') or not regexp_full_match(l4,'[0-9]{{4}}')
union all select id,'MISSING_CONTACT' from r where contact is null
union all select id,'NO_POPIA_CONSENT' from r where coalesce(trim(popia),'')<>'Yes'
union all select id,'POSSIBLE_DUPLICATE' from (select id, row_number() over (partition by store,amt,f6,l4,txd order by sub,id) rn from r) where rn>1""")
c.execute("create table k as select * from read_csv('data/answer_key.csv', all_varchar=true)")
print(c.execute("""select coalesce(e.x,k.exception_type) t, count(e.id) filter (where k.submission_id is not null) tp,
 count(*) filter (where k.submission_id is null) fp, count(*) filter (where e.id is null) missed
 from e full join k on e.id=k.submission_id and e.x=k.exception_type group by 1 order by 1""").fetchall())
