create user [logicAppUserIdentity] from external provider
GO;

alter role db_datareader add member [logicAppUserIdentity]
GO;

alter role db_datawriter add member [logicAppUserIdentity]
GO;

GRANT EXECUTE TO [logicAppUserIdentity]
GO;