@description('The name of the logic app to create.')
param logicAppName string = 'github-metrics'

@description('A github Api Uru')
param gitHubUri string = 'https://api.github.com'

@description('User access token. ')
@secure()
param token string
// https://docs.github.com/en/rest/metrics/traffic?apiVersion=2022-11-28#get-repository-clones 
// https://docs.github.com/en/rest/metrics/traffic?apiVersion=2022-11-28#get-page-views
// The fine-grained token must have the following permission set:  "Administration" repository permissions (read)

@description('The account own of the repos')
param owner string = 'mspnp'

@description('the array of repos to collect metrics')
param repositories array

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The administrator username of the SQL logical server.')
param administratorLogin string = 'myadminname'

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string = newGuid()

@description('The Microsoft Entra ID user to be database admin')
param user string

@description('The object id of the previous user')
param userObjectId string

@description('The tenant id of the previous user')
param userTenantId string

// --- Variables
var uniqueName = uniqueString(resourceGroup().id)

@description('The name of the SQL logical server.')
var serverName = 'sqlserver-${uniqueName}'
@description('The name of the SQL Database.')
var sqlDBName = 'GitHubMetrics-${uniqueName}'

var frequency = 'Day'
var interval = '1'
var workflowSchema = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
var connections_sql_name = 'sql'
var logAnalyticsWorkspaceName = 'GitHubMetrics-${uniqueName}'

// -- Resources

resource ghbLogicAppUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: 'ghbLogicAppUserIdentity'
  location: resourceGroup().location
}

resource connections_sql_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_sql_name
  location: location
  properties: {
    authenticatedUser: {}
    connectionState: 'Enabled'
    parameterValueSet: {
      name: 'oauthMI'
      values: {}
    }
    alternativeParameterValues: {}
    displayName: 'MetricDatabase'
    statuses: [
      {
        status: 'Ready'
      }
    ]
    customParameterValues: {}
    api: {
      name: 'sql'
      displayName: 'SQL Server'
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/${connections_sql_name}'
      type: 'Microsoft.Web/locations/managedApis'
    }
    testLinks: [
      {
        requestUri: 'https://management.azure.com:443/subscriptions${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/${connections_sql_name}/extensions/proxy/testconnection?api-version=2016-06-01'
        method: 'get'
      }
    ]
  }
}

resource gitHubMetrics 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: {
    displayName: logicAppName
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${ghbLogicAppUserIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': workflowSchema
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
        gitHubUri: {
          type: 'string'
          defaultValue: gitHubUri
        }
        token: {
          type: 'string'
          defaultValue: token
        }
        owner: {
          type: 'string'
          defaultValue: owner
        }
      }
      triggers: {
        recurrence: {
          recurrence: {
            frequency: frequency
            interval: interval
            timeZone: 'UTC'
            schedule: {
              hours: [
                '0'
              ]
              minutes: [
                0
              ]
            }
          }
          evaluatedRecurrence: {
            frequency: frequency
            interval: interval
            timeZone: 'UTC'
            schedule: {
              hours: [
                '0'
              ]
              minutes: [
                0
              ]
            }
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Authorization_Token: {
          runAfter: {}
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'token'
                type: 'string'
                value: token
              }
            ]
          }
        }
        Account: {
          runAfter: {
            Authorization_Token: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'account'
                type: 'string'
                value: owner
              }
            ]
          }
        }
        Repositories: {
          runAfter: {
            Account: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'repositories'
                type: 'array'
                value: repositories
              }
            ]
          }
        }
        'For_each_repo_-_Views': {
          foreach: '@variables(\'repositories\')'
          actions: {
            HTTP_View: {
              type: 'Http'
              inputs: {
                uri: 'https://api.github.com/repos/@{variables(\'account\')}/@{items(\'For_each_repo_-_Views\')}/traffic/views'
                method: 'GET'
                headers: {
                  Authorization: 'Bearer @{variables(\'token\')}'
                  Accept: 'application/vnd.github+json'
                  'X-GitHub-Api-Version': '2022-11-28'
                  'User-Agent': 'Awesome-Traffic-App'
                }
                queries: {
                  per: 'day'
                }
              }
              runtimeConfiguration: {
                contentTransfer: {
                  transferMode: 'Chunked'
                }
              }
            }
            Parse_JSON_Views_Body: {
              runAfter: {
                HTTP_View: [
                  'Succeeded'
                ]
              }
              type: 'ParseJson'
              inputs: {
                content: '@body(\'HTTP_View\')'
                schema: {
                  properties: {
                    count: {
                      type: 'integer'
                    }
                    uniques: {
                      type: 'integer'
                    }
                    views: {
                      items: {
                        properties: {
                          count: {
                            type: 'integer'
                          }
                          timestamp: {
                            type: 'string'
                          }
                          uniques: {
                            type: 'integer'
                          }
                        }
                        required: [
                          'timestamp'
                          'count'
                          'uniques'
                        ]
                        type: 'object'
                      }
                      type: 'array'
                    }
                  }
                  type: 'object'
                }
              }
            }
            For_each_view_day: {
              foreach: '@body(\'Parse_JSON_Views_Body\')?[\'views\']'
              actions: {
                View_Data_in_a_Day: {
                  type: 'ParseJson'
                  inputs: {
                    content: '@items(\'For_each_view_day\')'
                    schema: {
                      properties: {
                        count: {
                          type: 'integer'
                        }
                        timestamp: {
                          type: 'string'
                        }
                        uniques: {
                          type: 'integer'
                        }
                      }
                      type: 'object'
                    }
                  }
                }
                Save_view_data: {
                  inputs: {
                    body: {
                      account: '@variables(\'account\')'
                      count: '@body(\'View_Data_in_a_Day\')?[\'count\']'
                      repository: '@{items(\'For_each_repo_-_Views\')}'
                      timestamp: '@body(\'View_Data_in_a_Day\')?[\'timestamp\']'
                      uniques: '@body(\'View_Data_in_a_Day\')?[\'uniques\']'
                    }
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${sqlServer.name}.database.windows.net\'))},@{encodeURIComponent(encodeURIComponent(\'${sqlDB.name}\'))}/procedures/@{encodeURIComponent(encodeURIComponent(\'[ghb].[MergeRepoViews]\'))}'
                  }
                  runAfter: {
                    View_Data_in_a_Day: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                }
              }
              runAfter: {
                Parse_JSON_Views_Body: [
                  'Succeeded'
                ]
              }
              type: 'Foreach'
            }
          }
          runAfter: {
            Repositories: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
        'For_each_repo_-Clones': {
          foreach: '@variables(\'repositories\')'
          actions: {
            HTTP_Clones: {
              type: 'Http'
              inputs: {
                uri: 'https://api.github.com/repos/@{variables(\'account\')}/@{items(\'For_each_repo_-Clones\')}/traffic/clones'
                method: 'GET'
                headers: {
                  Authorization: 'Bearer @{variables(\'token\')}'
                  Accept: 'application/vnd.github+json'
                  'X-GitHub-Api-Version': '2022-11-28'
                  'User-Agent': 'Awesome-Traffic-App'
                }
                queries: {
                  per: 'day'
                }
              }
              runtimeConfiguration: {
                contentTransfer: {
                  transferMode: 'Chunked'
                }
              }
            }
            Parse_JSON_Clones_Body: {
              runAfter: {
                HTTP_Clones: [
                  'Succeeded'
                ]
              }
              type: 'ParseJson'
              inputs: {
                content: '@body(\'HTTP_Clones\')'
                schema: {
                  properties: {
                    count: {
                      type: 'integer'
                    }
                    uniques: {
                      type: 'integer'
                    }
                    clones: {
                      items: {
                        properties: {
                          count: {
                            type: 'integer'
                          }
                          timestamp: {
                            type: 'string'
                          }
                          uniques: {
                            type: 'integer'
                          }
                        }
                        required: [
                          'timestamp'
                          'count'
                          'uniques'
                        ]
                        type: 'object'
                      }
                      type: 'array'
                    }
                  }
                  type: 'object'
                }
              }
            }
            For_each_clone_day: {
              foreach: '@body(\'Parse_JSON_Clones_Body\')?[\'clones\']'
              actions: {
                Clone_Data_in_a_Day: {
                  type: 'ParseJson'
                  inputs: {
                    content: '@items(\'For_each_clone_day\')'
                    schema: {
                      properties: {
                        count: {
                          type: 'integer'
                        }
                        timestamp: {
                          type: 'string'
                        }
                        uniques: {
                          type: 'integer'
                        }
                      }
                      type: 'object'
                    }
                  }
                }
                Save_clone_data: {
                  runAfter: {
                    Clone_Data_in_a_Day: [
                      'Succeeded'
                    ]
                  }
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'sql\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: {
                      account: '@variables(\'account\')'
                      count: '@body(\'Clone_Data_in_a_Day\')?[\'count\']'
                      repository: '@{items(\'For_each_repo_-Clones\')}'
                      timestamp: '@body(\'Clone_Data_in_a_Day\')?[\'timestamp\']'
                      uniques: '@body(\'Clone_Data_in_a_Day\')?[\'uniques\']'
                    }
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${sqlServer.name}.database.windows.net\'))},@{encodeURIComponent(encodeURIComponent(\'${sqlDB.name}\'))}/procedures/@{encodeURIComponent(encodeURIComponent(\'[ghb].[MergeRepoClones]\'))}'
                  }
                }
              }
              runAfter: {
                Parse_JSON_Clones_Body: [
                  'Succeeded'
                ]
              }
              type: 'Foreach'
            }
          }
          runAfter: {
            Repositories: [
              'Succeeded'
            ]
          }
          type: 'Foreach'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          sql: {
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/sql'
            connectionId: connections_sql_resource.id
            connectionName: 'sql'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
                identity: ghbLogicAppUserIdentity.id
              }
            }
          }
        }
      }
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    minimalTlsVersion: '1.2'
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
  resource allowAzureServicesRule 'firewallRules' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  resource activeDirectoryAdmin 'administrators@2023-08-01-preview' = {
    name: 'ActiveDirectory'
    properties: {
      administratorType: 'ActiveDirectory'
      login: user
      sid: userObjectId
      tenantId: userTenantId
    }
  }
  resource sqlADOnlyAuth 'azureADOnlyAuthentications@2023-08-01-preview' = {
    name: 'Default'
    properties: {
      azureADOnlyAuthentication: true
    }
    dependsOn: [
      activeDirectoryAdmin
    ]
  }
}

resource diagnosticSettingsSqlServer 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlServer
  name: '${sqlServer.name}-diag'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
  dependsOn: [
    sqlServer::sqlADOnlyAuth
    sqlServer::activeDirectoryAdmin
    auditingServerSettings
    sqlVulnerabilityAssessment
  ]
}

resource auditingDbSettings 'Microsoft.Sql/servers/databases/auditingSettings@2023-08-01-preview' = {
  parent: sqlDB
  name: 'default'
  properties: {
    retentionDays: 0
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
    isAzureMonitorTargetEnabled: true
    isManagedIdentityInUse: false
    state: 'Enabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Example SKU, adjust as needed
    }
    retentionInDays: 30 // Adjust retention period as needed
  }
}

resource diagnosticSettingsSqlDb 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlDB
  name: '${sqlDB.name}-diag'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

resource auditingServerSettings 'Microsoft.Sql/servers/auditingSettings@2021-11-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}

resource sqlVulnerabilityAssessment 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2022-11-01-preview' = {
  name: 'default'
  parent: sqlServer
  properties: {
    state: 'Enabled'
  }
  dependsOn: [
    auditingServerSettings
  ]
}

resource solutions_SQLAuditing_githubmetrics 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SolutionSQLAuditing${logAnalyticsWorkspace.name}'
  location: location
  plan: {
    name: 'SQLAuditing${sqlDB.name}'
    promotionCode: ''
    product: 'SQLAuditing'
    publisher: 'Microsoft'
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
    containedResources: [
      '${resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspace.name)}/views/SQLSecurityInsights'
      '${resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspace.name)}/views/SQLAccessToSensitiveData'
    ]
    referencedResources: []
  }
}

// Diagnostic setting for the Logic App
resource logicAppDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${logicAppName}-diag'
  scope: gitHubMetrics
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}
