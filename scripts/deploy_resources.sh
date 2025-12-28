#!/bin/bash

# Declaración de variables de entorno
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-consumo-energetico-${ACCOUNT_ID}"
ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

echo "Usando Bucket: $BUCKET_NAME y Role: $ROLE_ARN"


# =======================================
# ======== SECCIÓN: Kinesis & S3 ========
# =======================================

# Crear el bucket de S3
aws s3 mb s3://$BUCKET_NAME

# Crear carpetas del bucket (objetos vacíos con / al final)
aws s3api put-object --bucket $BUCKET_NAME --key raw/
aws s3api put-object --bucket $BUCKET_NAME --key raw/energy_consumption_five_minutes/
aws s3api put-object --bucket $BUCKET_NAME --key processed/
aws s3api put-object --bucket $BUCKET_NAME --key config/
aws s3api put-object --bucket $BUCKET_NAME --key scripts/
aws s3api put-object --bucket $BUCKET_NAME --key queries/
aws s3api put-object --bucket $BUCKET_NAME --key errors/

# Crear el stream de Kinesis
aws kinesis create-stream --stream-name energy-stream --shard-count 1


# =======================================
# ======== SECCIÓN: FIREHOSE ========
# =======================================

# Crear el zip de la lambda
python -c "import zipfile, sys; z=zipfile.ZipFile('firehose.zip', 'w'); z.write(sys.argv[1]); z.close()" "firehose.py"

# Crear la función lambda
aws lambda create-function \
    --function-name energy-firehose-lambda \
    --runtime python3.12 \
    --role $ROLE_ARN \
    --handler firehose.lambda_handler \
    --zip-file fileb://firehose.zip \
    --timeout 60 \
    --memory-size 128

# Actualizar la función lambda
aws lambda update-function-code \
    --function-name energy-firehose-lambda \
    --zip-file fileb://firehose.zip

# Obtener el ARN de la función lambda
LAMBDA_ARN=$(aws lambda get-function --function-name energy-firehose-lambda --query 'Configuration.FunctionArn' --output text)

# Crear el delivery stream
aws firehose create-delivery-stream \
    --delivery-stream-name energy-delivery-stream \
    --delivery-stream-type KinesisStreamAsSource \
    --kinesis-stream-source-configuration "KinesisStreamARN=arn:aws:kinesis:$AWS_REGION:$ACCOUNT_ID"":stream/energy-stream,RoleARN=$ROLE_ARN" \
    --extended-s3-destination-configuration '{
        "BucketARN": "arn:aws:s3:::'"$BUCKET_NAME"'",
        "RoleARN": "'"$ROLE_ARN"'",
        "Prefix": "raw/energy_consumption_five_minutes/processing_date=!{partitionKeyFromLambda:processing_date}/",
        "ErrorOutputPrefix": "errors/!{firehose:error-output-type}/",
        "BufferingHints": {
            "SizeInMBs": 64,
            "IntervalInSeconds": 60
        },
        "DynamicPartitioningConfiguration": {
            "Enabled": true,
            "RetryOptions": {
                "DurationInSeconds": 300
            }
        },
        "ProcessingConfiguration": {
            "Enabled": true,
            "Processors": [
                {
                    "Type": "Lambda",
                    "Parameters": [
                        {
                            "ParameterName": "LambdaArn",
                            "ParameterValue": "'"$LAMBDA_ARN"'"
                        },
                        {
                            "ParameterName": "BufferSizeInMBs",
                            "ParameterValue": "1"
                        },
                        {
                            "ParameterName": "BufferIntervalInSeconds",
                            "ParameterValue": "60"
                        }
                    ]
                }
            ]
        }
    }'


# =======================================
# ============ SECCIÓN: GLUE ============
# =======================================

# Crear la base de datos de Glue
aws glue create-database --database-input "{\"Name\":\"energy_db\"}"

# Crear el crawler de Glue
aws glue create-crawler \
    --name energy-raw-crawler \
    --role $ROLE_ARN \
    --database-name energy_db \
    --targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET_NAME/raw/energy_consumption_five_minutes\"}]}"

python kinesis.py
sleep 60

aws glue start-crawler --name energy-raw-crawler


# =======================================
# ============ SECCIÓN: GLUE ETL =========
# =======================================

# Subir los scripts de ETL a S3
aws s3 cp energy_aggregation_daily.py s3://$BUCKET_NAME/scripts/
aws s3 cp energy_aggregation_monthly.py s3://$BUCKET_NAME/scripts/

# Variables de entorno
DATABASE="energy_db"
TABLE="energy_consumption_five_minutes"
DAILY_OUTPUT="s3://$BUCKET_NAME/processed/energy_consumption_daily/"
MONTHLY_OUTPUT="s3://$BUCKET_NAME/processed/energy_consumption_monthly/"

# Creación de los Jobs de Glue
aws glue create-job \
    --name energy-monthly-aggregation \
    --role $ROLE_ARN \
    --command '{
        "Name": "glueetl",
        "ScriptLocation": "s3://'"$BUCKET_NAME"'/scripts/energy_aggregation_monthly.py",
        "PythonVersion": "3"
    }' \
    --default-arguments '{
        "--database": "'"$DATABASE"'",
        "--table": "'"$TABLE"'",
        "--output_path": "s3://'"$BUCKET_NAME"'/processed/energy_consumption_monthly/",
        "--enable-continuous-cloudwatch-log": "true",
        "--spark-event-logs-path": "s3://'"$BUCKET_NAME"'/logs/"
    }' \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X"

aws glue create-job \
    --name energy-daily-aggregation \
    --role $ROLE_ARN \
    --command '{
        "Name": "glueetl",
        "ScriptLocation": "s3://'"$BUCKET_NAME"'/scripts/energy_aggregation_daily.py",
        "PythonVersion": "3"
    }' \
    --default-arguments '{
        "--database": "'"$DATABASE"'",
        "--table": "'"$TABLE"'",
        "--output_path": "s3://'"$BUCKET_NAME"'/processed/energy_consumption_daily/",
        "--enable-continuous-cloudwatch-log": "true",
        "--spark-event-logs-path": "s3://'"$BUCKET_NAME"'/logs/"
    }' \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X"

echo ""
echo "Esperando a que el crawler 'energy-raw-crawler' termine..."
while true; do
    CRAWLER_STATE=$(aws glue get-crawler --name energy-raw-crawler --query "Crawler.State" --output text)
    echo "Estado del Crawler: $CRAWLER_STATE"
    
    if [ "$CRAWLER_STATE" == "READY" ]; then
        echo "Crawler finalizado."
        break
    fi
    
    sleep 30
done

# Comenzar la ejecución de los Jobs
aws glue start-job-run --job-name energy-daily-aggregation
aws glue start-job-run --job-name energy-monthly-aggregation

# Comprobar el estado de los Jobs
aws glue get-job-runs --job-name energy-daily-aggregation --max-items 1
aws glue get-job-runs --job-name energy-monthly-aggregation --max-items 1