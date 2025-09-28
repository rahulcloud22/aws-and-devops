import hashlib
import hmac
import requests
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

access_key = 'ACCESS_KEY_ID'
secret_key = 'SECRET_ACCESS_KEY'

def get_amz_dates():
    t = datetime.now(timezone.utc)
    amz_date = t.strftime('%Y%m%dT%H%M%SZ')
    date_stamp = t.strftime('%Y%m%d')
    return amz_date, date_stamp

def hash256(payload):
    return hashlib.sha256((payload).encode('utf-8')).hexdigest()

def create_canonical_request(method, canonical_uri, canonical_querystring, canonical_headers, signed_headers, payload_hash):
    canonical_request = '\n'.join([
        method,
        canonical_uri,
        canonical_querystring,
        canonical_headers,
        signed_headers,
        payload_hash
    ])
    return canonical_request

def create_string_to_sign(amz_date, credential_scope, canonical_request):
    algorithm = 'AWS4-HMAC-SHA256'
    string_to_sign = '\n'.join([
        algorithm,
        amz_date,
        credential_scope,
        hash256(canonical_request)
    ])
    return string_to_sign

def sign(key, msg, hex=False):
    signature = hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()
    return signature.hex() if hex else signature

def create_signing_key(secret_key, date_stamp, region, service):
    DateKey = sign(f'AWS4{secret_key}'.encode('utf-8'), date_stamp)
    DateRegionKey = sign(DateKey,region)
    DateRegionServiceKey = sign(DateRegionKey,service)
    SigningKey = sign(DateRegionServiceKey, "aws4_request")
    return SigningKey

def create_authorization_header(access_key, credential_scope, signed_headers, signature):
    return (
        f'AWS4-HMAC-SHA256 Credential={access_key}/{credential_scope}, '
        f'SignedHeaders={signed_headers}, Signature={signature}'
    )

def list_s3_buckets():
    method = 'GET'
    host = 's3.us-east-1.amazonaws.com'
    region = 'us-east-1'
    service = 's3'
    uri = '/'
    query_string = ''
    payload_hash = hash256('')
    amz_date, date_stamp = get_amz_dates()

    canonical_headers = (
        f'host:{host}\n'
        f'x-amz-content-sha256:{payload_hash}\n'
        f'x-amz-date:{amz_date}\n'
    )
    signed_headers = 'host;x-amz-content-sha256;x-amz-date'

    canonical_request = create_canonical_request(
        method, uri, query_string,
        canonical_headers, signed_headers,
        payload_hash
    )

    print(f"Canonical Request:\n{canonical_request}\n")

    credential_scope = f'{date_stamp}/{region}/{service}/aws4_request'
    string_to_sign = create_string_to_sign(
        amz_date, credential_scope, canonical_request
    )

    print(f"String to Sign:\n{string_to_sign}\n")
    signing_key = create_signing_key(secret_key, date_stamp, region, service)
    signature = sign(signing_key, string_to_sign, hex=True)

    print(f"Signature:\n{signature}\n")

    headers = {
        'Authorization': create_authorization_header(access_key, credential_scope, signed_headers, signature),
        'x-amz-date': amz_date,
        'x-amz-content-sha256': payload_hash
    }

    print("Request Headers:\n", headers, "\n")
    response = requests.get(f"https://{host}", headers=headers)

    if response.status_code != 200:
        print(response.text)
        print(f"Error: {response.status_code}")
        return

    root = ET.fromstring(response.text)
    namespace = {'ns': 'http://s3.amazonaws.com/doc/2006-03-01/'}
    bucket_names = []
    for bucket in root.findall('.//ns:Bucket', namespace):
        name = bucket.find('.//ns:Name', namespace).text
        bucket_names.append(name)
    print("Buckets:", bucket_names)

if __name__ == "__main__":
    list_s3_buckets()
