import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

const dynamodbBackendTable = new aws.dynamodb.Table("dynamodbBackendTable",{
    name: "rahul-db-table",
    hashKey: "LockID",
    billingMode: "PROVISIONED",
    readCapacity: 5,
    writeCapacity: 5,
    attributes: [
        {
            name: "LockID", //required for tf state locking
            type: "S"
        }
    ]
})