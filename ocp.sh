#!/bin/bash
#GOGOGO
create_vpc() {
    aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text
}
#VPC-------------------------------
account_id=$(aws sts get-caller-identity --query Account --output text)
printf "Create VPC"
vpcid=$(create_vpc)
printf "#"
aws ec2 create-tags --resources $vpcid --tags Key=Name,Value="Cloud Project VPC"
printf "#"
az1a_pub_sub=$(aws ec2 create-subnet --availability-zone us-east-1a --cidr-block 10.0.0.0/24 --vpc-id $vpcid --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=az1a_public}]' --query 'Subnet.SubnetId' --output text)
printf "#"
az1a_pri_sub=$(aws ec2 create-subnet --availability-zone us-east-1a --cidr-block 10.0.4.0/22 --vpc-id $vpcid --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=az1a_private}]' --query 'Subnet.SubnetId' --output text)
printf "#"
az1b_pub_sub=$(aws ec2 create-subnet --availability-zone us-east-1b --cidr-block 10.0.1.0/24 --vpc-id $vpcid --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=az1b_public}]' --query 'Subnet.SubnetId' --output text)
printf "#"
az1b_pri_sub=$(aws ec2 create-subnet --availability-zone us-east-1b --cidr-block 10.0.8.0/22 --vpc-id $vpcid --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=az1b_private}]' --query 'Subnet.SubnetId' --output text)
printf "#\n"
printf "Create Internet Gateway#"
igw=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcid
printf "#\n"
printf "Create Route Tables"
az1a_pub_rtb=$(aws ec2 create-route-table --vpc-id $vpcid --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=az1a_public_rtb}]' --query 'RouteTable.RouteTableId' --output text)
printf "#"
az1a_pri_rtb=$(aws ec2 create-route-table --vpc-id $vpcid --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=az1a_private_rtb}]' --query 'RouteTable.RouteTableId' --output text)
printf "#"
az1b_pub_rtb=$(aws ec2 create-route-table --vpc-id $vpcid --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=az1b_public_rtb}]' --query 'RouteTable.RouteTableId' --output text)
printf "#"
az1b_pri_rtb=$(aws ec2 create-route-table --vpc-id $vpcid --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=az1b_private_rtb}]' --query 'RouteTable.RouteTableId' --output text)
printf "#\n"
printf "Create S3 Endpoints"
az1a_S3EP=$(aws ec2 create-vpc-endpoint --vpc-id $vpcid --service-name com.amazonaws.us-east-1.s3 --route-table-ids $az1a_pri_rtb --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=az1a_S3EP}]')
printf "#"
az1b_S3EP=$(aws ec2 create-vpc-endpoint --vpc-id $vpcid --service-name com.amazonaws.us-east-1.s3 --route-table-ids $az1b_pri_rtb --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=az1b_S3EP}]')
printf "#\n"
printf "Map Internet Gateway to Route Table#"
az1a_igw_route=$(aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --route-table-id $az1a_pub_rtb --gateway-id $igw)
printf "#"
az1b_igw_route=$(aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --route-table-id $az1b_pub_rtb --gateway-id $igw)
printf "#\n"
#SQS/SNS-----------------------------------
printf "Create 2 Queues"
error_queue_URL=$(aws sqs create-queue --queue-name Error_Queue --attributes VisibilityTimeout=300 --output text)
printf "#"
To_Be_Processed_Queue_URL=$(aws sqs create-queue --queue-name To_Be_Processed_Queue --attributes VisibilityTimeout=300 --output text)
printf "#\n"
printf "Create topic and set subscription"
topic_arn=$(aws sns create-topic --name ErrorTopic --output text)
printf "#"
queue_arn=$(aws sqs get-queue-attributes --queue-url $error_queue_URL --attribute-names QueueArn --output text |grep ATTRIBUTES |awk '{print$2}')
printf "#"
aws sns subscribe --topic-arn $topic_arn --protocol sqs --notification-endpoint $queue_arn
printf "#\n"
albSg=$(aws ec2 create-security-group --group-name "ALB Security Group" --description "albSg" --vpc-id $vpcid --output text)
lambdaSg=$(aws ec2 create-security-group --group-name "Web Lambda Security Group" --description "lambdaSg" --vpc-id $vpcid --output text)
dbSg=$(aws ec2 create-security-group --group-name "Database Security Group" --description "dbSg" --vpc-id $vpcid --output text)
SQSSG=$(aws ec2 create-security-group --group-name "SQS Security Group" --description "SQSSG" --vpc-id $vpcid --output text)
SMSG=$(aws ec2 create-security-group --group-name "Secret Manager Security Group" --description "SMSG" --vpc-id $vpcid --output text)
InitDBSG=$(aws ec2 create-security-group --group-name "Initial Database Security Group" --description "InitDBSG" --vpc-id $vpcid --output text)

aws ec2 create-vpc-endpoint --vpc-id $vpcid --vpc-endpoint-type Interface --service-name com.amazonaws.us-east-1.sqs --subnet-id $az1a_pri_sub $az1b_pri_sub --no-private-dns-enabled --security-group-ids $SQSSG --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=SQS_EP}]'
aws ec2 create-vpc-endpoint --vpc-id $vpcid --vpc-endpoint-type Interface --service-name com.amazonaws.us-east-1.secretsmanager --subnet-id $az1a_pri_sub $az1b_pri_sub --no-private-dns-enabled --security-group-ids $SMSG --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=SM_EP}]'

aws rds create-db-subnet-group --db-subnet-group-name subnet-id --db-subnet-group-description subnet-id --subnet-ids $az1a_pub_sub $az1b_pub_sub
sm_arn=$(aws secretsmanager create-secret --name AuroraServerlessMasterUser --description AuroraServerlessMasterUserDescription --secret-string '{"engine":"mysql","port":3306,"username":"dbroot"}' --output text |awk '{print$1}')

echo "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Action\": [
                \"secretsmanager:GetSecretValue\"
            ],
            \"Resource\": \"$sm_arn\"
        },
        {
            \"Effect\": \"Allow\",
            \"Action\": [
                \"rds:DescribeDBClusters\"
            ],
            \"Resource\": \"arn:aws:rds:us-east-1:$account_id:cluster:CloudProjectDatabase\"
        },
        {
            \"Effect\": \"Allow\",
            \"Action\": [
                \"sqs:SendMessage\",
                \"sqs:GetQueueAttributes\",
                \"sqs:GetQueueUrl\"
            ],
            \"Resource\": \"arn:aws:sqs:us-east-1:$account_id:To_Be_Processed_Queue\"
        },
        {
            \"Effect\": \"Allow\",
            \"Action\": [
                \"xray:PutTelemetryRecords\",
                \"xray:PutTraceSegments\"
            ],
            \"Resource\": \"*\"
        }
    ]
}" | tee Lam_Policy
aws iam create-policy --policy-name Lam_Policy --policy-document file://Lam_Policy
echo "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Action\": [
                \"logs:CreateLogStream\",
                \"logs:PutLogEvents\"
            ],
            \"Resource\": \"arn:aws:logs:us-east-1:$account_id:log-group:/cloudproject/batchprocesslog:*\",
            \"Effect\": \"Allow\"
        },
        {
            \"Action\": \"logs:DescribeLogStreams\",
            \"Resource\": \"arn:aws:logs:us-east-1:$account_id:log-group:/cloudproject/batchprocesslog:*\",
            \"Effect\": \"Allow\"
        },
        {
            \"Action\": [
                \"sqs:ReceiveMessage\",
                \"sqs:ChangeMessageVisibility\",
                \"sqs:GetQueueUrl\",
                \"sqs:DeleteMessage\",
                \"sqs:GetQueueAttributes\"
            ],
            \"Resource\": \"arn:aws:sqs:us-east-1:$account_id:To_Be_Processed_Queue\",
            \"Effect\": \"Allow\"
        }
    ]
}" | tee EC2_Policy
aws iam create-policy --policy-name EC2_Policy --policy-document file://EC2_Policy
echo "[{\"IpProtocol\": \"-1\", \"FromPort\": \"-1\", \"ToPort\": \"-1\", \"IpRanges\": [{\"CidrIp\": \"$lambdaSg\", \"Description\": \"\"}]}]" | tee db_ingress
aws ec2 update-security-group-rule-descriptions-ingress --group-id $dbSg --ip-permissions file://db_ingress





#--tag-specifications 'ResourceType=,Tags=[{Key=,Value=}]'
#===============================
printf "\n"