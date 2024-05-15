provider "aws" {
  region = var.REGION
}

resource "aws_ecs_cluster" "my_cluster" {
  name = var.CLUSTER_NAME
}


resource "aws_lb" "lms_lb" {
  name               = var.LOAD_BALANCER_NAME
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-016e2591b7f949d99"]
  subnets            = ["subnet-0ffd405711375c017", "subnet-0e63b67043cd1f4aa"]
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.lms_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = 200
      message_body = "OK"
    }
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name        = var.TARGET_GROUP_NAME
  port        = 2000
  protocol    = "HTTP"
  vpc_id      = "vpc-0816ba4118fcc07c3"
  target_type = "ip"
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "ecs_update_service_policy" {
  name        = "ecs_update_service_policy"
  path        = "/"
  description = "Policy to allow ecs:UpdateService on specific service"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "ecs:UpdateService",
        Resource = "arn:aws:ecs:ap-south-1:905418133399:service/lms/import-sql"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_update_service_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_update_service_policy.arn
}



resource "aws_elasticache_subnet_group" "my_redis_subnet" {
  name       = "lms-redis"
  subnet_ids = ["subnet-0ffd405711375c017", "subnet-0e63b67043cd1f4aa"]
}


resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "my-db-subnet-group"
  subnet_ids = ["subnet-0ffd405711375c017", "subnet-0e63b67043cd1f4aa"]

}

resource "aws_elasticache_cluster" "my_redis" {
  cluster_id           = "redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.my_redis_subnet.name
  security_group_ids   = ["sg-016e2591b7f949d99"]
}

resource "aws_db_parameter_group" "postgresql" {
  name   = "custom-postgresql"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }
}

resource "aws_db_instance" "my_db" {
  allocated_storage = 10
  storage_type      = "gp2"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  db_name           = "postgres"
  identifier        = "postgres-db"
  username          = "Adil12341"
  password          = "Adil1234"

  vpc_security_group_ids = ["sg-016e2591b7f949d99"]
  db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.name
  skip_final_snapshot    = true
  publicly_accessible    = true
  storage_encrypted      = true
  parameter_group_name   = aws_db_parameter_group.postgresql.name

  lifecycle {
    ignore_changes = [password]
  }


}

output "db_instance_endpoint" {
  value = aws_db_instance.my_db.endpoint
}

resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = var.TASKNAME
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn
  container_definitions = jsonencode([
    {
      name  = "lms-test",
      image = "905418133399.dkr.ecr.ap-south-1.amazonaws.com/lms-test:latest",
      portMappings = [{
        containerPort = 2000,
        hostPort      = 2000
      }]
      environment = [
        {
          name  = "REDIS_URL",
          value = "redis://${aws_elasticache_cluster.my_redis.cache_nodes[0].address}:6379"
        },
        {
          name  = "DB_HOST",
          value = "${aws_db_instance.my_db.address}"
        },
        {
          name  = "DB_PORT",
          value = "5432"
        },
        {
          name  = "DB_NAME",
          value = aws_db_instance.my_db.db_name
        },
        {
          name  = "DB_USER",
          value = aws_db_instance.my_db.username
        },
        {
          name  = "DB_PASSWORD",
          value = aws_db_instance.my_db.password
        }
      ]
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "ecs_logs",
          "awslogs-region" : "ap-south-1",
          "awslogs-stream-prefix" : "streaming"
        }
      }
    }
  ])
  depends_on = [aws_ecs_service.import_sql_service]
}

resource "aws_ecs_task_definition" "sql_import" {
  family                   = "sqlimporttask"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "512"
  cpu                      = "256"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name       = "import-sql",
    image      = "postgres:16-alpine"
    essential  = true
    entryPoint = ["sh", "-c"]
    command = [
      "apk add --no-cache aws-cli 1> /dev/null && echo 'packages installed' && echo 'Downloading SQL file from S3...' && aws s3 cp s3://backupsqldump/tetr.sql /tmp/initial_data.sql && ls -l /tmp/initial_data.sql && echo 'Importing SQL file into PostgreSQL...' && PGPASSWORD=Adil1234 psql -h ${aws_db_instance.my_db.address} -p 5432 -U Adil12341 -d postgres -f /tmp/initial_data.sql && echo 'Backup and import finished'"
    ]
    "logConfiguration" : {
      "logDriver" : "awslogs",
      "options" : {
        "awslogs-group" : "ecs_logs",
        "awslogs-region" : "ap-south-1",
        "awslogs-stream-prefix" : "streaming"
      }
    }
  }])
}


resource "aws_lb_listener_rule" "my_listener_rule" {
  listener_arn = aws_lb_listener.my_listener.arn
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_ecs_service" "my_service" {
  name            = var.ECS_SERVICE_NAME
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task_definition.arn

  network_configuration {
    security_groups  = ["sg-016e2591b7f949d99"]
    subnets          = ["subnet-0ffd405711375c017", "subnet-0e63b67043cd1f4aa"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.my_target_group.arn
    container_name   = "lms-test"
    container_port   = 2000
  }
  depends_on = [
    aws_lb_listener_rule.my_listener_rule,
    aws_db_instance.my_db,
  ]

  desired_count = 1

  enable_ecs_managed_tags = true

  deployment_controller {
    type = "ECS"
  }

  launch_type = "FARGATE"
}

resource "aws_ecs_service" "import_sql_service" {
  name            = "import-sql"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.sql_import.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    security_groups  = ["sg-016e2591b7f949d99"]
    subnets          = ["subnet-0ffd405711375c017", "subnet-0e63b67043cd1f4aa"]
    assign_public_ip = true
  }
  depends_on = [aws_ecs_task_definition.sql_import]
}


resource "aws_appautoscaling_target" "ecs_service" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.my_cluster.name}/${aws_ecs_service.my_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [
    aws_ecs_service.my_service,
  ]
}

resource "aws_appautoscaling_policy" "ecs_scaling_policy_cpu" {
  name        = "ecs-scaling-policy-cpu"
  policy_type = "TargetTrackingScaling"

  resource_id        = "service/${aws_ecs_cluster.my_cluster.name}/${aws_ecs_service.my_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 300

    target_value = 60.0
  }

  depends_on = [
    aws_appautoscaling_target.ecs_service,
  ]
}


