variable ZONE = {
    default = "ap-south-1a"
}


variable REGION = {
    default = "ap-south-1"
}

variable AMIS = {
    type = map
    default = {
        ap-south-1 : "ami-013e83f579886baeb"
    }
}