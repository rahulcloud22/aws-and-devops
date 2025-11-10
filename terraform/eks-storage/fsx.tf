resource "aws_iam_role" "fsx_csi_driver" {
  name               = "${var.application_name}-fsx-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "fsx_policy_attachment" {
  role       = aws_iam_role.fsx_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonFSxFullAccess"
}

resource "aws_eks_addon" "fsx_csi_driver" {
  cluster_name = module.eks.id
  addon_name   = "aws-fsx-csi-driver"
  pod_identity_association {
    role_arn        = aws_iam_role.fsx_csi_driver.arn
    service_account = "fsx-csi-controller-sa"
  }
}