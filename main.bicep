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

var frequency = 'Day'
var interval = '1'
var workflowSchema = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'

resource gitHubMetrics 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: {
    displayName: logicAppName
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': workflowSchema
      contentVersion: '1.0.0.0'
      parameters: {
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
  }
}
