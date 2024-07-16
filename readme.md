# Read metrics

```bash
export LOCATION=eastus2
export RESOURCEGROUP_BASE_NAME=far-rg-test1
export RESOURCEGROUP=${RESOURCEGROUP_BASE_NAME}-${LOCATION}
az group create --name ${RESOURCEGROUP} --location ${LOCATION}


az deployment group create --resource-group ${RESOURCEGROUP} -f ./main.bicep -p token=<your access token> administratorLoginPassword=changeMe123!

az group delete --name ${RESOURCEGROUP} --yes
```
