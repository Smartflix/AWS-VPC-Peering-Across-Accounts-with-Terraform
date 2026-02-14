# Delpyment-of-Static-Website-using-Terraform-

---

# Deploying a Static Web Application on AWS Using Terraform Across Multiple Accounts

In this post, I’ll share my journey deploying a static web application on AWS using **Terraform**, with a unique challenge: **Route 53 and CloudFront resources were in different AWS accounts**. Along the way, I faced multiple errors and learned best practices for multi-account AWS deployments.

---

## **Architecture Overview**

Here’s the final architecture:

```
![Delpyment-of-Static-Website-using-Terraform](images/Architeture.png)



```

**Components**:

* **S3 Bucket (Account B)** – hosts static files
* **CloudFront (Account B)** – content delivery with HTTPS via ACM
* **ACM Certificate (Account B)** – for HTTPS
* **Route 53 Hosted Zone (Account A)** – domain management and alias to CloudFront
* **Terraform** – infrastructure as code

---

## **Deployment Steps**

### **1. Configure Providers**

Because CloudFront requires **ACM in `us-east-1`**, I used a provider alias:

```
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

---

### **2. S3 Bucket & Private Access**

```
resource "aws_s3_bucket" "firstbucket" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.firstbucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

* Blocked public access for security
* Enabled **Origin Access Control (OAC)** for CloudFront

---

### **3. Upload Application Files**

Terraform can manage S3 objects:

```
resource "aws_s3_object" "object" {
  for_each = fileset("${path.module}/www", "**/*")
  bucket   = aws_s3_bucket.firstbucket.id
  key      = each.value
  source   = "${path.module}/www/${each.value}"
  etag     = filemd5("${path.module}/www/${each.value}")
}
```

* Automatically uploads all static files from `/www` directory
* Detects content type (HTML, CSS, JS, images)

---

### **4. ACM Certificate & DNS Validation**

```
resource "aws_acm_certificate" "cert" {
  domain_name       = "smartflixlms.com"
  validation_method = "DNS"
  provider          = aws.us_east_1
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => dvo
  }
  zone_id = data.aws_route53_zone.primary.zone_id  # Account A
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert_validation" {
  provider                 = aws.us_east_1
  certificate_arn          = aws_acm_certificate.cert.arn
  validation_record_fqdns  = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

* Used **DNS validation** via Route 53 in Account A
* Ensured CloudFront in Account B could use the certificate

---

### **5. CloudFront Distribution**

```
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.firstbucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = local.origin_id
  }
  aliases = ["smartflixlms.com"]

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
```

* Linked CloudFront to **S3 bucket with OAC**
* Configured **HTTPS** with ACM

---

### **6. Route 53 Alias Record in a Different Account**

```
resource "aws_route53_record" "root_domain" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "smartflixlms.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
```

* This **points the domain in Account A** to CloudFront in Account B
* Critical step for **multi-account deployments**

---

## **Challenges & Errors**

| Error                           | Cause                                       | Solution                                       |
| ------------------------------- | ------------------------------------------- | ---------------------------------------------- |
| Invalid variable names          | Variable contained spaces                   | Replace with underscores                       |
| Invalid S3 bucket name          | Did not follow AWS rules                    | Use lowercase letters, numbers, and dashes     |
| ACM certificate region mismatch | CloudFront requires `us-east-1`             | Create provider alias for `us-east-1`          |
| CNAMEAlreadyExists              | Domain previously linked in another account | Delete old distribution & wait for propagation |
| DNS_PROBE_FINISHED_NXDOMAIN     | Local DNS cache or propagation              | Flush DNS cache, test on other devices         |
| SSL not working temporarily     | CloudFront propagation delay                | Wait 10–15 minutes                             |

---

## **Verification**

* **DNS**:

```
nslookup smartflixlms.com 8.8.8.8
```

* **HTTPS**:

```
openssl s_client -connect smartflixlms.com:443 -servername smartflixlms.com
```

* **Browser**: Test in incognito mode

✅ Result: site live, SSL active, distributed via CloudFront, domain resolving from Route 53 in a different account

---

## **Key Takeaways**

1. Terraform is powerful but **region-aware**. ACM + CloudFront always need `us-east-1`.
2. Multi-account deployments require careful **DNS and CNAME management**.
3. Patience is required: **CloudFront edge propagation** can take 5–15 minutes.
4. Always **flush local DNS caches** when troubleshooting domain issues.
5. Use **Terraform lifecycle rules** (`create_before_destroy`) to avoid downtime during certificate updates.

---

### **Conclusion**

Deploying a static web application across multiple AWS accounts is entirely possible with Terraform. While errors like **CNAME conflicts, DNS propagation delays, and SSL region issues** can be tricky, careful planning and methodical debugging ensure a smooth deployment.

🔗 Live URL: [https://smartflixlms.com](https://smartflixlms.com)

---
