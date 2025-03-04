import os
import boto3

prefix_key = "server/"
local_path = "./server/"
bucket_name = "consul-bucket-us-east-2-704678691702"

s3_client = boto3.client('s3')

if __name__ == "__main__" :
    for filename in os.listdir(local_path):

        print("Uploading:", filename)
        s3_client.upload_file(local_path + filename, bucket_name, prefix_key + filename)