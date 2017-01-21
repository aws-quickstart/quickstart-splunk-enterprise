#quickstart-splunk-enterprise

#####**Simple AWS CloudFormation templates for automated Splunk deployments.**


***Splunk License***<br>
Before getting started with the template configuration, you will need to make your Splunk license available via an http(s) download.  The simplest way to do this is to upload your license file to S3.  The following steps will guide you through that process.

 1. From the AWS Console, select "S3" under the "Storage & Content Delivery" heading.
 2. Click "Create Bucket" 
   3. (You can either select an existing bucket to upload to, or create a new one.  For this exercise, create a new bucket.)
 3. Name your bucket, and select your region.  In this example, I will use "bbartlett-splunk-config".  Your bucket name must be unique, and you should select the same region where you plan on deploying Splunk. ![enter image description here](https://s3-us-west-2.amazonaws.com/splk-bbartlett/splunk_newbucket.png)
 4. From the bucket list, select your new bucket name.
 5. Click "Upload" on the upper left of the page
 6. Click "Add Files"
 7. Select your license file.
 8. Click "Start Upload" on the lower right of the page.
 9. Once the file has finished uploading, it will be shown.
 10. Click the properties tab on the upper right.  Here you will find the URL for your license file.  This is the URL we will use in the template itself.

<br>
**Template Usage**
-----
This guide will show you how to launch a fully functioning Splunk deployment in just a few minutes.  Our templates require an AWS account with permission to create new VPCs and associated ACLs, create security groups, create elastic IP addresses, and launch instances.  If your account does not have these permissions, please consult with your AWS administrator.  These instructions assume that you have downloaded the template to your local machine.

TODO: Include walkthrough

**Next Steps**
-----
To find the Splunk search head URL, click the "**Outputs**" tab of your stack.  Visit that URL, and use the credentials shown to log in.  

Next, you will need to know your indexer IP addresses, as you'll need to point your forwarders here to start indexing data.  The easiest way is via the [EC2 Console](https://us-west-2.console.aws.amazon.com/ec2).  From the EC2 Console, select "**Auto Scaling Groups**" and then select your Splunk autoscaling group from the list.  (The name will be in the format YOUR_STACK_NAME-SplunkIndexerNodesASG) From here, there is an indexer tab at the bottom of the page that will show you each indexer in your deployment.  You can click each indexer to get information about them , including both private and public IP addresses.  If you need to ssh to any of these machines, you will need to use the key pair that you created earlier, and log in as the user "ec2-user".  

**Help**
-----

 - If you have any problems or general questions, please file them on the issues page of this project: https://github.com/aws-quickstart/quickstart-splunk-enterprise/issues


