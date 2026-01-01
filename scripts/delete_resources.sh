#!/bin/bash
# Declaración de variables de entorno
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="datalake-laureates-${ACCOUNT_ID}"

echo "========== 🗑️  Iniciando limpieza de recursos... 🗑️ =========="
echo "Cuenta AWS:       $ACCOUNT_ID"
echo "Bucket Objetivo:  $BUCKET_NAME"

add_blankspaces() {
    echo ""
    echo "========================================="
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
    fi
}


# =======================================
# ========== SECCIÓN: GLUE ETL ==========
# =======================================

execute_command "Eliminando el Job de Glue: Nobel Gender Aggregation..." \
                "Job eliminado correctamente (o ya no existía)." \
                "AVISO: El Job no existe o ya fue eliminado previamente." \
                aws glue delete-job --job-name nobel-gender-aggregation

execute_command "Eliminando el Job de Glue: Nobel Decadal Aggregation..." \
                "Job eliminado correctamente (o ya no existía)." \
                "AVISO: El Job no existe o ya fue eliminado previamente." \
                aws glue delete-job --job-name nobel-decadal-aggregation

execute_command "Eliminando el Job de Glue: Nobel Country Aggregation..." \
                "Job eliminado correctamente (o ya no existía)." \
                "AVISO: El Job no existe o ya fue eliminado previamente." \
                aws glue delete-job --job-name nobel-country-aggregation


# =======================================
# ===== SECCIÓN: GLUE CRAWLER & DB ======
# =======================================

execute_command "Eliminando el Crawler de Glue..." \
                "El crawler fue eliminado correctamente (o ya no existía)." \
                "AVISO: El Crawler no existe o ya fue eliminado previamente." \
                aws glue delete-crawler --name laureates-raw-crawler

execute_command "Eliminando el Crawler de Glue de procesados..." \
                "El crawler de procesados fue eliminado correctamente (o ya no existía)." \
                "AVISO: El Crawler de procesados no existe o ya fue eliminado previamente." \
                aws glue delete-crawler --name laureates-processed-crawler

execute_command "Eliminando la Glue Database..." \
                "La base de datos fue eliminada correctamente (o ya no existía)." \
                "AVISO: La Base de Datos no existe o ya fue eliminada previamente." \
                aws glue delete-database --name laureates_db


# =======================================
# ========== SECCIÓN: FIREHOSE ==========
# =======================================

execute_command "Eliminando el Firehose Delivery Stream..." \
                "El Stream de Firehose fue eliminado correctamente (o ya no existía)." \
                "AVISO: El Stream de Firehose no existe o ya fue eliminado previamente." \
                aws firehose delete-delivery-stream --delivery-stream-name laureates-delivery-stream

execute_command "Eliminando la Lambda Function..." \
                "La Lambda Function fue eliminada correctamente (o ya no existía)." \
                "AVISO: La Lambda Function no existe o ya fue eliminada previamente." \
                aws lambda delete-function --function-name laureates-firehose-lambda


# =======================================
# ======== SECCIÓN: Kinesis & S3 ========
# =======================================

execute_command "Eliminando el Kinesis Stream..." \
                "El Stream de Kinesis fue eliminado correctamente (o ya no existía)." \
                "AVISO: El Stream de Kinesis no existe o ya fue eliminado previamente." \
                aws kinesis delete-stream --stream-name laureates-stream

execute_command "Eliminando el S3 Bucket y todo su contenido..." \
                "El Bucket de S3 fue eliminado correctamente (o ya no existía)." \
                "AVISO: El Bucket de S3 no existe o ya fue eliminado previamente." \
                aws s3 rb "s3://$BUCKET_NAME" --force


# =======================================
# ======== SECCIÓN: LOCAL FILES =========
# =======================================

add_blankspaces
echo "Eliminando los archivos temporales locales..."
rm -f firehose.zip
echo "¡Hecho! Limpieza completada exitosamente."

add_blankspaces
echo "🎉  L I M P I E Z A   C O M P L E T A D A  🎉"
