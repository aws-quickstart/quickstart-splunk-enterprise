#quickstart-splunk-enterprise

#####**AWS CloudFormation templates for automated Splunk Enterprise deployments.**


***Splunk License***
Before getting started with the template configuration, you will need to make your Splunk Enterprise license privately accessible for CloudFormation template deployment via S3 download.  The following steps will guide you through that process.   *(Note:  This step is not required, and you can upload your license from the Splunk web interface.  It is, however, required that you have a non-trial Splunk Enterprise license to utilize the deployment our template creates.  If you don't already have a Splunk Enterprise license, you can obtain one by contacting sales@splunk.com.)*

 1. From the AWS Console, select "S3" under the "Storage" heading, or by simply typing "S3" into the search bar.
 2. You can either select an existing private bucket to upload to, or create a new one. If you select an existing bucket, make sure its access policy does not grant public access. By default, all the S3 resources are private, so only the AWS account that created the resources can access them. For this exercise, I'm outlining how to create a new bucket.
 3. Click "create bucket"
 3. Name your bucket, and select your region.  In this example, I will use "bbartlett-splunk-config".  Your bucket name must be unique, and you should select the same region where you plan on deploying Splunk. <br><br> ![new bucket example](https://s3-us-west-2.amazonaws.com/splk-bbartlett/splunk_newbucket.png) <br><br>
 4. Once you've created your bucket, select your new bucket from the list of buckets.
 5. Click "Upload" on the upper left of the page
 6. Click "Add Files"
 7. Select your license file.
 8. Click "Start Upload" on the lower right of the page.
 9. Once the license has finished uploading, you'll need the bucket name and the filename to use with the CloudFormation template.

<br>
**Template Usage**
-----
The templates in this repo were created in conjunction with our [Splunk Enterprise AWS Quick Start](https://aws.amazon.com/quickstart/architecture/splunk-enterprise/) which explains everything you'll need to get started.


**Help**
-----

 - If you have any problems or general questions, please file them on the issues page of this project: https://github.com/aws-quickstart/quickstart-splunk-enterprise/issues


