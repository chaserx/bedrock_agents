# aws provider
provider "aws" {
  region = "us-east-1"
}

# data sources
data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}
locals {
  account_id = data.aws_caller_identity.this.account_id
  partition  = data.aws_partition.this.partition
  region     = data.aws_region.this.name
}

# bedrock foundation model
data "aws_bedrock_foundation_model" "this" {
  model_id = "anthropic.claude-3-haiku-20240307-v1:0"
}

# bedrock agent trust policy
data "aws_iam_policy_document" "fake_telematics_agent_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["bedrock.amazonaws.com"]
      type        = "Service"
    }
    condition {
      test     = "StringEquals"
      values   = [local.account_id]
      variable = "aws:SourceAccount"
    }
    condition {
      test     = "ArnLike"
      values   = ["arn:${local.partition}:bedrock:${local.region}:${local.account_id}:agent/*"]
      variable = "AWS:SourceArn"
    }
  }
}


data "aws_iam_policy_document" "fake_telematics_agent_permissions" {
  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      data.aws_bedrock_foundation_model.this.model_arn
    ]
  }
}

# bedrock agent role
resource "aws_iam_role" "fake_telematics_agent" {
  assume_role_policy = data.aws_iam_policy_document.fake_telematics_agent_trust.json
  name_prefix        = "AmazonBedrockExecutionRoleForAgents_"
}

# bedrock agent policy
resource "aws_iam_role_policy" "fake_telematics_agent_policy" {
  name = "AmazonBedrockAgentBedrockFoundationModelPolicy_ftd"
  role = aws_iam_role.fake_telematics_agent.id
  policy = data.aws_iam_policy_document.fake_telematics_agent_permissions.json
}

# lambda execution role
data "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole"
}

# Action group Lambda execution role
resource "aws_iam_role" "lambda_fake_telematics_api" {
  name = "FunctionExecutionRoleForLambda_Fake_Telematics_API"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"  
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"  
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Lambda basic execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_fake_telematics_api.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution.arn
}

# Lambda policy
resource "aws_lambda_permission" "fake_telematics_api" {
  action         = "lambda:invokeFunction"
  function_name  = module.lambda_function.lambda_function_name
  principal      = "bedrock.amazonaws.com"
  source_account = local.account_id
  source_arn     = "arn:aws:bedrock:${local.region}:${local.account_id}:agent/*"
}

# create bedrock agent
resource "aws_bedrockagent_agent" "fake_telematics_agent" {
  agent_name              = "FakeTelematicsAgent"
  agent_resource_role_arn = aws_iam_role.fake_telematics_agent.arn
  description             = "An assisant that provides fake telematics information."
  foundation_model        = data.aws_bedrock_foundation_model.this.model_id
  instruction             = "You are an assistant that looks up telematics data from the equipment fleet from the Fake Telematics API. You can include information about the equipment but your are currently limited to just providing an answer on total distance traveled. Do not provide any other information about the equipment. If you can't provide that information, then say 'Sorry, I can't help with that.'"
  prepare_agent = true
  skip_resource_in_use_check = true
}

# bedrock action group
resource "aws_bedrockagent_agent_action_group" "fake_telematics_action_group" {
  action_group_name = "FakeTelematicsActionGroup"
  agent_id = aws_bedrockagent_agent.fake_telematics_agent.id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  prepare_agent = true
  description = "An action group that provides fake telematics information."
  action_group_executor {
    lambda = module.lambda_function.lambda_function_arn
  }
  function_schema {
    member_functions {
      functions {
        name        = "fake-telematics-function-equipment-distance"  
        description = "Get the total distance traveled by all equipment"
      }
    }
  }
}

# action group lambda function
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.20.1"

  function_name = "fake-telematics-function-equipment-distance"
  description   = "A telematics function for getting the total distance traveled by all equipment"
  handler       = "src.fake_telematics.lambda_handler"
  runtime       = "python3.13"
  timeout       = 300
  create_package = false
  local_existing_package = "./fake_telematics.zip"
  ignore_source_code_hash = true
  depends_on = [
    null_resource.uv_build
  ]
}

# build the lambda function into a zip file using uv
# There are multiple ways to do this, but this is the most straightforward. 
# Other options include using a docker image or using lambda layers.
# https://docs.astral.sh/uv/guides/integration/aws-lambda/#deploying-a-zip-archive
resource "null_resource" "uv_build" {
  provisioner "local-exec" {
    command = "./build_lambda.sh"
  }
}
