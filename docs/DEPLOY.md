# Deploy and run: step by step

This takes about an hour, end to end. Everything after step 1 happens in the Azure portal and Azure Cloud Shell, so nothing needs installing on your machine.

## 1. Push the repo to GitHub (your machine)

1. Unzip `adf_refunds_pipeline.zip`. It already contains a git repo with two commits.
2. On GitHub, create a new **empty** repository named `adf-refunds-pipeline`. Don't add a README or licence, and make it public (the CV links to it).
3. In the unzipped `refunds` folder:

```bash
git remote add origin https://github.com/donbugan/adf-refunds-pipeline.git
git push -u origin main
```

## 2. Open Cloud Shell and get the repo

1. Go to portal.azure.com, click the Cloud Shell icon (`>_`, top bar) and choose **Bash**.
2. Get the repo:

```bash
git clone https://github.com/donbugan/adf-refunds-pipeline.git
cd adf-refunds-pipeline
```

3. Register the providers. This is harmless if they're already registered; wait until both say `Registered`:

```bash
az provider register -n Microsoft.DataFactory
az provider register -n Microsoft.Sql
az provider show -n Microsoft.DataFactory --query registrationState -o tsv
az provider show -n Microsoft.Sql --query registrationState -o tsv
```

## 3. Deploy the infrastructure with Bicep

```bash
az group create -n rg-refunds -l southafricanorth

az deployment group create -g rg-refunds -f infra/main.bicep \
  -p sqlAdminLogin="$(az ad signed-in-user show --query userPrincipalName -o tsv)" \
     sqlAdminObjectId="$(az ad signed-in-user show --query id -o tsv)" \
  --query properties.outputs
```

It takes about 3–5 minutes. Then put the outputs into variables:

```bash
OUT=$(az deployment group show -g rg-refunds -n main --query properties.outputs)
SQL=$(echo $OUT | jq -r .sqlServer.value)
ADF=$(echo $OUT | jq -r .factory.value)
STG=$(echo $OUT | jq -r .storageAccount.value)
echo $SQL $ADF $STG
```

**If it fails:**
- **Free offer already used:** if the error mentions the free offer or `useFreeLimit`, rerun with `useSqlFreeOffer=false` added after the other `-p` values.
- **Region:** if the error says a resource type isn't available in `southafricanorth`, delete the group (`az group delete -n rg-refunds --yes`) and redo this step with `-l westeurope`.

📸 **Screenshot:** the resource group overview, showing the storage account, SQL server, database and data factory.

## 4. Create the database objects

Cloud Shell has no `sqlcmd`, so install go-sqlcmd into your home folder first:

```bash
mkdir -p ~/bin && cd ~/bin
curl -sSL -o sqlcmd.tbz https://github.com/microsoft/go-sqlcmd/releases/latest/download/sqlcmd-linux-amd64.tar.bz2
tar -xjf sqlcmd.tbz sqlcmd && rm sqlcmd.tbz
export PATH=~/bin:$PATH
cd ~/adf-refunds-pipeline
```

Then:

```bash
bash infra/run_sql.sh $SQL $ADF
```

This runs `sql/01` to `05` and `07`, as you, through your Azure CLI sign-in. It creates the tables, the calendar, both procedures and the answer key, and gives the factory's identity its grants.

**If `sqlcmd` fails on sign-in or the firewall,** use the portal instead:
1. Go to SQL database `refunds` → **Query editor** → sign in with Microsoft Entra. If it offers to allowlist your IP, accept.
2. The query editor does not understand `GO`. Paste and run each file **one block at a time**, splitting at every `GO`, in the order 01, 02, 03, 04, 05, 07.
3. In 05, replace `adf-refunds-<you>` with your factory name first.

## 5. Upload the export

```bash
az storage blob upload --auth-mode login --account-name $STG -c refunds \
  -n inbound/jotform_refunds_export.csv -f data/jotform_refunds_export.csv
```

If you get `AuthorizationPermissionMismatch`, your storage role is still propagating. Wait 2–5 minutes and run it again.

## 6. Run the pipeline

1. Go to portal → your data factory → **Launch studio**.
2. Open **Author** (pencil icon) → Pipelines → `pl_refunds_to_sql`.
3. Click **Debug**. The defaults are file `jotform_refunds_export.csv`, as-of date `2026-10-27`, and 18 columns. Click OK.
4. Watch the Output tab. All 8 activities should go green: Check file, File is usable, Stage as text, Merge, Rows reconcile, Build exceptions, and the two report writes.

**Check the counts:**
- Click the glasses icon on **Merge**. Expect `staged 307, rejected 3, inserted 304, updated 0`.
- If **Stage as text** shows `rowsCopied 306`, ADF skipped the fully blank row. That's fine, but note it in RESULTS.md.
- Click the glasses icon on **Build exceptions**. Expect these seven counts:

  | Exception | Expected |
  |---|---|
  | BANK_SLA_BREACH | 42 |
  | CARD_MASK_INVALID | 7 |
  | MISSING_CONTACT | 4 |
  | MISSING_STATEMENT | 6 |
  | NO_POPIA_CONSENT | 2 |
  | POSSIBLE_DUPLICATE | 4 |
  | REVIEW_SLA_BREACH | 33 |

📸 **Screenshots:** the green pipeline run, the Merge output, and the Build exceptions output.

**If an activity fails,** click the error icon on it, copy the message and send it to me.

## 7. Prove the rerun

Click **Debug** again with the same file. Expect `inserted 0, updated 304`, and the same exception counts. This shows the load is idempotent and never deletes.

📸 **Screenshot:** the second Merge output.

## 8. Validate against the answer key

Run `sql/06_validate.sql`, either with `sqlcmd -S $SQL -d refunds --authentication-method ActiveDirectoryAzCli -i sql/06_validate.sql` or block by block in the query editor. The scorecard should show `false_pos 0` and `missed 0` for every type.

📸 **Screenshots:** the scorecard, plus the report files in storage (`refunds/reports/`) in the portal.

## 9. Record the results

Create `RESULTS.md` in the repo with the counts you saw, the date, and any differences (e.g. 306 rows copied). Add the screenshots in a `docs/img/` folder, then commit and push.

## 10. Tear down (before the 29th)

```bash
az group delete -n rg-refunds --yes
```

This removes everything, so no more charges.
