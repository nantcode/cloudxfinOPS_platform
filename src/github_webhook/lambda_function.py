import json
import os
import hmac
import hashlib
import base64
import urllib.request
import urllib.error
import boto3
from finops_engine import FinOpsPolicyEngine

dynamodb = boto3.resource('dynamodb')
ssm = boto3.client('ssm')

# Cache PAT across warm Lambda executions
GITHUB_PAT = None

def get_github_pat():
    """Retrieve GitHub PAT from SSM Parameter Store or Environment Variables."""
    global GITHUB_PAT
    if GITHUB_PAT:
        return GITHUB_PAT

    # 1. Environment variable check
    pat = os.environ.get('GITHUB_PAT', '')
    if pat:
        GITHUB_PAT = pat
        return GITHUB_PAT

    # 2. SSM Parameter Store retrieval
    param_name = os.environ.get('GITHUB_PAT_PARAM', '/cloudops/github/pat')
    try:
        response = ssm.get_parameter(Name=param_name, WithDecryption=True)
        GITHUB_PAT = response['Parameter']['Value']
        return GITHUB_PAT
    except Exception as e:
        print(f"Error fetching PAT from SSM ({param_name}): {str(e)}")
        return ''

def fetch_pr_files(repo_full_name, pr_number, pat):
    """Fetch changed files for a Pull Request via GitHub REST API."""
    url = f"https://api.github.com/repos/{repo_full_name}/pulls/{pr_number}/files"
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "AWS-Lambda-FinOps-Scanner"
    }
    if pat:
        headers["Authorization"] = f"token {pat}"

    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req) as response:
            if response.status == 200:
                files_data = json.loads(response.read().decode('utf-8'))
                return files_data
    except urllib.error.HTTPError as e:
        print(f"GitHub API HTTP Error {e.code}: {e.reason}")
    except Exception as e:
        print(f"Failed to fetch PR files: {str(e)}")
    
    return []

def post_github_comment(comments_url, body_markdown, pat):
    """Post a markdown comment to the GitHub PR."""
    if not pat or not comments_url:
        print("Skipping PR comment: missing PAT or comments_url.")
        return None

    headers = {
        "Authorization": f"token {pat}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json",
        "User-Agent": "AWS-Lambda-FinOps-Scanner"
    }
    req = urllib.request.Request(
        comments_url,
        data=json.dumps({"body": body_markdown}).encode('utf-8'),
        headers=headers,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as response:
            return response.status
    except Exception as e:
        print(f"Failed to post comment to GitHub: {str(e)}")
        return None

def lambda_handler(event, context):
    secret = os.environ.get('WEBHOOK_SECRET', '')
    table_name = os.environ.get('DYNAMODB_TABLE_NAME', 'cloudops-audit-log-dev')

    # 1. Normalize HTTP Headers
    headers = {k.lower(): v for k, v in (event.get('headers') or {}).items()}
    signature = headers.get('x-hub-signature-256', '')
    github_event = headers.get('x-github-event', '')

    body = event.get('body', '') or ''
    if event.get('isBase64Encoded', False):
        body = base64.b64decode(body).decode('utf-8')

    # 2. Validate HMAC SHA-256 Signature
    if secret and signature:
        computed_hash = 'sha256=' + hmac.new(
            secret.encode('utf-8'),
            body.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        if not hmac.compare_digest(computed_hash, signature):
            return {
                'statusCode': 401,
                'body': json.dumps({'error': 'Invalid HMAC signature'})
            }

    # 3. Handle GitHub Ping Event
    if github_event == 'ping':
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'PONG - Webhook connection successful!'})
        }

    # 4. Process Pull Request Events & Run FinOps Evaluation
    try:
        payload = json.loads(body)
        action = payload.get('action', 'unknown')
        pr = payload.get('pull_request', {})
        repo = payload.get('repository', {}).get('full_name', 'unknown')
        pr_number = str(pr.get('number', '0'))
        comments_url = pr.get('comments_url', '')
        
        event_id = f"{repo}#{pr_number}"
        
        # Filter for relevant PR lifecycle actions
        if action in ['opened', 'synchronize', 'reopened']:
            pat = get_github_pat()
            files = fetch_pr_files(repo, pr_number, pat)
            
            # Filter specifically for Terraform (.tf) files
            tf_files = [f for f in files if f.get('filename', '').endswith('.tf')]
            file_names = [f.get('filename') for f in tf_files]

            # Run FinOps Policy Rules Engine against fetched PR diffs
            engine = FinOpsPolicyEngine(tf_files)
            results = engine.evaluate()

            # Format Markdown report for GitHub PR Comment
            status_icon = "✅ Pass" if results["passed"] else "❌ Action Required"
            markdown_body = f"### 🛡️ FinOps Guardrail Assessment: {status_icon}\n\n"
            
            if results["violations"]:
                markdown_body += "#### Policy Violations:\n" + "\n".join(f"- {v}" for v in results["violations"]) + "\n\n"
                
            if results["warnings"]:
                markdown_body += "#### Cost Warnings:\n" + "\n".join(f"- {w}" for w in results["warnings"]) + "\n\n"
                
            if results["passed"] and not results["warnings"]:
                markdown_body += "All modified Terraform resources comply with organizational cost limits and tagging policies."

            # Post comment to GitHub Pull Request
            post_github_comment(comments_url, markdown_body, pat)
            
            # Update DynamoDB audit record
            table = dynamodb.Table(table_name)
            table.put_item(
                Item={
                    'eventId': event_id,
                    'status': 'EVALUATED',
                    'finops_passed': results["passed"],
                    'violations_count': len(results["violations"]),
                    'warnings_count': len(results["warnings"]),
                    'action': action,
                    'sender': payload.get('sender', {}).get('login', 'unknown'),
                    'repository': repo,
                    'pr_number': pr_number,
                    'modified_tf_files': file_names,
                    'total_tf_changes': len(tf_files)
                }
            )

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'PR files evaluated by FinOps Engine successfully',
                    'eventId': event_id,
                    'passed': results["passed"],
                    'violations': results["violations"],
                    'warnings': results["warnings"],
                    'tf_files_count': len(tf_files),
                    'files': file_names
                })
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({'message': f"Ignored action: {action}"})
            }

    except json.JSONDecodeError:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Malformed JSON payload'})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}