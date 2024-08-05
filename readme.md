# Collecting GitHub Metrics

This project uses the GitHub API to collect traffic metrics from a set of repositories within an organization. It deploys an Azure Logic App to consume the GitHub API, and the gathered information is saved in a SQL database.  
The Azure Logic App is configured in Consumption mode because it only needs to run for a few minutes each day, making it much more cost-effective than using a Standard App Service plan. However, [the Consumption mode](https://learn.microsoft.com/azure/logic-apps/single-tenant-overview-compare) does not support the use of private endpoints for accessing the database.  
The traffic data is available for the past 12 days. This implementation helps preserve the data for ongoing analysis over time.  
The application collects [views](https://docs.github.com/en/rest/metrics/traffic?apiVersion=2022-11-28#get-page-views) and [clones](https://docs.github.com/en/rest/metrics/traffic?apiVersion=2022-11-28#get-repository-clones) information from the repositories.

## Getting a GitHub Token

To use the GitHub API, you need a personal access token.
Follow the steps described in this guide to [creating a fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token).  
Please note that, according to the API documentation, you need to include `"Administration" repository permissions (read)`.  
Please make sure to keep your token secure.

## Deploy the Azure Resources

The Azure SQL Database, Azure Logic App, and other necessary resources will be deployed.

The database is going to be Microsoft Entra ID integrated (Only Microsoft Entra ID users will be enabled to login). A user name, user object id, and tenat id are going to be needed.

```bash
export USER=eastus<your data>
export USER_OBJECTID=<your data>
export USER_TENANTID=<your data>
```

The resource group creation

```bash
export LOCATION=eastus2
export RESOURCEGROUP_BASE_NAME=rg-github-metrics-collector
export RESOURCEGROUP=${RESOURCEGROUP_BASE_NAME}-${LOCATION}
az group create --name ${RESOURCEGROUP} --location ${LOCATION}
```

Please add the GitHub token, the GitHub account, and the array of repos array to be collected, then proceed to deploy.

```bash
az deployment group create --resource-group ${RESOURCEGROUP}  \
                        -f ./main.bicep  \
                        -p token=<GitHub Token>  \
                        administratorLoginPassword=changeMe123!  \
                        owner=mspnp  \
                        repositories='["samples", "iaas-baseline", "aks-baseline"]'  \
                        user=${USER} \
                        userObjectId=${USER_OBJECTID} \
                        userTenantId=${USER_TENANTID}
```

## Create Database Objects

1. Navigate to the resource group using the Azure Portal.
2. Select the SQL Database
3. Select the Query Editor
4. Log in using your Azure Account. The first time you do this, you’ll need to configure the firewall by following the portal instructions.
5. Copy the code from ./scripts.sql and paste it into the Query Editor. This includes the tables and stored procedures that the Azure Logic App will call to save the data.
6. Execute the script.
7. Review the created table and explore any stored procedures.
8. **Grant permissions to the Logic App User Managed Identity**. Copy the code from ./UserManageIdentity.sql and paste it into the Query Editor.
9. Execute the script.

## Test the Workflow

1. Navigate to the resource group using the Azure Portal.
2. Select the Azure Logic App
3. Open the Logic App Designer.
4. Run the workflow.
5. Select **Run History** and check if the workflow executed successfully.

Note: It may take some time to recognize that the permission to the identity was granted. If it fails, wait a little and try again later.

## Report

A star model was created in order to query the data. There are to dimentional tables and one fact table.

![GitHub Metrics](./GitHub-metrics.jpg)

- Select the SQL Database
- Open the Query Editor.
- Log in using your Azure Account.

The following is an example query on the star model. It returns the sum of values by account-repository and by week of the year.

```sql
SELECT
    dates.year,
    dates.month,
    dates.week,
    repo.account,
    repo.repository,
    SUM(fact.countViews) AS TotalCountViews,
    SUM(fact.uniquesViews) AS TotalUniquesViews,
    SUM(fact.countClones) AS TotalCountClones,
    SUM(fact.uniquesClones) AS TotalUniquesClones
FROM
    ghb.fact_views_clones fact
INNER JOIN
    ghb.dim_date dates ON fact.dateId = dates.id
INNER JOIN
    ghb.dim_repo repo ON fact.repoId = repo.id
GROUP BY
    dates.year,
    dates.month,
    dates.week,
    fact.repoId,
    repo.account,
    repo.repository
ORDER BY
    repo.account,
    repo.repository,
    dates.week
```

## Improve Database Security Information

On database Server navigate to Security-Auditing and select the Log Analytics which is deployed in the resource group.

## Clean up

```bash
az group delete --name ${RESOURCEGROUP} --yes
```
