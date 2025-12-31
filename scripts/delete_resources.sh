#!/bin/bash
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-laureates-${ACCOUNT_ID}"

echo "Iniciando limpieza de recursos..."
echo "Cuenta AWS: $ACCOUNT_ID"
echo "Bucket Objetivo: $BUCKET_NAME"
echo ""
echo "================================="
echo ""

# ===> GLUE ETL
echo "Eliminando Glue Jobs..."
aws glue delete-job --job-name nobel-gender-aggregation 2>/dev/null || echo "El Job de Glue 'nobel-gender-aggregation' no existe o ya fue eliminado."
aws glue delete-job --job-name nobel-decadal-aggregation 2>/dev/null || echo "El Job de Glue 'nobel-decadal-aggregation' no existe o ya fue eliminado."
aws glue delete-job --job-name nobel-country-aggregation 2>/dev/null || echo "El Job de Glue 'nobel-country-aggregation' no existe o ya fue eliminado."

echo ""
echo "================================="
echo ""

# ===> GLUE CRAWLER & DATABASE
echo "Eliminando el Glue Crawler..."
aws glue delete-crawler --name laureates-raw-crawler 2>/dev/null || echo "El Crawler de Glue 'laureates-raw-crawler' no existe o ya fue eliminado."

echo "Eliminando la Glue Database..."
aws glue delete-database --name laureates_db 2>/dev/null || echo "La Base de Datos de Glue 'laureates_db' no existe o ya fue eliminada."

echo ""
echo "================================="
echo ""

# ===> FIREHOSE
echo "Eliminando el Firehose Delivery Stream..."
aws firehose delete-delivery-stream --delivery-stream-name laureates-delivery-stream 2>/dev/null || echo "El Stream de Firehose 'laureates-delivery-stream' no existe o ya fue eliminado."

echo ""
echo "================================="
echo ""

# ===> LAMBDA
echo "Eliminando la Lambda Function..."
aws lambda delete-function --function-name laureates-firehose-lambda 2>/dev/null || echo "La Lambda Function 'laureates-firehose-lambda' no existe o ya fue eliminada."

echo ""
echo "================================="
echo ""

# ===> KINESIS
echo "Eliminando el Kinesis Stream..."
aws kinesis delete-stream --stream-name laureates-stream 2>/dev/null || echo "El Stream de Kinesis 'laureates-stream' no existe o ya fue eliminado."

echo ""
echo "================================="
echo ""

# ===> S3
echo "Eliminando el S3 Bucket y todo su contenido..."
aws s3 rb "s3://$BUCKET_NAME" --force 2>/dev/null || echo "El Bucket '$BUCKET_NAME' no existe o ya fue eliminado."

echo ""
echo "================================="
echo ""

# ===> LOCAL FILES
echo "Eliminando los archivos temporales locales..."
rm -f firehose.zip

echo "¡Hecho! Limpieza completada exitosamente."
