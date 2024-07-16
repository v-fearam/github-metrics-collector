CREATE TABLE
    repo_views (
        id int IDENTITY (1, 1) PRIMARY KEY,
        account varchar(255),
        repository varchar(255),
        count int,
        uniques int,
        timestamp datetime
    );
GO;

CREATE TABLE
    repo_clones(
        id int IDENTITY (1, 1) PRIMARY KEY,
        account varchar(255),
        repository varchar(255),
        count int,
        uniques int,
        timestamp datetime
    );
GO;


CREATE PROCEDURE MergeRepoViews
    @account VARCHAR(255),
    @repository VARCHAR(255),
    @count INT,
    @uniques INT,
    @timestamp DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    MERGE repo_views AS target
    USING (SELECT @account AS account, @repository AS repository, @count AS count, @uniques AS uniques, @timestamp AS timestamp) AS source
    ON (target.account = source.account AND target.repository = source.repository AND target.timestamp = source.timestamp)
    WHEN MATCHED THEN 
        UPDATE SET count = source.count, uniques = source.uniques
    WHEN NOT MATCHED THEN
        INSERT (account, repository, count, uniques, timestamp)
        VALUES (source.account, source.repository, source.count, source.uniques, source.timestamp);
END;
GO;
