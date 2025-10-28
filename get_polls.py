import json; import boto3; import os; from decimal import Decimal
dynamodb = boto3.resource('dynamodb'); table_name = os.environ['DYNAMODB_TABLE']; table = dynamodb.Table(table_name)
class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal): return int(o) if o % 1 == 0 else float(o)
        return super(DecimalEncoder, self).default(o)
def lambda_handler(event, context):
    try:
        response = table.scan(ProjectionExpression="PollID, Question, Options"); items = response.get('Items', [])
        while 'LastEvaluatedKey' in response: response = table.scan(ProjectionExpression="PollID, Question, Options", ExclusiveStartKey=response['LastEvaluatedKey']); items.extend(response.get('Items', []))
        return { 'statusCode': 200, 'headers': { 'Content-Type': 'application/json' }, 'body': json.dumps(items, cls=DecimalEncoder) }
    except Exception as e: print(f"Error: {e}"); return { 'statusCode': 500, 'body': json.dumps({'error': 'Internal server error'}) }
