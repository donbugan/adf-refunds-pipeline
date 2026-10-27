// ============================================================
// Card refunds: everything the pipeline needs, in one deployment
//   storage account + container, Azure SQL (Entra-only auth), Data Factory with
//   system-assigned identity, its role on storage, and the factory's linked
//   services, datasets and pipeline (loaded from ../adf so there is one source of truth)
// Deploy: see infra/README.md
// ============================================================
targetScope = 'resourceGroup'

@description('Short prefix for resource names, lower case letters and digits')
@maxLength(10)
param prefix string = 'refunds'

param location string = resourceGroup().location

@description('Your Entra sign-in (UPN), set as the SQL Entra admin')
param sqlAdminLogin string

@description('Object id of that user: az ad signed-in-user show --query id -o tsv')
param sqlAdminObjectId string

@description('Use the Azure SQL free offer (one per subscription). Set false if already used.')
param useSqlFreeOffer bool = true

var suffix = uniqueString(resourceGroup().id)
var storageName = take('${prefix}${suffix}', 24)
var sqlServerName = '${prefix}-sql-${suffix}'
var sqlDbName = 'refunds'
var factoryName = '${prefix}-adf-${suffix}'
var blobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ---------- Storage ----------
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false      // identity only, no account keys
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'refunds'
  properties: { publicAccess: 'None' }
}

// ---------- Azure SQL ----------
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    minimalTlsVersion: '1.2'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: sqlAdminLogin
      sid: sqlAdminObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true  // no SQL logins or passwords
    }
  }
}

resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDbName
  location: location
  sku: { name: 'GP_S_Gen5', tier: 'GeneralPurpose', family: 'Gen5', capacity: 1 }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
    useFreeLimit: useSqlFreeOffer
    freeLimitExhaustionBehavior: useSqlFreeOffer ? 'AutoPause' : null
  }
}

// ---------- Data Factory ----------
resource factory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: factoryName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

// Factory identity reads inbound files and writes reports
resource factoryBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, factory.id, blobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataContributor)
    principalId: factory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// You upload the export in the portal with your own identity (shared keys are off)
resource adminBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, sqlAdminObjectId, blobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataContributor)
    principalId: sqlAdminObjectId
    principalType: 'User'
  }
}

// Linked services are written here because they carry this deployment's endpoints
resource lsBlob 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: factory
  name: 'ls_blob_refunds'
  properties: {
    type: 'AzureBlobStorage'
    description: 'Storage account via the factory system-assigned managed identity (no keys).'
    typeProperties: {
      serviceEndpoint: storage.properties.primaryEndpoints.blob
      accountKind: 'StorageV2'
    }
  }
}

resource lsSql 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: factory
  name: 'ls_sql_refunds'
  properties: {
    type: 'AzureSqlDatabase'
    description: 'Azure SQL Database via the factory system-assigned managed identity.'
    typeProperties: {
      server: sqlServer.properties.fullyQualifiedDomainName
      database: sqlDbName
      encrypt: 'mandatory'
      trustServerCertificate: false
      authenticationType: 'SystemAssignedManagedIdentity'
    }
  }
}

// Datasets and pipeline come straight from the ADF JSON in the repo
var datasetFiles = {
  ds_jotform_csv: loadJsonContent('../adf/dataset/ds_jotform_csv.json')
  ds_report_csv: loadJsonContent('../adf/dataset/ds_report_csv.json')
  ds_sql_stage: loadJsonContent('../adf/dataset/ds_sql_stage.json')
  ds_sql_query: loadJsonContent('../adf/dataset/ds_sql_query.json')
}

resource datasets 'Microsoft.DataFactory/factories/datasets@2018-06-01' = [for ds in items(datasetFiles): {
  parent: factory
  name: ds.key
  properties: ds.value.properties
  dependsOn: [ lsBlob, lsSql ]
}]

resource pipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: factory
  name: 'pl_refunds_to_sql'
  properties: loadJsonContent('../adf/pipeline/pl_refunds_to_sql.json').properties
  dependsOn: [ datasets ]
}

output storageAccount string = storage.name
output sqlServer string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabase string = sqlDbName
output factory string = factory.name
output factoryPrincipalId string = factory.identity.principalId
