provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.profile.name

  user_data = <<-EOF
              #!/bin/bash
              # 1. Install dependencies
              apt-get update -y
              apt-get install -y qbittorrent-nox unzip curl bc zip

              # 2. AWS CLI Install
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip && ./aws/install

              # 3. Configure qBittorrent (Auth Bypass & Speed Fix)
              mkdir -p /home/ubuntu/.config/qBittorrent
              cat <<EOT > /home/ubuntu/.config/qBittorrent/qBittorrent.conf
              [LegalNotice]
              Accepted=true
              [Preferences]
              WebUI\\Port=8080
              WebUI\\LocalHostAuth=false
              WebUI\\AuthSubnetWhitelistEnabled=true
              WebUI\\AuthSubnetWhitelist=0.0.0.0/0
              WebUI\\HostHeaderValidation=false
              WebUI\\CSRFProtection=false
              Connection\\PortRangeMin=51413
              Net\\PortForwarding=false
              BitTorrent\\DHT=true
              BitTorrent\\PeX=true
              EOT
              chown -R ubuntu:ubuntu /home/ubuntu/.config

              # 4. Inject the local upload.sh file
              cat <<'INNER_EOF' > /home/ubuntu/upload.sh
              ${file("${path.module}/upload.sh")}
              INNER_EOF

              chmod +x /home/ubuntu/upload.sh
              chown ubuntu:ubuntu /home/ubuntu/upload.sh

              # 5. Create Service
              cat <<EOT > /etc/systemd/system/qbittorrent-nox.service
              [Unit]
              Description=qBittorrent
              After=network.target
              [Service]
              User=ubuntu
              ExecStart=/usr/bin/qbittorrent-nox
              Restart=always
              EOT

              systemctl daemon-reload
              systemctl enable --now qbittorrent-nox
              EOF

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
}