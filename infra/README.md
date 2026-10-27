# Deploy with Bicep

`main.bicep` creates everything in one resource group:
- A storage account with the `refunds` container. Shared keys are off, so access is by identity only.
- Azure SQL Database (serverless, free offer) with Microsoft Entra-only authentication.
- The Data Factory with a system-assigned identity.
- The role assignments on storage.
- The factory's linked services, datasets and pipeline. The datasets and pipeline are loaded from `../adf`, so the repo JSON is what gets deployed.

Run these in Azure Cloud Shell (bash), from the repo root:

```bash
az group create -n rg-refunds -l southafricanorth

az deployment group create -g rg-refunds -f infra/main.bicep \
  -p sqlAdminLogin="$(az ad signed-in-user show --query userPrincipalName -o tsv)" \
     sqlAdminObjectId="$(az ad signed-in-user show --query id -o tsv)"
```

If the subscription has already used the Azure SQL free offer, add `useSqlFreeOffer=false`.

The outputs give the storage account, SQL server and factory names. Then:

1. In the SQL query editor (sign in with Entra), run `sql/01` to `sql/04`. Then run `sql/05_security.sql`, with `adf-refunds-<you>` replaced by the factory name from the outputs.
2. Upload `data/jotform_refunds_export.csv` to `refunds/inbound`. In the portal upload pane, choose "Microsoft Entra user account" as the authentication method.
3. Open the factory and Debug `pl_refunds_to_sql`.
4. Run `sql/06_validate.sql`.

Creating the SQL user for the factory (step 1) is the only manual step. Bicep cannot run T-SQL without a deployment script and an extra identity, and that wasn't worth it here.

Tear down:

```bash
az group delete -n rg-refunds --yes
```
