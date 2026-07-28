# The habit the challenge is really teaching. This stack should idle at roughly
# fifty cents a month, so anything approaching five dollars means something is
# running that was not meant to be.
#
# Deliberately unfiltered and account wide. Scoping it to the services this
# project already uses would remove the only property that matters, which is
# catching the thing nobody anticipated. The known cost of that choice is the
# annual domain renewal, which trips it once a year for a reason that takes two
# seconds to confirm in Cost Explorer.
#
# No provider alias: Budgets is a global service and the SDK routes it to its
# own endpoint regardless of the configured region.
resource "aws_budgets_budget" "monthly" {
  name         = "christiansantiago-dev-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Actual spend, at four fifths of the limit. The early warning, while there is
  # still room to act before the number is one worth caring about.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Forecast, at the full limit. This is the one that catches a resource left
  # running on day three, where actual spend is still small but the trend is
  # not. Waiting for actual spend to cross the line wastes most of the month.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
