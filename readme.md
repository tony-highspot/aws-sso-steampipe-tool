# Getting Started with aws-sso-steampipe-tool

**Note**: [aws-sso-steampipe-tool](https://github.com/somoore/aws-sso-steampipe-tool) is based on [aws-sso-profile-tool](https://github.com/aws-samples/aws-sso-profile-tool) from AWS. 

**What does this do?**

This tool generate profiles in your ~/.aws/config path based on your level of access in AWS SSO in a headless manner and also auto-generates the connections required for [Steampipe](https://steampipe.io/) to connect to one or many accounts using the [AWS](https://hub.steampipe.io/plugins/turbot/aws) plugin.

**What if I have multiple AWS accounts in AWS SSO?**

This tool has been tested against AWS Orgs as large as 900 accounts with great success. The larger your AWS Org & SSO size the longer it will take for the tool to generate the necessary profiles and connections. YMMV

**How do I run this?**

First make sure you have the following installed:
 - [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
 - [Steampipe](https://steampipe.io/downloads)
 - Ensure your AWS Org has [AWS IAM Identity Center](https://aws.amazon.com/iam/identity-center/) setup

git clone https://github.com/somoore/aws-sso-steampipe-tool.git  & open 'sync.sh' in your favorite editor and edit the following:

#Add your AWS SSO Start URL & Region on the next two lines
 

    START_URL="https://[start-url].awsapps.com/start#/"; 
    REGION="us-east-1";

Now run

    chmod +x
    sh ./sync.sh

Grab some coffee and you should see your AWS Accounts synced to ~/.aws/config & steampipe connections for the AWS plugin ~/.steampipe/config/aws.spc automatically.


