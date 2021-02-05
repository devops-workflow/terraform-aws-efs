#
# Setup AWS EFS file system
#
# https://www.terraform.io/docs/providers/aws/r/efs_file_system.html
# https://www.terraform.io/docs/providers/aws/r/efs_mount_target.html

module "enabled" {
  source  = "devops-workflow/boolean/local"
  version = "0.1.2"
  value   = "${var.enabled}"
}

# Define composite variables for resources
module "label" {
  source        = "devops-workflow/label/local"
  version       = "0.2.1"
  attributes    = "${var.attributes}"
  component     = "${var.component}"
  delimiter     = "${var.delimiter}"
  environment   = "${var.environment}"
  monitor       = "${var.monitor}"
  name          = "${var.name}"
  namespace-env = "${var.namespace-env}"
  namespace-org = "${var.namespace-org}"
  organization  = "${var.organization}"
  owner         = "${var.owner}"
  product       = "${var.product}"
  service       = "${var.service}"
  tags          = "${var.tags}"
  team          = "${var.team}"
}

resource "aws_efs_file_system" "default" {
  count            = "${module.enabled.value}"
  performance_mode = "${var.performance_mode}"
  encrypted        = "${var.encrypted}"
  kms_key_id       = "${var.kms_key_id}"
  tags             = "${module.label.tags}"
}

resource "aws_efs_mount_target" "default" {
  count           = "${module.enabled.value ? length(compact(var.subnets)) : 0}"
  file_system_id  = "${aws_efs_file_system.default.id}"
  subnet_id       = "${element(compact(var.subnets), count.index)}"
  security_groups = ["${aws_security_group.default.id}"]
}

resource "aws_security_group" "default" {
  count       = "${module.enabled.value}"
  name        = "${module.label.id}"
  description = "EFS Access"
  vpc_id      = "${var.vpc_id}"
  tags        = "${module.label.tags}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress" {
  count                    = "${module.enabled.value ? length(compact(var.security_groups)) : 0}"
  type                     = "ingress"
  from_port                = "2049"
  to_port                  = "2049"
  protocol                 = "tcp"
  source_security_group_id = "${element(compact(var.security_groups), count.index)}"
  security_group_id        = "${aws_security_group.default.id}"
}

resource "aws_security_group_rule" "ingress_cidr" {
  count             = "${module.enabled.value && length(compact(var.ingress_cidr)) > 0 ? 1 : 0}"
  type              = "ingress"
  from_port         = "2049"
  to_port           = "2049"
  protocol          = "tcp"
  cidr_blocks       = ["${var.ingress_cidr}"]
  security_group_id = "${aws_security_group.default.id}"
}

resource "aws_security_group_rule" "egress" {
  count             = "${module.enabled.value}"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.default.id}"
}

# TODO: use alias module instead. This does CNAME
module "dns" {
  source  = "cloudposse/route53-cluster-hostname/aws"
  version = "0.12.0"
  name    = "${module.label.name}"
  ttl     = "${var.dns_ttl}"
  zone_id = "${var.zone_id}"
  records = ["${element(concat(aws_efs_file_system.default.*.dns_name, list("")),0)}"]
  enabled = "${module.enabled.value ? (length(var.zone_id) > 0 ? "true" : "false") : "false"}"
}
