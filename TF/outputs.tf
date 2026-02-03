output "qbittorrent_url" {
  value = "http://${aws_instance.server.public_ip}:8080"
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.server.public_ip}"
}
