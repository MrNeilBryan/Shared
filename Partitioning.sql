USE [master]
GO
SET NOCOUNT ON;
GO
SET STATISTICS IO OFF
SET STATISTICS TIME OFF
GO

----------------------------------------------------------------------------------------------------------------
-- Drop PartitioningDatabase Database
----------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.databases where [name] = 'PartitioningDatabase') BEGIN
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PartitioningDatabase'
    ALTER DATABASE PartitioningDatabase SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE PartitioningDatabase
END
GO
 

----------------------------------------------------------------------------------------------------------------
-- Create PartitioningDatabase Database
----------------------------------------------------------------------------------------------------------------
CREATE DATABASE PartitioningDatabase
GO
ALTER DATABASE PartitioningDatabase SET RECOVERY SIMPLE; 
GO

USE [PartitioningDatabase]
GO
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
SET NOCOUNT ON
GO
 
--------------------------------------------------------------------------------------------
-- Create a partition function called pfMonths with 50 vears of months 2000 - 2050
--------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE [name] = 'pfMonths') BEGIN
        DECLARE @DT DATE ='20000101'
        DECLARE @Str NVARCHAR(MAX) = N' CREATE PARTITION FUNCTION pfMonths (DATE) AS RANGE RIGHT FOR VALUES (';
        WHILE @DT < '20510101'
        BEGIN
                SET @Str += '''' + CONVERT (NVARCHAR(256), @DT, 112) + ''',';
                SET @DT = DATEADD(MONTH, 1, @DT ) ;
        END

        SET @Str = SUBSTRING(@Str, 1, LEN(@Str)-1) + ')'
        EXEC sp_executesql @stmt = @Str;
        PRINT 'Partition Function pfMonths created'; 
END 
ELSE 
BEGIN
        PRINT 'Partition Function pfMonths already exists'; 
      END 
GO

--------------------------------------------------------------------------------------------
-- Create the partition schema psMonths for partition function pfMonths
--------------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.partition_schemes WHERE [name] = 'psMonths') 
BEGIN
    CREATE PARTITION SCHEME psMonths AS PARTITION pfMonths ALL TO ([Primary]);
    PRINT 'Partition Scheme psMonths created'; 
END 
ELSE 
BEGIN
    PRINT 'Partition Scheme psMonths already exists'; 
END 
GO

--------------------------------------------------------------------------------------------
-- Drop the non partition work table
--------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.tbl_Test_Non_Partition') IS NOT NULL 
BEGIN 
    DROP TABLE do.tbl_Test_Non_Partition 
END 
PRINT 'Dropped table dbo.tbl Test Non Partition'
GO

--------------------------------------------------------------------------------------------
--  Drop the partition work table
--------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.tbl_Test_Partition') IS NOT NULL 
BEGIN
    DROP TABLE dbo.tbl_Test_Partition 
END 
PRINT 'Dropped table dbo.tbl_Test_ Partition'
GO


--------------------------------------------------------------------------------------------
-- Create the partition work table
--------------------------------------------------------------------------------------------
CREATE TABLE dbo.tbl_Test_Partition([Date] [date] NOT NULL , 
                                    EmployeeID INT NOT NULL IDENTITY(1,1) , 
                                    [AccRef] BIGINT NOT NULL, 
                                    [Amount] [money] NULL) 
             ON psMonths ( [Date]) 
PRINT 'Recreated dbo.tbl_Test_Partition'
GO
--------------------------------------------------------------------------------------------
-- Create the non partition work table
--------------------------------------------------------------------------------------------
CREATE TABLE dbo.tbl_Test_Non_Partition( [Date] [date] NOT NULL ,
                                         EmployeeID INT NOT NULL IDENTITY(1,1), 
                                         [AccRef] [bigint] NOT NULL, 
                                         [Amount] [money] NULL,
                                         PRIMARY KEY CLUSTERED (EmployeeID ) 
) ON [PRIMARY]
PRINT 'Recreated dbo.tbl_Test_Non_Partition'
GO

--------------------------------------------------------------------------------------------
-- Populate the non partition work table
--------------------------------------------------------------------------------------------
DECLARE @i INT = 1 ;
DECLARE @startDate AS DATE = '20130101'; 
DECLARE @DT DATE 
WHILE (@i <= 10000000) -- Amend as required
BEGIN
        SET @DT = DATEADD(DAY, RAND(CHECKSUM(NEWID()))* (1+DATEDIFF (DAY, @startDate, @EndDate)) , @StartDate) ;
        INSERT dbo.tbl_Test_Non_Partition ([Date], [AccRef], [Amount]) SELECT @DT, CAST (@I AS NVARCHAR (256)), 
                                                                                        DATEDIFF(DAY, @DT, GETDATE());
        SET @i +=1
END
PRINT 'Populated the non partition work table'
GO
--------------------------------------------------------------------------------------------
-- Populate the partition work table
--------------------------------------------------------------------------------------------—
INSERT dbo.tbl_Test_Partition ([Date],AccRef,Amount) SELECT [Date], AccRef, Amount FROM dbo.tbl_Test_Non_Partition PRINT 'Populated the partition work table'; 
GO


--------------------------------------------------------------------------------------------
-- Testing
-------------------------------------------------------------------------------------------
USE [PartitioningDatabase]
GO

SET STATISTICS IO ON
SET STATISTICS TIME ON
GO

PRINT '-------------------------Selecting from dbo.tbl_Test_Partition----------------------------------------';
PRINT 'Selecting from dbo.tbl_Test_Partition';
SELECT COUNT(1) FROM dbo.tbl_Test_Partition WHERE [date] >= '20220101' AND [date] <= '20220131'
PRINT '----------------------------------------------------------------------------------------------------';
PRINT '-------------------------Selecting from dbo.tbl_Test_Non_Partition----------------------------------------';
PRINT 'Selecting from dbo.tbl_Test_Non_Partition';
SELECT COUNT(1) FROM dbo.tbl_Test_Non_Partition WHERE [date] >= '20220101' AND [date] <= '20220131'
PRINT '----------------------------------------------------------------------------------------------------';


GO


--------------------------------------------------------------------------------------------
-- Show partitions
-------------------------------------------------------------------------------------------
SELECT $PARTITION.pfMonths([Date]) PartitionID, * FROM dbo.tbl_Test_Partition ORDER BY [Date] 
GO

--------------------------------------------------------------------------------------------
-- Delete all data from a partition usig TRUNCATE - INSTANT 2016 feature
--------------------------------------------------------------------------------------------
TRUNCATE TABLE  dbo.tbl_Test_Partition WITH (PARTITIONS (160)) 
GO
--
-- Check that there is no longer any rows in dbo.tbl_Test_Partition for Partition 160
--
SELECT * FROM  dbo.tbl_Test_Partition WHERE $PARTITION.pfMonths([Date]) = 160 
GO

--------------------------------------------------------------------------------------------
-- Move data from a partition to a partition on another table
--------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.tbl_Transferred_Data','U') IS NOT NULL BEGIN
    DROP TABLE dbo.tbl_Transferred_Data;
END
GO
CREATE TABLE dbo.tbl_Transferred_Data
(
    [Date] [date] NOT NULL , 
    EmployeeID INT NOT NULL IDENTITY(1,1) ,
    [AccRef] BIGINT NOT NULL,
    [Amount] [money] NULL 
) ON psMonths ( [Date])
GO
--
-- Switch the Partiton 159 from table dbo.tbl_Test_Partition to table dbo.tbl_Transferred_Data. This is INSTANT
--
ALTER TABLE dbo.tbl_Test_Partition SWITCH PARTITION 159 TO dbo.tbl_Transferred_Data PARTITION 159;
--
-- Check that there is no longer any rows in dbo.tbl_Test_Partition for Partition 159
--
SELECT $PARTITION.pfMonths([Date]),* FROM  dbo.tbl_Test_Partition WHERE $PARTITION.pfMonths([Date]) = 159
--
-- Check that the Partition 159 rows are now in the dbo.tbl_Transferred_Data table.
--
SELECT $PARTITION.pfMonths([Date]),* FROM dbo.tbl_Transferred_Data  
