# Provider
provider "aws" {
  region = "us-west-2"
}

locals {
  instance_type = "t3a.xlarge"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_vpc" "autogpt_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "autogpt_vpc"
  }
}

resource "aws_subnet" "autogpt_public_subnet" {
  vpc_id     = aws_vpc.autogpt_vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "autogpt-public-subnet"
  }
}

resource "aws_internet_gateway" "autogpt_igw" {
  vpc_id = aws_vpc.autogpt_vpc.id

  tags = {
    Name = "autogpt-igw"
  }
}

resource "aws_route_table" "autogpt_rt" {
  vpc_id = aws_vpc.autogpt_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.autogpt_igw.id
  }

  tags = {
    Name = "autogpt-rt"
  }
}

resource "aws_route_table_association" "autogpt_rt_association" {
  subnet_id      = aws_subnet.autogpt_public_subnet.id
  route_table_id = aws_route_table.autogpt_rt.id
}

resource "aws_security_group" "ssh_access" {
  name_prefix = "ssh-access"
  vpc_id      = aws_vpc.autogpt_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "autogpt-sg"
  }
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  key_name   = "linux-key-pair"
  public_key = tls_private_key.key.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.key_pair.key_name}.pem"
  content  = tls_private_key.key.private_key_pem
}

resource "aws_instance" "autogpt_server" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = local.instance_type
  key_name                    = aws_key_pair.key_pair.key_name
  subnet_id                   = aws_subnet.autogpt_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.ssh_access.id]
  associate_public_ip_address = true

  tags = {
    Name = "autogpt-server"
  }

  provisioner "remote-exec" {

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ec2-user"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "sudo yum -y update",
      "sudo yum -y upgrade",
      "sudo yum -y install docker git screen",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker $(whoami)"
    ]
  }

  provisioner "remote-exec" {

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ec2-user"
      private_key = file(local_file.ssh_key.filename)
    }

    inline = [
      "git clone -b stable https://github.com/Significant-Gravitas/Auto-GPT.git",
      "cd Auto-GPT/",
      "cp .env.template .env",
      "sed -i 's/OPENAI_API_KEY=your-openai-api-key/OPENAI_API_KEY=${var.openai_key}/g' .env",
      "docker build -t autogpt .",
      "echo alias start=\\\"docker run -it --env-file=.env -v $PWD/auto_gpt_workspace:/home/ec2-user/auto_gpt_workspace autogpt --continuous\\\" >> ~/.bash_profile"
    ]
  }
}

output "ssh_command" {
  value = "ssh -i ${aws_key_pair.key_pair.key_name}.pem ec2-user@${aws_instance.autogpt_server.public_ip}"
}