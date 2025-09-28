## AWS SigV4

This script demonstrates how AWS signs a request using the Signature Version 4 (SigV4) signing process by making a simple API call to list S3 buckets.

To learn more about aws-sigv4 checkout my [blog](https://medium.com/@rahul.cloud/aws-sigv4-e6d042249224)

### Prerequisites
- Python 3.8+
- Install dependency:
```bash
pip install requests
```

### Configure
Edit `sigv4.py` and set your AWS credentials
```python
access_key = 'YOUR_ACCESS_KEY_ID'
secret_key = 'YOUR_SECRET_ACCESS_KEY'
```

### Run
```bash
python sigv4.py
```

If successful, you will see your bucket names printed