import boto3
import json
import time
from loguru import logger
import datetime

# CONFIGURACIÓN
STREAM_NAME = 'energy-stream'
REGION = 'us-east-1' # Cambia si usas otra región
INPUT_FILE = 'datos.json'

kinesis = boto3.client('kinesis', region_name=REGION)

def load_data(file_path):
    with open(file_path, 'r') as f:
        return json.load(f)

def run_producer():
    data = load_data(INPUT_FILE)
    records_sent = 0
    
    # El JSON tiene una estructura 'included' donde están los arrays de valores
    series_list = data.get('included', [])
    
    logger.info(f"Iniciando transmisión al stream: {STREAM_NAME}...")
    
    # Iteramos sobre los 3 tipos de demanda (Real, Programada, Prevista)
    for serie in series_list:
        tipo_demanda = serie['attributes']['title']
        valores = serie['attributes']['values']
        
        for registro in valores:
            # Estructura del mensaje a enviar
            payload = {
                'tipo': tipo_demanda,
                'valor': registro['value'],
                'timestamp_origen': registro['datetime'],
                'porcentaje': registro['percentage']
            }
            
            # Enviar a Kinesis
            response = kinesis.put_record(
                StreamName=STREAM_NAME,
                Data=json.dumps(payload),
                PartitionKey=tipo_demanda # Usamos el tipo como clave de partición
            )
            
            records_sent += 1
            logger.info(f"Registro enviado al shard {response['ShardId']} con SequenceNumber {response['SequenceNumber']}")
            logger.info(f"Enviado [{tipo_demanda}]: {registro['value']} MW")
            
            # Pequeña pausa para simular streaming y no saturar de golpe
            time.sleep(0.1) 

    logger.info(f"Fin de la transmisión. Total registros enviados: {records_sent}")

if __name__ == '__main__':
    run_producer()