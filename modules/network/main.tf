# --- Shared VPC -------------------------------------------------------------
#
# One VPC for the whole lab. Tenancy isolation happens BELOW the VPC layer
# (one subnet + one security group per student) rather than one VPC per
# student, which would multiply NAT/IGW/route-table overhead for no real
# isolation benefit -- security groups are stateful and default-deny, so a
# shared VPC with per-tenant subnets + SGs is enough to guarantee no
# east-west traffic between students. See docs/DECISIONS.md.
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Private DNS namespace for service discovery. This is how the cache gets a
# stable hostname (e.g. cache.cybered-lab.internal) instead of tenant
# containers being handed a raw task IP that changes on every redeploy.
resource "aws_service_discovery_private_dns_namespace" "lab" {
  name = "${var.project_name}.internal"
  vpc  = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-namespace"
  }
}

# Public route table shared by every subnet. Fargate tasks are launched with
# a public IP (assign_public_ip = true, set in the app/cache modules) purely
# so they can reach ECR/S3/DNS without a NAT Gateway -- avoiding ~$0.045/hr
# + data processing charges that would eat into the $50 cap for very little
# benefit in a short-lived lab. Reachability from the open internet is
# controlled entirely by security groups, not by subnet routing, so this
# does not weaken tenant-to-tenant isolation.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# --- Per-student subnets -----------------------------------------------------
#
# Each student gets a dedicated /24 carved out of the VPC CIDR, indexed by
# their stable roster index (0..N-1). Reserving index 200+ for shared
# services (below) assumes a class roster of well under 200 students, which
# comfortably covers a cohort-scale deployment; documented here rather than
# hidden.
resource "aws_subnet" "tenant" {
  for_each = var.students

  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value.index)
  map_public_ip_on_launch = true

  tags = {
    Name  = "${var.project_name}-${each.value.sanitized_id}-subnet"
    Owner = each.value.sanitized_id
  }
}

resource "aws_route_table_association" "tenant" {
  for_each = aws_subnet.tenant

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- Shared services subnet (cache) ------------------------------------------
resource "aws_subnet" "shared" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 200)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-shared-services-subnet"
  }
}

resource "aws_route_table_association" "shared" {
  subnet_id      = aws_subnet.shared.id
  route_table_id = aws_route_table.public.id
}

# --- Per-student security groups --------------------------------------------
#
# Deliberately created with NO inline ingress/egress blocks. Rules are
# attached as standalone aws_vpc_security_group_*_rule resources below so
# that this SG and the cache SG can reference each other's IDs without
# forming a dependency cycle.
resource "aws_security_group" "tenant" {
  for_each = var.students

  name        = "${var.project_name}-${each.value.sanitized_id}-sg"
  description = "Isolation boundary for student ${each.value.sanitized_id}. No rule in this group ever references another student's security group."
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name  = "${var.project_name}-${each.value.sanitized_id}-sg"
    Owner = each.value.sanitized_id
  }
}

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Centralized cache. Ingress allowed only from each tenant security group on the cache port."
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

# Inbound: terminal access restricted to the authorized user's IP/CIDR per
# the candidate environment sheet (not 0.0.0.0/0). ttyd still requires
# per-student basic-auth credentials generated in tenant_app.
resource "aws_vpc_security_group_ingress_rule" "tenant_app_ingress" {
  for_each = var.students

  security_group_id = aws_security_group.tenant[each.key].id
  description       = "Application/terminal access for authorized user only"
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_ingress_cidr
}

# Outbound: the ONLY east-west rule any tenant SG has is to the cache SG,
# scoped to the cache port. There is intentionally no rule, in any tenant
# security group, that references another tenant's security group.
resource "aws_vpc_security_group_egress_rule" "tenant_to_cache" {
  for_each = var.students

  security_group_id            = aws_security_group.tenant[each.key].id
  description                  = "Reach the centralized cache, and only the cache"
  referenced_security_group_id = aws_security_group.cache.id
  from_port                    = var.cache_port
  to_port                      = var.cache_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tenant_https_egress" {
  for_each = var.students

  security_group_id = aws_security_group.tenant[each.key].id
  description       = "Pull the container image from ECR / reach AWS APIs"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "tenant_dns_egress" {
  for_each = var.students

  security_group_id = aws_security_group.tenant[each.key].id
  description       = "DNS resolution"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Cache security group rules ---------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "cache_from_tenant" {
  for_each = var.students

  security_group_id            = aws_security_group.cache.id
  description                  = "Allow student ${each.value.sanitized_id} to reach the cache, and nothing else"
  referenced_security_group_id = aws_security_group.tenant[each.key].id
  from_port                    = var.cache_port
  to_port                      = var.cache_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "cache_https_egress" {
  security_group_id = aws_security_group.cache.id
  description       = "Pull the cache container image from ECR / reach AWS APIs"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "cache_dns_egress" {
  security_group_id = aws_security_group.cache.id
  description       = "DNS resolution"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
}
