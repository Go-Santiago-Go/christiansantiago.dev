# One item, keyed on the literal string "site". A sort key would be a value
# every call has to supply for nothing in return, and the single partition
# ceiling of roughly 1,000 writes per second is accepted rather than sharded.
resource "aws_dynamodb_table" "visits" {
  name = "christiansantiago-dev-visits"

  # Costs nothing at idle. PROVISIONED reserves throughput around the clock and
  # is what you get by omitting this.
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  # Keys are the only attributes DynamoDB indexes, so they are the only ones it
  # accepts here. visits is created by the first ADD.
  attribute {
    name = "id"
    type = "S"
  }
}
