-- Change to the new schema
CREATE SCHEMA ghb;
GO

-- Create tables in the new schema
CREATE TABLE
    ghb.dim_date (
        id int IDENTITY (1, 1) PRIMARY KEY,
        day int,
        month int,
        year int,
        week int
    );
GO;

CREATE UNIQUE INDEX UX_DimDate_DayMonthYear ON ghb.dim_date (day, month, year);
GO;

CREATE TABLE
    ghb.dim_repo (
        id int IDENTITY (1, 1) PRIMARY KEY,
        account varchar(255),
        repository varchar(255)
    );
GO;

CREATE UNIQUE INDEX UX_DimRepo_AccountRepo ON ghb.dim_repo (account, repository);
GO;

CREATE TABLE
    ghb.fact_views_clones (
        id int IDENTITY (1, 1) PRIMARY KEY,
        dateId int,
        repoId int,
        countViews int Null,
        uniquesViews int Null,
        countClones int Null,
        uniquesClones int Null
    );
GO;

CREATE UNIQUE INDEX UX_FactViewsClones_DateIdRepoId ON ghb.fact_views_clones (dateId, repoId);
GO;

ALTER TABLE ghb.fact_views_clones
ADD CONSTRAINT FK_fact_views_clones_dateId FOREIGN KEY (dateId) REFERENCES ghb.dim_date(id);
GO;

ALTER TABLE ghb.fact_views_clones
ADD CONSTRAINT FK_fact_views_clones_repoId FOREIGN KEY (repoId) REFERENCES ghb.dim_repo(id);
GO;

-- Create the stored procedures in the new schema
CREATE PROCEDURE ghb.InsertRepoIfNotExists
    @account VARCHAR(255),
    @repository VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if the repo already exists in the table
    IF NOT EXISTS (SELECT 1 FROM ghb.dim_repo WHERE account = @account AND repository = @repository)
    BEGIN
        -- Insert the repo into the table
        INSERT INTO ghb.dim_repo (account, repository)
        VALUES (@account, @repository);
    END
END;
GO;

CREATE PROCEDURE ghb.InsertDateIfNotExists
    @InputDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Day INT;
    DECLARE @Month INT;
    DECLARE @Year INT;
    DECLARE @Week INT;

    -- Extract day, month, and year from the input date
    SET @Day = DAY(@InputDate);
    SET @Month = MONTH(@InputDate);
    SET @Year = YEAR(@InputDate);
    SET @Week = DATEPART(WEEK, @InputDate);

    -- Check if the date already exists in the table
    IF NOT EXISTS (SELECT 1 FROM ghb.dim_date WHERE day = @Day AND month = @Month AND year = @Year)
    BEGIN
        -- Insert the date into the table
        INSERT INTO ghb.dim_date (day, month, year, week)
        VALUES (@Day, @Month, @Year, @Week);
    END
END;
GO;

CREATE PROCEDURE ghb.MergeRepoViews
    @account VARCHAR(255),
    @repository VARCHAR(255),
    @count INT,
    @uniques INT,
    @timestamp DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Day INT;
    DECLARE @Month INT;
    DECLARE @Year INT;
    DECLARE @DateId INT;
    DECLARE @RepoId INT;

    -- Extract day, month, and year from the input date
    SET @Day = DAY(@timestamp);
    SET @Month = MONTH(@timestamp);
    SET @Year = YEAR(@timestamp);

    -- Insert date and repo if not exists
    EXEC ghb.InsertDateIfNotExists @timestamp;
    EXEC ghb.InsertRepoIfNotExists @account, @repository;

    -- Retrieve the id of the date
    SELECT @DateId = id
    FROM ghb.dim_date
    WHERE day = @Day AND month = @Month AND year = @Year;

    -- Retrieve the id of the repository
    SELECT @RepoId = id
    FROM ghb.dim_repo
    WHERE account = @account AND repository = @repository;

    -- Merge the fact_views_clones data
    MERGE ghb.fact_views_clones AS target
    USING (SELECT @RepoId AS repoId, @DateId AS dateId, @count AS countViews, @uniques AS uniquesViews) AS source
    ON (target.repoId = source.repoId AND target.dateId = source.dateId)
    WHEN MATCHED THEN 
        UPDATE SET countViews = source.countViews, uniquesViews = source.uniquesViews
    WHEN NOT MATCHED THEN
        INSERT (dateId, repoId, countViews, uniquesViews)
        VALUES (source.dateId, source.repoId, source.countViews, source.uniquesViews);
END;
GO;

CREATE PROCEDURE ghb.MergeRepoClones
    @account VARCHAR(255),
    @repository VARCHAR(255),
    @count INT,
    @uniques INT,
    @timestamp DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Day INT;
    DECLARE @Month INT;
    DECLARE @Year INT;
    DECLARE @DateId INT;
    DECLARE @RepoId INT;

    -- Extract day, month, and year from the input date
    SET @Day = DAY(@timestamp);
    SET @Month = MONTH(@timestamp);
    SET @Year = YEAR(@timestamp);

    -- Insert date and repo if not exists
    EXEC ghb.InsertDateIfNotExists @timestamp;
    EXEC ghb.InsertRepoIfNotExists @account, @repository;

    -- Retrieve the id of the date
    SELECT @DateId = id
    FROM ghb.dim_date
    WHERE day = @Day AND month = @Month AND year = @Year;

    -- Retrieve the id of the repository
    SELECT @RepoId = id
    FROM ghb.dim_repo
    WHERE account = @account AND repository = @repository;

    -- Merge the fact_views_clones data
    MERGE ghb.fact_views_clones AS target
    USING (SELECT @RepoId AS repoId, @DateId AS dateId, @count AS countClones, @uniques AS uniquesClones) AS source
    ON (target.repoId = source.repoId AND target.dateId = source.dateId)
    WHEN MATCHED THEN 
        UPDATE SET countClones = source.countClones, uniquesClones = source.uniquesClones
    WHEN NOT MATCHED THEN
        INSERT (dateId, repoId, countClones, uniquesClones)
        VALUES (source.dateId, source.repoId, source.countClones, source.uniquesClones);
END;
GO;
