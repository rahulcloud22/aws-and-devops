resource "aws_efs_file_system" "efs" {
  creation_token   = "${var.application_name}-efs-token"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
  tags = merge({
    Name = "${var.application_name}-efs"
  }, var.tags)
}

resource "aws_efs_mount_target" "mnt_targets" {
  for_each        = toset(data.terraform_remote_state.infra.outputs.vpc.public_subnet_ids)
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = each.value
  security_groups = [module.eks.cluster_security_group_id]
}

resource "aws_iam_role" "efs_csi_driver" {
  name               = "${var.application_name}-efs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "efs_policy_attachment" {
  role       = aws_iam_role.efs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name = module.eks.id
  addon_name   = "aws-efs-csi-driver"
  pod_identity_association {
    role_arn        = aws_iam_role.efs_csi_driver.arn
    service_account = "efs-csi-controller-sa"
  }
  configuration_values = jsonencode({
    controller = { # default false, the data will remain in EFS even after PVC deletion. 
      deleteAccessPointRootDir = true
    }
  })
}