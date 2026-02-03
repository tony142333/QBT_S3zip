resource "aws_security_group" "sg" {
  name        = "qbittorrent_sg_final"
  description = "Security group for qBittorrent"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Web UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # High-Speed Peer Traffic (TCP & UDP)
  ingress {
    from_port   = 51413
    to_port     = 51413
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 51413
    to_port     = 51413
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}