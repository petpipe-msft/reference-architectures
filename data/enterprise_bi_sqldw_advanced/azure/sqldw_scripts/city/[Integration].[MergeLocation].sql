EXEC [dbo].[DropProcedureIfExists] 'Integration', 'MergeLocation'

PRINT 'Creating procedure [Integration].[MergeLocation]'
GO

CREATE PROCEDURE [Integration].[MergeLocation] AS
BEGIN

	DECLARE @MaxRowCount int = (
	SELECT MAX(a.[RowCount])
	FROM (
			SELECT COUNT(*) AS [RowCount]
				FROM [Integration].[CityLocation_Staging]
			GROUP BY [WWI City ID]
			) a
	)
 
	DECLARE @PivotColumns nvarchar(max) = '[1]'
	DECLARE @ColumnCount int
	SET @ColumnCount = 2
	WHILE @ColumnCount <= @MaxRowCount
	BEGIN
	  SET @PivotColumns = @PivotColumns + ', ' + QUOTENAME(CONVERT(nvarchar(5), @ColumnCount))
	  SET @ColumnCount += 1
	END
 
	DECLARE @Sql nvarchar(max) =
	N'

	CREATE TABLE LocationHolder
	WITH (HEAP , DISTRIBUTION = HASH([WWI City ID]))
	AS

	SELECT [WWI City ID], CONVERT(varbinary(max), CONCAT(NULL, ' + @PivotColumns + ')) AS [Location], [Valid From]
	  FROM (
		SELECT b.[WWI City ID], b.[Block ID], cls.[Location],b.[Valid From]
		FROM (
		  SELECT DISTINCT cls.[WWI City ID], a.[Block ID], NULL AS [Location],cls.[Valid From] As [Valid From]
			FROM [Integration].[CityLocation_Staging] cls CROSS APPLY (
			  SELECT TOP ' +
			  CONVERT(nvarchar(3), @MaxRowCount) + ' ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS [Block ID]
				FROM sys.all_objects
			) a
		) b
		LEFT OUTER JOIN [Integration].[CityLocation_Staging] cls
		  ON cls.[WWI City ID] = b.[WWI City ID]
		 AND cls.[Block ID] = b.[Block ID]
		 AND cls.[Valid From] = b.[Valid From]
	  ) x
	PIVOT
	(
	  max([Location])
	  for [Block ID] in (' + @PivotColumns + ')
	) piv

	UPDATE [Integration].[City_Staging]
	SET [Integration].[City_Staging].[Location] = LocationHolder.[Location]
	FROM LocationHolder
	WHERE [Integration].[City_Staging].[WWI City ID] = LocationHolder.[WWI City ID]
	and [Integration].[City_Staging].[Valid From] = LocationHolder.[Valid From]

	DROP TABLE LocationHolder

	'
	EXEC sp_executesql @Sql
END