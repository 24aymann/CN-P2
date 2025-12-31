"""Job that shows the number of laureates per country and category."""
import sys
import logging
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.sql.functions import col, count
from awsglue.dynamicframe import DynamicFrame

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def main():
    # Get arguments that define the job
    args = getResolvedOptions(sys.argv, ['database', 'table', 'output_path'])
    database = args['database']
    table = args['table']
    output_path = args['output_path']
    
    logger.info(f"Database: {database}, Table: {table}, Output: {output_path}")
    
    # Initialize Contexts
    sc = SparkContext()
    glueContext = GlueContext(sc)
    
    # Read from Glue Catalog through GlueContext
    dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database=database,
        table_name=table
    )
    
    df = dynamic_frame.toDF()
    
    # Normalize column names
    for col_name in df.columns:
        new_col_name = col_name.lower().replace(" ", "_").strip()
        df = df.withColumnRenamed(col_name, new_col_name)
    
    # Group by birth country and category
    aggregated_df = df.filter(col("birth_country") != "") \
        .groupBy("birth_country", "category") \
        .agg(count("*").alias("total_laureates")) \
        .orderBy("birth_country", "category")
    
    output_dynamic_frame = DynamicFrame.fromDF(aggregated_df, glueContext, "output")
    
    logger.info(f"🔹Records added: {aggregated_df.count()}")
    
    # Write to S3 in Parquet format
    glueContext.write_dynamic_frame.from_options(
        frame=output_dynamic_frame,
        connection_type="s3",
        connection_options={
            "path": output_path,
            "partitionKeys": ["birth_country"] 
        },
        format="parquet",
        format_options={"compression": "snappy"}
    )
    
    logger.info("✅Job completed successfully.")

if __name__ == "__main__":
    main()
