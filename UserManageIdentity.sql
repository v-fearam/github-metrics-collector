create user [ghbLogicAppUserIdentity] from external provider
GO;

alter role db_datareader add member [ghbLogicAppUserIdentity]
GO;

alter role db_datawriter add member [ghbLogicAppUserIdentity]
GO;

GRANT EXECUTE TO [ghbLogicAppUserIdentity]
GO;

-- Grant permissions on the ghb schema
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ghb TO [ghbLogicAppUserIdentity];
GO;