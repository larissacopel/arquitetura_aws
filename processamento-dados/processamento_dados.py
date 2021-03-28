
from __future__ import print_function

import base64

print('Loading function')


def lambda_handler(event, context):
    output = []

    for record in event['records']:
        print(record['recordId'])
        payload = base64.b64decode(record['data'])

        # Do custom processing on the payload here
        dadosTrat = eval(payload)
        
        header = "\"id\",\"name\",\"abv\",\"ibu\",\"target_fg\",\"target_og\",\"ebc\",\"srm\",\"ph\""
        registroTratado = f"{dadosTrat['id']},\"{dadosTrat['name']}\",{dadosTrat['abv']},{dadosTrat['ibu']},{dadosTrat['target_fg']},{dadosTrat['target_og']},{dadosTrat['ebc']},{dadosTrat['srm']},{dadosTrat['ph']}"
        print('Registro tratado: ', registroTratado)
        
        output_record = {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': base64.b64encode(registroTratado.encode("utf-8"))
        }
        output.append(output_record)

    print('Successfully processed {} records.'.format(len(event['records'])))

    return {'records': output}
