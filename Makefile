STACK = chris-s3mount-bug

deploy: s3mount-bug.yml
	aws cloudformation deploy --stack-name $(STACK) --template-file s3mount-bug.yml --capabilities CAPABILITY_IAM

connect conn ssh shell:
	IID=$$(aws cloudformation describe-stack-resources --stack-name $(STACK) --query "StackResources[?(ResourceType=='AWS::EC2::Instance')].[PhysicalResourceId]" --output text) ;\
	echo "Connecting to instance $$IID ..." ;\
	aws ssm start-session --target $$IID

