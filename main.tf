# Configuracao do provider da AWS
provider "aws" {
  region = "us-east-1"
  access_key = "*"
  secret_key = "*"
}

# Cria uma instancia de IAM
resource "aws_instance" "servidor" {
  ami           = "ami-042e8287309f5df03"
  instance_type = "t3.micro"
  tags = {
    Name = "ubuntu"
  }
}

# Cria um role que sera usado na funcao lambda
resource "aws_iam_role" "captura-lambda-role" {
  name = "captura-lambda-role"
  assume_role_policy = file("arquivos/lambda-role.json")
}

# Cria a politica que sera usada na funcao lambda
resource "aws_iam_role_policy" "captura-lamdba-policy" {
  name = "captura-lambda-policy"
  role = "captura-lambda-role"
  policy = file("arquivos/lambda-policy.json")
  depends_on = [
    aws_iam_role.captura-lambda-role
  ]
}

# Compacta o arquivo .py em um .zip
data "archive_file" "lambda-zip" {
  type        = "zip"
  source_dir = "captura-dados"
  output_path = "lambda/captura_dados.zip"
}

# Cria funcão lambda
resource "aws_lambda_function" "captura-lambda-function" {
  function_name     = "captura-lambda-function"
  filename          = "lambda/captura_dados.zip"
  role              = aws_iam_role.captura-lambda-role.arn
  runtime           = "python3.8"
  handler           = "captura_dados.lambda_handler"
  timeout           = "60"
  publish           = true
}

# Cria um cloudwacth que será usado para a execucao da função lambda
resource "aws_cloudwatch_event_rule" "cloudwatch-rule" {
  name = "agendamento_captura"
  description = "Agendamento responsavel pela execucao da captura dos dados de 5 em 5 minutos"
  schedule_expression = "rate(5 minutes)"
}

# Designa a funcao lambda de captura de dados ao cloudwatch criado
resource "aws_cloudwatch_event_target" "captura-event" {
  target_id = aws_lambda_function.captura-lambda-function.id
  rule      = aws_cloudwatch_event_rule.cloudwatch-rule.name
  arn       = aws_lambda_function.captura-lambda-function.arn
}

# Define o permissionamento da funcao lambda
resource "aws_lambda_permission" "captura-lambda-permission" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.captura-lambda-function.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.cloudwatch-rule.arn
}

# Cria o kinesis
resource "aws_kinesis_stream" "kinesis-stream" {
  name = "kinesis-stream"
  shard_count = 1
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

}

# Cria o bucket 'raw' no S3
resource "aws_s3_bucket" "s3-bucket-raw" {
  bucket = "raw-lcr"
  acl    = "private"
}

# Cria o role do firehose
resource "aws_iam_role" "firehose-role" {
  name = "firehose-role"

  assume_role_policy = file("arquivos/firehose-role.json")
}

# Cria a politica que sera usada no kinesis e no firehose
resource "aws_iam_role_policy" "firehose-policy" {
  name = "firehose-policy"
  role = "firehose-role"
  policy = file("arquivos/firehose-policy.json")
  depends_on = [
    aws_iam_role.firehose-role
  ]
}

# Cria o firehose
resource "aws_kinesis_firehose_delivery_stream" "firehose-stream-raw" {
  name        = "firehose-stream-raw"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose-role.arn
    bucket_arn = aws_s3_bucket.s3-bucket-raw.arn
  }

  kinesis_source_configuration {
      kinesis_stream_arn = aws_kinesis_stream.kinesis-stream.arn
      role_arn = aws_iam_role.firehose-role.arn
  }
}

# Compacta o arquivo .py em um .zip
data "archive_file" "processamento-lambda-zip" {
  type        = "zip"
  source_dir = "processamento-dados"
  output_path = "lambda/processamento_dados.zip"
}

# Cria a funcao lambda de processamento dos dados
resource "aws_lambda_function" "processamento-lambda-function" {
  function_name     = "processamento-lambda-function"
  filename          = "lambda/processamento_dados.zip"
  role              = aws_iam_role.captura-lambda-role.arn
  runtime           = "python3.8"
  handler           = "processamento_dados.lambda_handler"
  timeout           = "60"
  publish           = true
}

# Cria o bucket 'cleaned_picpay' no S3
resource "aws_s3_bucket" "s3-bucket-cleaned" {
  bucket = "cleaned-lcr"
  acl    = "private"
}

# Cria o firehose de processsamento
resource "aws_kinesis_firehose_delivery_stream" "firehose-stream-cleaned" {
  name        = "firehose-stream-cleaned"
  destination = "extended_s3"

  # Destino
  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose-role.arn
    bucket_arn = aws_s3_bucket.s3-bucket-cleaned.arn

    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.processamento-lambda-function.arn}:$LATEST"
        }
      }
    }
  }

  # Origem
  kinesis_source_configuration {
      kinesis_stream_arn = aws_kinesis_stream.kinesis-stream.arn
      role_arn = aws_iam_role.firehose-role.arn
  }
}
