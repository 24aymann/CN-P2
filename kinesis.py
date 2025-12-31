from loguru import logger
import boto3
import json
import time

# VARIABLES DE CONFIGURACIÓN
INPUT_FILE =    'nobel_laureates.json'
STREAM_NAME =   'laureates-stream'
REGION_NAME =   'us-east-1'

kinesis = boto3.client('kinesis', region_name=REGION_NAME)

def load_data(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        return json.load(file)

def run_producer():
    laureates_list = load_data(INPUT_FILE)
    records_sent = 0

    logger.info(f"❗ Iniciando transmisión al stream: {STREAM_NAME}...")

    # Se itera sobre todos los laureados
    for laureate in laureates_list:
        category = laureate.get('Category', 'Unknown')

        # Se envía a Kinesis el registro completo
        kinesis.put_record(
            StreamName=STREAM_NAME,
            Data=json.dumps(laureate),
            PartitionKey=category
        )

        records_sent += 1

        # Información para el log
        laureate_name = laureate.get('Full Name', 'Unknown')
        year = laureate.get('Year', 'N/A')

        # Indicador de registro enviado
        logger.info(f"( {year} - {category} ) ===> 🌟 {laureate_name} 🌟")

        # Pequeña pausa para simular streaming y no saturar de golpe
        time.sleep(0.1) 

    logger.info("")
    logger.info("✅¡La transmisión ha finalizado!✅")
    logger.info(f"Total de registros enviados: {records_sent}")


if __name__ == '__main__':
    run_producer()
