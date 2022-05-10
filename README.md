# Splunk Enterprise on AWS - Quick Start

Source code associated with [Splunk Enterprise AWS Quick Start](https://fwd.aws/r7QNJ)

## Usage

Use these templates to deploy a highly available Splunk Enterprise environment across multiple AZs (2 or 3) in a given AWS region.
AZ-aware indexer clustering is enabled for horizontal scaling and to guarantee data is replicated in every AZ.
AZ-aware Search head clustering (3 nodes by default) can also be enabled for horizontal scaling and to guarantee data is available for search in every AZ.

View the accompanying [deployment guide](https://fwd.aws/bGBmy) for everything you need to get started. Refer to 'Deployment Steps' section for a step-by-step walkthrough on how to use these templates in AWS console.

### Prerequisites

Before getting started with the template configuration, you will need to make your Splunk Enterprise license privately accessible for CloudFormation template deployment via S3 download.  The following steps will guide you through that process.   *(Note:  This step is required.  A non-trial Splunk Enterprise license is required to allow our template to configure the Splunk deployment.  If you don't already have a Splunk Enterprise license, you can obtain one by contacting sales@splunk.com.)*

 1. From the AWS Console, select "S3" under the "Storage" heading, or by simply typing "S3" into the search bar.
 2. You can either select an existing private bucket to upload to, or create a new one. If you select an existing bucket, make sure its access policy does not grant public access. By default, all the S3 resources are private, so only the AWS account that created the resources can access them. For this exercise, I'm outlining how to create a new bucket.
 3. Click "create bucket"
 4. Name your bucket, and select your region.  In this example, I will use "bbartlett-splunk-config".  Your bucket name must be unique, and you should select the same region where you plan on deploying Splunk. <br><br> ![new bucket example](https://s3-us-west-2.amazonaws.com/splk-bbartlett/splunk_newbucket.png) <br><br>
 5. Once you've created your bucket, select your new bucket from the list of buckets.
 6. Click "Upload" on the upper left of the page
 7. Click "Add Files"
 8. Select your license file.
 9. Click "Start Upload" on the lower right of the page.
 10. Once the license has finished uploading, you'll need the bucket name and the filename to use with the CloudFormation template.

## License

This project is licensed under Apache License 2.0 - see [LICENSE.txt](./LICENSE.txt) file for details

## Help

If you have any problems or general questions, please file an issue in the parent repository:
https://github.com/aws-quickstart/quickstart-splunk-enterprise/issues


