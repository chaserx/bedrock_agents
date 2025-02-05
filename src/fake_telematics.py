import json
import logging
import inflect

logger = logging.getLogger()

# as a mock, we'll just return the telematics data
def get_telematics_data():
    with open('data/telematics_data.json', 'r') as f:
        return json.load(f)

# we'll use the telematics data to generate a response for total distance, total time, and average speed
def generate_response(telematics_data):
    p = inflect.engine()
    total_distance = 0
    
    for item in telematics_data['Equipment']:
        total_distance += item['Distance']['Odometer']
    
    return {
        'total_distance': f"{total_distance} {p.plural(telematics_data['Equipment'][0]['Distance']['OdometerUnits'])}",
    }

def lambda_handler(event, context):
    agent = event['agent'] # not used but passed in the event
    actionGroup = event['actionGroup'] 
    function = event['function'] 
    parameters = event.get('parameters', []) # not used but passed in the event

    try:
        logger.info(f"Received event: {event}")
        responseBody = {
            'TEXT': { "body": json.dumps(generate_response(get_telematics_data())) }
        }
        action_response = {
            'actionGroup': actionGroup,
            'function': function,
            'functionResponse': {
                'responseBody': responseBody
            }
        }
        function_response = {'response': action_response, 'messageVersion': event['messageVersion']}
        print("Response: {}".format(function_response))
        return function_response
    except Exception as e:
        logger.exception(f"Error in lambda_handler: {e}")
        return f"Error occurred: {e}"
