data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_internet_gateway" "main" {
  vpc_id = data.terraform_remote_state.persistent.outputs.vpc_id

  tags = {
    Name = "project-bedrock-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = data.terraform_remote_state.persistent.outputs.vpc_id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "project-bedrock-public-${count.index}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "project-bedrock-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "project-bedrock-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = data.terraform_remote_state.persistent.outputs.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "project-bedrock-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = data.terraform_remote_state.persistent.outputs.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "project-bedrock-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = data.terraform_remote_state.persistent.outputs.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private.id
}