\# Delpyment-of-Static-Website-using-Terraform-



---



\# Deploying a Static Web Application on AWS Using Terraform Across Multiple Accounts



In this post, I’ll share my journey deploying a static web application on AWS using \*\*Terraform\*\*, with a unique challenge: \*\*Route 53 and CloudFront resources were in different AWS accounts\*\*. Along the way, I faced multiple errors and learned best practices for multi-account AWS deployments.



---



\## \*\*Architecture Overview\*\*



Here’s the final architecture:



```

![Architecture Diagram](images/architecture.png)





```



\*\*Components\*\*:



\* \*\*S3 Bucket (Account B)\*\* – hosts static files

\* \*\*CloudFront (Account B)\*\* – content delivery with HTTPS via ACM

\* \*\*ACM Certificate (Account B)\*\* – for HTTPS

\* \*\*Route 53 Hosted Zone (Account A)\*\* – domain management and alias to CloudFront

\* \*\*Terraform\*\* – infrastructure as code



---



\## \*\*Deployment Steps\*\*



\### \*\*1. Configure Providers\*\*



Because CloudFront requires \*\*ACM in `us-east-1`\*\*, I used a provider alias:



```

provider "aws" {

&nbsp; region = "us-east-1"

}



provider "aws" {

&nbsp; alias  = "us\_east\_1"

&nbsp; region = "us-east-1"

}

```



---



\### \*\*2. S3 Bucket \& Private Access\*\*



```

resource "aws\_s3\_bucket" "firstbucket" {

&nbsp; bucket = var.bucket\_name

&nbsp; tags   = var.tags

}



resource "aws\_s3\_bucket\_public\_access\_block" "block" {

&nbsp; bucket                  = aws\_s3\_bucket.firstbucket.id

&nbsp; block\_public\_acls       = true

&nbsp; block\_public\_policy     = true

&nbsp; ignore\_public\_acls      = true

&nbsp; restrict\_public\_buckets = true

}

```



\* Blocked public access for security

\* Enabled \*\*Origin Access Control (OAC)\*\* for CloudFront



---



\### \*\*3. Upload Application Files\*\*



Terraform can manage S3 objects:



```

resource "aws\_s3\_object" "object" {

&nbsp; for\_each = fileset("${path.module}/www", "\*\*/\*")

&nbsp; bucket   = aws\_s3\_bucket.firstbucket.id

&nbsp; key      = each.value

&nbsp; source   = "${path.module}/www/${each.value}"

&nbsp; etag     = filemd5("${path.module}/www/${each.value}")

}

```



\* Automatically uploads all static files from `/www` directory

\* Detects content type (HTML, CSS, JS, images)



---



\### \*\*4. ACM Certificate \& DNS Validation\*\*



```

resource "aws\_acm\_certificate" "cert" {

&nbsp; domain\_name       = "smartflixlms.com"

&nbsp; validation\_method = "DNS"

&nbsp; provider          = aws.us\_east\_1

}



resource "aws\_route53\_record" "cert\_validation" {

&nbsp; for\_each = {

&nbsp;   for dvo in aws\_acm\_certificate.cert.domain\_validation\_options : dvo.domain\_name => dvo

&nbsp; }

&nbsp; zone\_id = data.aws\_route53\_zone.primary.zone\_id  # Account A

&nbsp; name    = each.value.resource\_record\_name

&nbsp; type    = each.value.resource\_record\_type

&nbsp; records = \[each.value.resource\_record\_value]

&nbsp; ttl     = 60

}



resource "aws\_acm\_certificate\_validation" "cert\_validation" {

&nbsp; provider                 = aws.us\_east\_1

&nbsp; certificate\_arn          = aws\_acm\_certificate.cert.arn

&nbsp; validation\_record\_fqdns  = \[for record in aws\_route53\_record.cert\_validation : record.fqdn]

}

```



\* Used \*\*DNS validation\*\* via Route 53 in Account A

\* Ensured CloudFront in Account B could use the certificate



---



\### \*\*5. CloudFront Distribution\*\*



```

resource "aws\_cloudfront\_distribution" "s3\_distribution" {

&nbsp; origin {

&nbsp;   domain\_name              = aws\_s3\_bucket.firstbucket.bucket\_regional\_domain\_name

&nbsp;   origin\_access\_control\_id = aws\_cloudfront\_origin\_access\_control.oac.id

&nbsp;   origin\_id                = local.origin\_id

&nbsp; }

&nbsp; aliases = \["smartflixlms.com"]



&nbsp; viewer\_certificate {

&nbsp;   acm\_certificate\_arn      = aws\_acm\_certificate.cert.arn

&nbsp;   ssl\_support\_method       = "sni-only"

&nbsp;   minimum\_protocol\_version = "TLSv1.2\_2021"

&nbsp; }

}

```



\* Linked CloudFront to \*\*S3 bucket with OAC\*\*

\* Configured \*\*HTTPS\*\* with ACM



---



\### \*\*6. Route 53 Alias Record in a Different Account\*\*



```

resource "aws\_route53\_record" "root\_domain" {

&nbsp; zone\_id = data.aws\_route53\_zone.primary.zone\_id

&nbsp; name    = "smartflixlms.com"

&nbsp; type    = "A"

&nbsp; alias {

&nbsp;   name                   = aws\_cloudfront\_distribution.s3\_distribution.domain\_name

&nbsp;   zone\_id                = aws\_cloudfront\_distribution.s3\_distribution.hosted\_zone\_id

&nbsp;   evaluate\_target\_health = false

&nbsp; }

}

```



\* This \*\*points the domain in Account A\*\* to CloudFront in Account B

\* Critical step for \*\*multi-account deployments\*\*



---



\## \*\*Challenges \& Errors\*\*



| Error                           | Cause                                       | Solution                                       |

| ------------------------------- | ------------------------------------------- | ---------------------------------------------- |

| Invalid variable names          | Variable contained spaces                   | Replace with underscores                       |

| Invalid S3 bucket name          | Did not follow AWS rules                    | Use lowercase letters, numbers, and dashes     |

| ACM certificate region mismatch | CloudFront requires `us-east-1`             | Create provider alias for `us-east-1`          |

| CNAMEAlreadyExists              | Domain previously linked in another account | Delete old distribution \& wait for propagation |

| DNS\_PROBE\_FINISHED\_NXDOMAIN     | Local DNS cache or propagation              | Flush DNS cache, test on other devices         |

| SSL not working temporarily     | CloudFront propagation delay                | Wait 10–15 minutes                             |



---



\## \*\*Verification\*\*



\* \*\*DNS\*\*:



```

nslookup smartflixlms.com 8.8.8.8

```



\* \*\*HTTPS\*\*:



```

openssl s\_client -connect smartflixlms.com:443 -servername smartflixlms.com

```



\* \*\*Browser\*\*: Test in incognito mode



✅ Result: site live, SSL active, distributed via CloudFront, domain resolving from Route 53 in a different account



---



\## \*\*Key Takeaways\*\*



1\. Terraform is powerful but \*\*region-aware\*\*. ACM + CloudFront always need `us-east-1`.

2\. Multi-account deployments require careful \*\*DNS and CNAME management\*\*.

3\. Patience is required: \*\*CloudFront edge propagation\*\* can take 5–15 minutes.

4\. Always \*\*flush local DNS caches\*\* when troubleshooting domain issues.

5\. Use \*\*Terraform lifecycle rules\*\* (`create\_before\_destroy`) to avoid downtime during certificate updates.



---



\### \*\*Conclusion\*\*



Deploying a static web application across multiple AWS accounts is entirely possible with Terraform. While errors like \*\*CNAME conflicts, DNS propagation delays, and SSL region issues\*\* can be tricky, careful planning and methodical debugging ensure a smooth deployment.



🔗 Live URL: \[https://smartflixlms.com](https://smartflixlms.com)



---



