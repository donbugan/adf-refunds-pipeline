#!/usr/bin/env bash
# Runs the SQL scripts against the deployed database using your Azure CLI sign-in (Cloud Shell).
# Usage: bash infra/run_sql.sh <sql-server-fqdn> <factory-name>
set -euo pipefail
SERVER="$1"; FACTORY="$2"; DB=refunds
run() { echo "== $1"; sqlcmd -S "$SERVER" -d "$DB" --authentication-method ActiveDirectoryDefault -b -i "$1"; }
run sql/01_schema.sql
run sql/02_calendar.sql
run sql/03_merge_proc.sql
run sql/04_exceptions_proc.sql
sed "s/adf-refunds-<you>/$FACTORY/g" sql/05_security.sql > /tmp/05_security_resolved.sql
run /tmp/05_security_resolved.sql
run sql/07_answer_key.sql
echo "Done. Database objects created and the factory identity has its grants."
