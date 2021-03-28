import boto3
import requests
import logging

def lambda_handler(event, context):
    
    api = requests.get('https://api.punkapi.com/v2/beers/random')

    # Verifica que a requisicao obteve sucesso
    if api.status_code != 200:
        raise ValueError("Erro na obtencao dos dados via API")

    # Conexao com o kinesis stream
    kinesis_client = boto3.client('kinesis', region_name='us-east-1')
    
    # Preparacao dos registros para enviar ao kinesis
    api_dados = api.json()
    
    # Lista com todos os registros a serem enviados ao kineses
    registrosKinesis = []
    
    for registro in api_dados:
        chave = registro['id']
        registroKinesis = { 'Data':str(registro),'PartitionKey': str(chave) }
        registrosKinesis.append(registroKinesis)    
        
    response = kinesis_client.put_records(
        Records=registrosKinesis,
        StreamName='kinesis-stream'
    )
    
    return(registrosKinesis)