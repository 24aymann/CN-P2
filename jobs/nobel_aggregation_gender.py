"""Job that shows the number of laureates per gender and category."""
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
    
    # Group by year, category, and sex
    aggregated_df = df.groupBy("year", "category", "sex") \
        .agg(count("*").alias("total_laureates")) \
        .orderBy("year", "category", "sex")
    
    output_dynamic_frame = DynamicFrame.fromDF(aggregated_df, glueContext, "output")
    
    logger.info(f"🔹Records added: {aggregated_df.count()}")
    
    # Write to S3 in Parquet format
    glueContext.write_dynamic_frame.from_options(
        frame=output_dynamic_frame,
        connection_type="s3",
        connection_options={
            "path": output_path,
            "partitionKeys": ["year"]
        },
        format="parquet",
        format_options={"compression": "snappy"}
    )
    
    logger.info("✅Job completed successfully.")


if __name__ == "__main__":
    main()
