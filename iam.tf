# Create IAM role for ECS task execution
resource "aws_iam_role" "ecs_role" {
  name = "role_ecs_tasks"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_execute_role" {
  name = "ecs_execute_role"
  role = aws_iam_role.ecs_role.name

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
       "Effect": "Allow",
       "Action": [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
       ],
      "Resource": "*"
      }
   ]
}
EOF
}

# resource "aws_iam_role_policy_attachment" "ecs_execute_policy_attachment" {
#   role       = aws_iam_role.ecs_role.name
#   policy_arn = aws_iam_role_policy.ecs_execute_role.policy.arn
# }

resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  role = aws_iam_role.ecs_role.name

  # This policy adds logging + ECR permissions
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
