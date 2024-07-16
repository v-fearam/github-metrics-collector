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
param repositories array = [
  'samples'
  'iaas-baseline'
]

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The administrator username of the SQL logical server.')
param administratorLogin string = 'myadminname'

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string

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

// -- Resources

resource logicAppUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: 'logicAppUserIdentity'
  location: resourceGroup().location
}

resource connections_sql_resource 'Microsoft.Web/connections@2016-06-01' = {
  name: connections_sql_name
  location: location
  properties: {
    displayName: 'MetricDatabase'
    statuses: [
      {
        status: 'Connected'
      }
    ]
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/${connections_sql_name}'
    }
    parameterValues: {
      server: sqlDB.name
      database: '${sqlServer.name}.database.windows.net'
      authType: 'sqlAuthentication'
      username: administratorLogin
      password: administratorLoginPassword
    }
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
      '${logicAppUserIdentity.id}': {}
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
            Parse_JSON_Body: {
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
            For_each_day: {
              foreach: '@body(\'Parse_JSON_Body\')?[\'views\']'
              actions: {
                View_Data_in_a_Day: {
                  type: 'ParseJson'
                  inputs: {
                    content: '@items(\'For_each_day\')'
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
                'Execute_stored_procedure_(V2)': {
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
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'default\'))},@{encodeURIComponent(encodeURIComponent(\'default\'))}/procedures/@{encodeURIComponent(encodeURIComponent(\'MergeRepoViews\'))}'
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
                Parse_JSON_Body: [
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
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/${connections_sql_resource.name}'
            connectionId: connections_sql_resource.id
            connectionName: 'sql'
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
  }
  resource allowAzureServicesRule 'firewallRules' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 10
  }
  properties: {
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}
