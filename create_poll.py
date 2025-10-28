import json; import boto3; import uuid; import os
dynamodb = boto3.resource('dynamodb'); table_name = os.environ['DYNAMODB_TABLE']; table = dynamodb.Table(table_name)
def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}')); question = body.get('question'); options = body.get('options')
        if not question or not options or not isinstance(options, list) or len(options) < 2: return { 'statusCode': 400, 'body': json.dumps({'error': 'Missing/invalid question/options (min 2)'}) }
        poll_id = str(uuid.uuid4()); options_db_format = [{'optionText': opt, 'votes': 0} for opt in options]
        table.put_item(Item={ 'PollID': poll_id, 'Question': question, 'Options': options_db_format });
        return { 'statusCode': 201, 'headers': { 'Content-Type': 'application/json' }, 'body': json.dumps({'pollId': poll_id, 'message': 'Poll created'}) }
    except Exception as e: print(f"Error: {e}"); return { 'statusCode': 500, 'body': json.dumps({'error': 'Internal server error'}) }
