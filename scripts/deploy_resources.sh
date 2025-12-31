#!/bin/bash

# Declaración de variables de entorno
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-laureates-${ACCOUNT_ID}"
ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

echo ""
echo "=========== 🔹 CONFIGURACIÓN INICIAL 🔹 ==========="
echo "1️⃣  Región de AWS:     $AWS_REGION"
echo "2️⃣  Bucket:            $BUCKET_NAME"
echo "3️⃣  Role:              $ROLE_ARN"
echo ""


# =======================================
# ======== SECCIÓN: Kinesis & S3 ========
# =======================================

# Crear el bucket de S3
aws s3 mb s3://$BUCKET_NAME > /dev/null

# Crear carpetas del bucket (objetos vacíos con / al final)
aws s3api put-object --bucket $BUCKET_NAME --key raw/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key raw/laureates/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key processed/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key config/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key scripts/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key queries/ > /dev/null
aws s3api put-object --bucket $BUCKET_NAME --key errors/ > /dev/null

# Crear el stream de Kinesis
aws kinesis create-stream --stream-name laureates-stream --shard-count 1 > /dev/null


# =======================================
# ========== SECCIÓN: FIREHOSE ==========
# =======================================

# Crear el zip de la lambda
python -c "import zipfile, sys; z=zipfile.ZipFile('firehose.zip', 'w'); z.write(sys.argv[1]); z.close()" "firehose.py"

# Crear la función lambda
aws lambda create-function \
    --function-name laureates-firehose-lambda \
    --runtime python3.12 \
    --role $ROLE_ARN \
    --handler firehose.lambda_handler \
    --zip-file fileb://firehose.zip \
    --timeout 60 \
    --memory-size 128 > /dev/null

# Actualizar la función lambda
aws lambda update-function-code \
    --function-name laureates-firehose-lambda \
    --zip-file fileb://firehose.zip > /dev/null

# Obtener el ARN de la función lambda
LAMBDA_ARN=$(aws lambda get-function --function-name laureates-firehose-lambda --query 'Configuration.FunctionArn' --output text)

# Crear el delivery stream
aws firehose create-delivery-stream \
    --delivery-stream-name laureates-delivery-stream \
    --delivery-stream-type KinesisStreamAsSource \
    --kinesis-stream-source-configuration "KinesisStreamARN=arn:aws:kinesis:$AWS_REGION:$ACCOUNT_ID"":stream/laureates-stream,RoleARN=$ROLE_ARN" \
    --extended-s3-destination-configuration '{
        "BucketARN": "arn:aws:s3:::'"$BUCKET_NAME"'",
        "RoleARN": "'"$ROLE_ARN"'",
        "Prefix": "raw/laureates/processing_date=!{partitionKeyFromLambda:processing_date}/",
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
    }' > /dev/null


# =======================================
# ============ SECCIÓN: GLUE ============
# =======================================

# Crear la base de datos de Glue
aws glue create-database --database-input "{\"Name\":\"laureates_db\"}" > /dev/null

# Crear el crawler de Glue
aws glue create-crawler \
    --name laureates-raw-crawler \
    --role $ROLE_ARN \
    --database-name laureates_db \
    --targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET_NAME/raw/laureates\"}]}" > /dev/null

python kinesis.py
sleep 60

aws glue start-crawler --name laureates-raw-crawler > /dev/null


# =======================================
# ========== SECCIÓN: GLUE ETL ==========
# =======================================

# Subir los scripts de ETL a S3
aws s3 cp jobs/nobel_aggregation_gender.py s3://$BUCKET_NAME/scripts/ > /dev/null
aws s3 cp jobs/nobel_aggregation_decadal.py s3://$BUCKET_NAME/scripts/ > /dev/null
aws s3 cp jobs/nobel_aggregation_by_country.py s3://$BUCKET_NAME/scripts/ > /dev/null

# Variables de entorno
DATABASE="laureates_db"
TABLE="laureates"
GENDER_OUTPUT="s3://$BUCKET_NAME/processed/laureates_gender/"
DECADAL_OUTPUT="s3://$BUCKET_NAME/processed/laureates_decadal/"
COUNTRY_OUTPUT="s3://$BUCKET_NAME/processed/laureates_country/"

# Creación de los Jobs de Glue
aws glue create-job \
    --name nobel-gender-aggregation \
    --role $ROLE_ARN \
    --command '{
        "Name": "glueetl",
        "ScriptLocation": "s3://'"$BUCKET_NAME"'/scripts/nobel_aggregation_gender.py",
        "PythonVersion": "3"
    }' \
    --default-arguments '{
        "--database": "'"$DATABASE"'",
        "--table": "'"$TABLE"'",
        "--output_path": "s3://'"$BUCKET_NAME"'/processed/laureates_by_gender/",
        "--enable-continuous-cloudwatch-log": "true",
        "--spark-event-logs-path": "s3://'"$BUCKET_NAME"'/logs/"
    }' \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" > /dev/null

aws glue create-job \
    --name nobel-decadal-aggregation \
    --role $ROLE_ARN \
    --command '{
        "Name": "glueetl",
        "ScriptLocation": "s3://'"$BUCKET_NAME"'/scripts/nobel_aggregation_decadal.py",
        "PythonVersion": "3"
    }' \
    --default-arguments '{
        "--database": "'"$DATABASE"'",
        "--table": "'"$TABLE"'",
        "--output_path": "s3://'"$BUCKET_NAME"'/processed/laureates_by_decadal/",
        "--enable-continuous-cloudwatch-log": "true",
        "--spark-event-logs-path": "s3://'"$BUCKET_NAME"'/logs/"
    }' \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" > /dev/null

aws glue create-job \
    --name nobel-country-aggregation \
    --role $ROLE_ARN \
    --command '{
        "Name": "glueetl",
        "ScriptLocation": "s3://'"$BUCKET_NAME"'/scripts/nobel_aggregation_by_country.py",
        "PythonVersion": "3"
    }' \
    --default-arguments '{
        "--database": "'"$DATABASE"'",
        "--table": "'"$TABLE"'",
        "--output_path": "s3://'"$BUCKET_NAME"'/processed/laureates_by_country/",
        "--enable-continuous-cloudwatch-log": "true",
        "--spark-event-logs-path": "s3://'"$BUCKET_NAME"'/logs/"
    }' \
    --glue-version "4.0" \
    --number-of-workers 2 \
    --worker-type "G.1X" > /dev/null

echo ""
echo "Esperando a que el crawler 'laureates-raw-crawler' termine..."
while true; do
    CRAWLER_STATE=$(aws glue get-crawler --name laureates-raw-crawler --query "Crawler.State" --output text)
    echo "Estado del Crawler: $CRAWLER_STATE"
    
    if [ "$CRAWLER_STATE" == "READY" ]; then
        echo "Crawler finalizado."
        break
    fi
    
    sleep 30
done

# Comenzar la ejecución de los Jobs
aws glue start-job-run --job-name nobel-gender-aggregation > /dev/null
aws glue start-job-run --job-name nobel-decadal-aggregation > /dev/null
aws glue start-job-run --job-name nobel-country-aggregation > /dev/null

# Comprobar el estado de los Jobs
aws glue get-job-runs --job-name nobel-gender-aggregation --max-items 1 > /dev/null
aws glue get-job-runs --job-name nobel-decadal-aggregation --max-items 1 > /dev/null
aws glue get-job-runs --job-name nobel-country-aggregation --max-items 1 > /dev/null
