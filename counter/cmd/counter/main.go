// Command counter is the Lambda behind the site's visitor count.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/Go-Santiago-Go/christiansantiago.dev/counter/internal/visits"
)

// Well under the function timeout, so a stalled DynamoDB call returns a 500
// the caller can see rather than being cut off by Lambda with no response.
const callTimeout = 3 * time.Second

func main() {
	// Runs once per container. Everything built here is reused by every warm
	// invocation, so the SDK client keeps its connection pool and cached
	// credentials instead of rebuilding them per request.
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	table := os.Getenv("VISITS_TABLE")
	if table == "" {
		slog.Error("VISITS_TABLE is not set")
		os.Exit(1)
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		slog.Error("load aws config", "error", err)
		os.Exit(1)
	}

	counter := visits.NewCounter(dynamodb.NewFromConfig(cfg), table)
	lambda.Start(handler(counter))
}

// incrementer is what the HTTP layer needs from the counter, declared here for
// the same reason visits declares Updater: it lets the handler be tested
// without an AWS client.
type incrementer interface {
	Increment(ctx context.Context) (int64, error)
}

func handler(c incrementer) func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	return func(ctx context.Context, _ events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		ctx, cancel := context.WithTimeout(ctx, callTimeout)
		defer cancel()

		count, err := c.Increment(ctx)
		if err != nil {
			// Logged with the detail, answered without it. The caller learns
			// the request failed and nothing about the table behind it.
			slog.Error("increment visit count", "error", err)
			return respond(http.StatusInternalServerError, map[string]string{"error": "could not record visit"})
		}

		return respond(http.StatusOK, map[string]int64{"count": count})
	}
}

func respond(status int, body any) (events.APIGatewayV2HTTPResponse, error) {
	// Returning an error to lambda.Start produces a 502 with no body, so
	// failures are encoded as responses instead.
	encoded, err := json.Marshal(body)
	if err != nil {
		slog.Error("marshal response", "error", err)
		return events.APIGatewayV2HTTPResponse{StatusCode: http.StatusInternalServerError}, nil
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(encoded),
	}, nil
}
