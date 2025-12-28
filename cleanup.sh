#!/bin/bash
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-consumo-energetico-${ACCOUNT_ID}"

echo "Iniciando limpieza de recursos..."
echo "Cuenta AWS: $ACCOUNT_ID"
echo "Bucket Objetivo: $BUCKET_NAME"

#--- GLUE ETL
echo "Eliminando Glue Jobs..."
aws glue delete-job --job-name energy-daily-aggregation 2>/dev/null || echo "Glue Job 'energy-daily-aggregation' no existe o ya fue eliminado."
aws glue delete-job --job-name energy-monthly-aggregation 2>/dev/null || echo "Glue Job 'energy-monthly-aggregation' no existe o ya fue eliminado."

#--- GLUE CRAWLER & DATABASE
echo "Eliminando Glue Crawler..."
aws glue delete-crawler --name energy-raw-crawler 2>/dev/null || echo "Glue Crawler 'energy-raw-crawler' no existe o ya fue eliminado."

echo "Eliminando Glue Database..."
# Se intenta borrar la base de datos. Si tiene tablas, hay que borrarlas primero manualmente o confiar en que delete-database las borre (en CLI a veces requiere limpieza).
# Sin embargo, delete-database en AWS CLI suele borrar la metadata del catálogo.
aws glue delete-database --name energy_db 2>/dev/null || echo "Glue Database 'energy_db' no existe o ya fue eliminada."

#--- FIREHOSE
echo "Eliminando Firehose Delivery Stream..."
aws firehose delete-delivery-stream --delivery-stream-name energy-delivery-stream 2>/dev/null || echo "Firehose Stream 'energy-delivery-stream' no existe o ya fue eliminado."

#--- LAMBDA
echo "Eliminando Lambda Function..."
aws lambda delete-function --function-name energy-firehose-lambda 2>/dev/null || echo "Lambda Function 'energy-firehose-lambda' no existe o ya fue eliminada."

#--- KINESIS
echo "Eliminando Kinesis Stream..."
aws kinesis delete-stream --stream-name energy-stream 2>/dev/null || echo "Kinesis Stream 'energy-stream' no existe o ya fue eliminado."
# Esperar un poco para asegurar que Kinesis y Firehose liberen referencias si es necesario, aunque en eliminación generalmente no bloquea el bucket inmediatamente si se usa force.

#--- S3
echo "Eliminando S3 Bucket y todo su contenido..."
aws s3 rb "s3://$BUCKET_NAME" --force 2>/dev/null || echo "Bucket '$BUCKET_NAME' no existe o ya fue eliminado."

#--- LOCAL FILES
echo "Eliminando archivos temporales locales..."
rm -f firehose.zip

echo "Limpieza completada exitosamente."
