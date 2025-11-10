resource "aws_s3_bucket" "mountpoint_bucket" {
  bucket = "${var.application_name}-mountpoint-bucket"
  tags   = var.tags
}

resource "aws_iam_role" "s3_csi_driver" {
  name               = "${var.application_name}-s3-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_pod_identity.json
}

data "aws_iam_policy_document" "s3_mountpoint_policy" {
  statement {
    sid    = "MountpointFullObjectAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.mountpoint_bucket.arn,
      "${aws_s3_bucket.mountpoint_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "s3_mountpoint_policy" {
  name   = "s3-mountpoint-policy"
  role   = aws_iam_role.s3_csi_driver.name
  policy = data.aws_iam_policy_document.s3_mountpoint_policy.json
}

resource "aws_eks_addon" "s3_csi_driver" {
  cluster_name = module.eks.id
  addon_name   = "aws-mountpoint-s3-csi-driver"
  pod_identity_association {
    role_arn        = aws_iam_role.s3_csi_driver.arn
    service_account = "s3-csi-driver-sa"
  }
}