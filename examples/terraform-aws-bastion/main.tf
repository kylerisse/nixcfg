resource "aws_security_group" "bastion" {
  name   = "bastion"
  vpc_id = "vpc-0123456789abcdef0"
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_network_interface" "bastion" {
  subnet_id       = "subnet-0123456789abcdef0"
  security_groups = [aws_security_group.bastion.id]
}

resource "aws_eip" "bastion" {
  vpc               = true
  network_interface = aws_network_interface.bastion.id
}

resource "aws_instance" "bastion" {
  ami              = "ami-06b260b3a958948a0" # NixOS-22.11.466.596a8e828c5-x86_64-linux
  instance_type    = "t3a.micro"
  user_data_base64 = base64encode(file("${path.cwd}/configuration.nix"))

  network_interface {
    network_interface_id = aws_network_interface.bastion.id
    device_index         = 0
  }

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}
