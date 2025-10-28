import json; import boto3; import os; from botocore.exceptions import ClientError
dynamodb = boto3.resource('dynamodb'); table_name = os.environ['DYNAMODB_TABLE']; table = dynamodb.Table(table_name)
def lambda_handler(event, context):
    try:
        poll_id = event.get('pathParameters', {}).get('pollId'); body = json.loads(event.get('body', '{}')); selected_option_text = body.get('optionText')
        if not poll_id or not selected_option_text: return { 'statusCode': 400, 'body': json.dumps({'error': 'Missing pollId or optionText'}) }
        response = table.get_item(Key={'PollID': poll_id}); item = response.get('Item')
        if not item: return { 'statusCode': 404, 'body': json.dumps({'error': 'Poll not found'}) }
        options = item.get('Options', []); option_index = -1
        for i, opt in enumerate(options):
            if opt.get('optionText') == selected_option_text: option_index = i; break
        if option_index == -1: return { 'statusCode': 400, 'body': json.dumps({'error': 'Invalid option text'}) }
        table.update_item(Key={'PollID': poll_id}, UpdateExpression=f"SET Options[{option_index}].votes = Options[{option_index}].votes + :inc", ExpressionAttributeValues={ ':inc': 1 });
        return { 'statusCode': 200, 'headers': { 'Content-Type': 'application/json' }, 'body': json.dumps({'message': 'Vote recorded'}) }
    except ClientError as e: print(f"DB Error: {e.response['Error']['Message']}"); return { 'statusCode': 500, 'body': json.dumps({'error': 'DB error'}) }
    except Exception as e: print(f"Error: {e}"); return { 'statusCode': 500, 'body': json.dumps({'error': 'Internal server error'}) }
