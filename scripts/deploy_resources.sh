#!/bin/bash
# Declaración de variables de entorno
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-laureates-${ACCOUNT_ID}"
ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)

echo "=========== 🔹 CONFIGURACIÓN INICIAL 🔹 ==========="
echo "1️⃣  Región de AWS:     $AWS_REGION"
echo "2️⃣  Bucket:            $BUCKET_NAME"
echo "3️⃣  Role:              $ROLE_ARN"

add_blankspaces() {
    echo ""
    echo "==========================================="
    echo ""
}

execute_command() {
    local informative_message="$1"
    local success_message="$2"
    local error_message="$3"
    shift 3
    
    add_blankspaces
    echo "$informative_message"
    "$@" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✅ $success_message"
    else
        echo "⚠️ $error_message"
        exit 1
    fi
}


# =======================================
# ======== SECCIÓN: Kinesis & S3 ========
# =======================================

# Crear el bucket de S3
execute_command "Creando el bucket de S3 $BUCKET_NAME..." \
                "¡Bucket de S3 creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el bucket de S3." \
                aws s3 mb s3://$BUCKET_NAME

# Crear carpetas del bucket (objetos vacíos con / al final)
execute_command "Creando estructura de carpetas en S3..." \
                "¡Estructura de carpetas creada correctamente!" \
                "AVISO: Ha ocurrido un error al crear la estructura de carpetas." \
                bash -c "aws s3api put-object --bucket $BUCKET_NAME --key raw/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key raw/laureates/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key processed/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key config/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key scripts/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key queries/ && \
                 aws s3api put-object --bucket $BUCKET_NAME --key errors/"

# Crear el stream de Kinesis
execute_command "Creando el stream de Kinesis: laureates-stream..." \
                "¡Stream de Kinesis creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el stream de Kinesis." \
                aws kinesis create-stream --stream-name laureates-stream --shard-count 1


# =======================================
# ========== SECCIÓN: FIREHOSE ==========
# =======================================

# Crear el zip de la lambda
execute_command "Empaquetando la función Lambda..." \
                "¡Paquete creado correctamente!" \
                "AVISO: Ha ocurrido un error al empaquetar la función Lambda." \
                python -c "import zipfile, sys; z=zipfile.ZipFile('firehose.zip', 'w'); z.write(sys.argv[1]); z.close()" "firehose.py"

# Crear la función lambda
execute_command "Creando la función Lambda: laureates-firehose-lambda..." \
                "¡Función Lambda creada correctamente!" \
                "AVISO: Ha ocurrido un error al crear la función Lambda." \
                aws lambda create-function \
                    --function-name laureates-firehose-lambda \
                    --runtime python3.12 \
                    --role "$ROLE_ARN" \
                    --handler firehose.lambda_handler \
                    --zip-file fileb://firehose.zip \
                    --timeout 60 \
                    --memory-size 128

# Actualizar la función lambda
execute_command "Actualizando el código de la función Lambda..." \
                "¡Código de Lambda actualizado correctamente!" \
                "AVISO: Ha ocurrido un error al actualizar el código de Lambda." \
                aws lambda update-function-code \
                    --function-name laureates-firehose-lambda \
                    --zip-file fileb://firehose.zip

# Obtener el ARN de la función lambda
LAMBDA_ARN=$(aws lambda get-function --function-name laureates-firehose-lambda --query 'Configuration.FunctionArn' --output text)
if [ -z "$LAMBDA_ARN" ]; then
    echo "AVISO: Ha ocurrido un error al obtener el ARN de la función Lambda."
    exit 1
fi

# Crear el delivery stream
execute_command "Creando Firehose Delivery Stream..." \
                "¡Firehose Delivery Stream creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el Firehose Delivery Stream." \
                aws firehose create-delivery-stream \
                    --delivery-stream-name laureates-delivery-stream \
                    --delivery-stream-type KinesisStreamAsSource \
                    --kinesis-stream-source-configuration "KinesisStreamARN=arn:aws:kinesis:$AWS_REGION:$ACCOUNT_ID"":stream/laureates-stream,RoleARN=$ROLE_ARN" \
                    --extended-s3-destination-configuration "{
                \"BucketARN\": \"arn:aws:s3:::$BUCKET_NAME\",
                \"RoleARN\": \"$ROLE_ARN\",
                \"Prefix\": \"raw/laureates/processing_date=!{partitionKeyFromLambda:processing_date}/\",
                \"ErrorOutputPrefix\": \"errors/!{firehose:error-output-type}/\",
                \"BufferingHints\": { \"SizeInMBs\": 64, \"IntervalInSeconds\": 60 },
                \"DynamicPartitioningConfiguration\": { \"Enabled\": true, \"RetryOptions\": { \"DurationInSeconds\": 300 } },
                \"ProcessingConfiguration\": { \"Enabled\": true, \"Processors\": [
                        { \"Type\": \"Lambda\", \"Parameters\": [
                                { \"ParameterName\": \"LambdaArn\", \"ParameterValue\": \"$LAMBDA_ARN\" },
                                { \"ParameterName\": \"BufferSizeInMBs\", \"ParameterValue\": \"1\" },
                                { \"ParameterName\": \"BufferIntervalInSeconds\", \"ParameterValue\": \"60\" }
                            ]
                        }
                    ]
                }
            }"


# =======================================
# ============ SECCIÓN: GLUE ============
# =======================================

# Crear la base de datos de Glue
execute_command "Creando la base de datos de Glue: laureates_db..." \
                "¡Base de datos de Glue creada correctamente!" \
                "AVISO: Ha ocurrido un error al crear la base de datos de Glue." \
                aws glue create-database --database-input "{\"Name\":\"laureates_db\"}"

# Crear el crawler de Glue
execute_command "Creando el crawler de Glue: laureates-raw-crawler..." \
                "¡Glue Crawler creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el crawler de Glue." \
                aws glue create-crawler \
                    --name laureates-raw-crawler \
                    --role "$ROLE_ARN" \
                    --database-name laureates_db \
                    --targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET_NAME/raw/laureates\"}]}"

# Crear el crawler de Glue para datos procesados
execute_command "Creando el crawler de Glue para procesados: laureates-processed-crawler..." \
                "¡Glue Crawler de procesados creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el crawler de Glue para procesados." \
                aws glue create-crawler \
                    --name laureates-processed-crawler \
                    --role "$ROLE_ARN" \
                    --database-name laureates_db \
                    --targets "{\"S3Targets\": [{\"Path\": \"s3://$BUCKET_NAME/processed/\"}]}"

add_blankspaces
echo "Ejecutando el producer de Kinesis (tardará unos momentos)..."
python kinesis.py
if [[ $? -eq 0 ]]; then
    echo "✅ ¡Datos enviados a Kinesis!"
else
    echo "⚠️ AVISO: Ha ocurrido un error al ejecutar el producer de Kinesis."
    exit 1
fi
sleep 60

execute_command "Iniciando el crawler 'laureates-raw-crawler'..." \
                "¡Glue Crawler iniciado!" \
                "AVISO: Ha ocurrido un error al iniciar el crawler de Glue." \
                aws glue start-crawler --name laureates-raw-crawler


# =======================================
# ========== SECCIÓN: GLUE ETL ==========
# =======================================

# Subir los scripts de ETL a S3
execute_command "Subiendo scripts ETL a S3..." \
                "¡Scripts ETL subidos correctamente!" \
                "AVISO: Ha ocurrido un error al subir scripts ETL." \
                bash -c "aws s3 cp jobs/nobel_aggregation_gender.py s3://$BUCKET_NAME/scripts/ && \
                 aws s3 cp jobs/nobel_aggregation_decadal.py s3://$BUCKET_NAME/scripts/ && \
                 aws s3 cp jobs/nobel_aggregation_by_country.py s3://$BUCKET_NAME/scripts/"

# Variables de entorno
DATABASE="laureates_db"
TABLE="laureates"
GENDER_OUTPUT="s3://$BUCKET_NAME/processed/laureates_gender/"
DECADAL_OUTPUT="s3://$BUCKET_NAME/processed/laureates_decadal/"
COUNTRY_OUTPUT="s3://$BUCKET_NAME/processed/laureates_country/"

# Creación de los Jobs de Glue
execute_command "¡Creando primer Job Glue! ---> 1️⃣  Nobel Gender Aggregation..." \
                "¡Job Nobel Gender Aggregation creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el Job nobel-gender-aggregation." \
                aws glue create-job \
                    --name nobel-gender-aggregation \
                    --role "$ROLE_ARN" \
                    --command "{
                        \"Name\": \"glueetl\",
                        \"ScriptLocation\": \"s3://$BUCKET_NAME/scripts/nobel_aggregation_gender.py\",
                        \"PythonVersion\": \"3\"
                    }" \
                    --default-arguments "{
                        \"--database\": \"$DATABASE\",
                        \"--table\": \"$TABLE\",
                        \"--output_path\": \"s3://$BUCKET_NAME/processed/laureates_by_gender/\",
                        \"--enable-continuous-cloudwatch-log\": \"true\",
                        \"--spark-event-logs-path\": \"s3://$BUCKET_NAME/logs/\"
                    }" \
                    --glue-version "4.0" \
                    --number-of-workers 2 \
                    --worker-type "G.1X"

execute_command "¡Creando segundo Job Glue! ---> 2️⃣  Nobel Decadal Aggregation..." \
                "¡Job Nobel Decadal Aggregation creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el Job nobel-decadal-aggregation." \
                aws glue create-job \
                    --name nobel-decadal-aggregation \
                    --role "$ROLE_ARN" \
                    --command "{
                        \"Name\": \"glueetl\",
                        \"ScriptLocation\": \"s3://$BUCKET_NAME/scripts/nobel_aggregation_decadal.py\",
                        \"PythonVersion\": \"3\"
                    }" \
                    --default-arguments "{
                        \"--database\": \"$DATABASE\",
                        \"--table\": \"$TABLE\",
                        \"--output_path\": \"s3://$BUCKET_NAME/processed/laureates_by_decadal/\",
                        \"--enable-continuous-cloudwatch-log\": \"true\",
                        \"--spark-event-logs-path\": \"s3://$BUCKET_NAME/logs/\"
                    }" \
                    --glue-version "4.0" \
                    --number-of-workers 2 \
                    --worker-type "G.1X"

execute_command "¡Creando tercer Job Glue! ---> 3️⃣  Nobel Country Aggregation..." \
                "¡Job Nobel Country Aggregation creado correctamente!" \
                "AVISO: Ha ocurrido un error al crear el Job nobel-country-aggregation." \
                aws glue create-job \
                    --name nobel-country-aggregation \
                    --role "$ROLE_ARN" \
                    --command "{
                        \"Name\": \"glueetl\",
                        \"ScriptLocation\": \"s3://$BUCKET_NAME/scripts/nobel_aggregation_by_country.py\",
                        \"PythonVersion\": \"3\"
                    }" \
                    --default-arguments "{
                        \"--database\": \"$DATABASE\",
                        \"--table\": \"$TABLE\",
                        \"--output_path\": \"s3://$BUCKET_NAME/processed/laureates_by_country/\",
                        \"--enable-continuous-cloudwatch-log\": \"true\",
                        \"--spark-event-logs-path\": \"s3://$BUCKET_NAME/logs/\"
                    }" \
                    --glue-version "4.0" \
                    --number-of-workers 2 \
                    --worker-type "G.1X"

add_blankspaces
echo "Esperando a que el crawler 'laureates-raw-crawler' termine..."
while true; do
    CRAWLER_STATE=$(aws glue get-crawler --name laureates-raw-crawler --query "Crawler.State" --output text)
    echo "Estado del Crawler: $CRAWLER_STATE"
    
    if [ "$CRAWLER_STATE" == "READY" ]; then
        echo ""
        echo "Crawler finalizado."
        break
    fi
    
    sleep 30
done

# Comenzar la ejecución de los Jobs
execute_command "Iniciando Jobs de Glue..." \
                "¡Jobs iniciados correctamente!" \
                "AVISO: Ha ocurrido un error al iniciar los Jobs de Glue." \
                bash -c "aws glue start-job-run --job-name nobel-gender-aggregation && \
                 aws glue start-job-run --job-name nobel-decadal-aggregation && \
                 aws glue start-job-run --job-name nobel-country-aggregation"

# Comprobar el estado de los Jobs
add_blankspaces
echo "Se debe esperar a que los Jobs de Glue finalicen para iniciar el crawler de procesados..."

while true; do
    STATUS_GENDER=$(aws glue get-job-runs --job-name nobel-gender-aggregation --max-items 1 --query "JobRuns[0].JobRunState" --output text)
    STATUS_DECADAL=$(aws glue get-job-runs --job-name nobel-decadal-aggregation --max-items 1 --query "JobRuns[0].JobRunState" --output text)
    STATUS_COUNTRY=$(aws glue get-job-runs --job-name nobel-country-aggregation --max-items 1 --query "JobRuns[0].JobRunState" --output text)

    echo " ==========> ESTADO DE LOS JOBS"
    echo "Gender: $STATUS_GENDER || Decadal: $STATUS_DECADAL || Country: $STATUS_COUNTRY"
    echo ""

    if [[ "$STATUS_GENDER" == "SUCCEEDED" && "$STATUS_DECADAL" == "SUCCEEDED" && "$STATUS_COUNTRY" == "SUCCEEDED" ]]; then
        echo "✅ Todos los Jobs finalizaron correctamente."
        break
    fi
    
    if [[ "$STATUS_GENDER" =~ (FAILED|TIMEOUT|STOPPED) || "$STATUS_DECADAL" =~ (FAILED|TIMEOUT|STOPPED) || "$STATUS_COUNTRY" =~ (FAILED|TIMEOUT|STOPPED) ]]; then
        echo "❌ Uno o más Jobs fallaron o se detuvieron. Estado: ($STATUS_GENDER, $STATUS_DECADAL, $STATUS_COUNTRY)"
        exit 1
    fi
    
    sleep 30
done

execute_command "Iniciando el crawler de procesados 'laureates-processed-crawler'..." \
                "¡Glue Crawler de procesados iniciado!" \
                "AVISO: Ha ocurrido un error al iniciar el crawler de procesados." \
                aws glue start-crawler --name laureates-processed-crawler

add_blankspaces
echo "🎉  F I N   D E L   D E S P L I E G U E  🎉"
echo ""
