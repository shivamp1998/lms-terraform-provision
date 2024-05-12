

resource "aws_instance" "react-frontend" {
    ami = var.AMIS[var.REGION]
    instance_type = "t2.micro"
    vpc_security_group_ids = ["sg-0e59babbc7f6aeed0"]
} 