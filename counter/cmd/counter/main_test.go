package main

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

type stubCounter struct {
	count int64
	err   error
}

func (s stubCounter) Increment(context.Context) (int64, error) {
	return s.count, s.err
}

func TestHandler(t *testing.T) {
	tests := []struct {
		name       string
		counter    stubCounter
		wantStatus int
		wantBody   string
	}{
		{
			name:       "counts the visit",
			counter:    stubCounter{count: 42},
			wantStatus: http.StatusOK,
			wantBody:   `{"count":42}`,
		},
		{
			name:       "increment fails",
			counter:    stubCounter{err: errors.New("throughput exceeded")},
			wantStatus: http.StatusInternalServerError,
			wantBody:   `{"error":"could not record visit"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := handler(tt.counter)(context.Background(), events.APIGatewayV2HTTPRequest{})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if resp.StatusCode != tt.wantStatus {
				t.Errorf("status = %d, want %d", resp.StatusCode, tt.wantStatus)
			}
			if resp.Body != tt.wantBody {
				t.Errorf("body = %s, want %s", resp.Body, tt.wantBody)
			}
			if got := resp.Headers["Content-Type"]; got != "application/json" {
				t.Errorf("content type = %q, want %q", got, "application/json")
			}
		})
	}
}

// The DynamoDB error must not reach the caller, only the log.
func TestHandlerDoesNotLeakInternalErrors(t *testing.T) {
	secret := "table christiansantiago-dev-visits not found"

	resp, err := handler(stubCounter{err: errors.New(secret)})(context.Background(), events.APIGatewayV2HTTPRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if strings.Contains(resp.Body, "christiansantiago-dev-visits") {
		t.Errorf("body leaks the table name: %s", resp.Body)
	}
	if strings.Contains(resp.Body, secret) {
		t.Errorf("body leaks the underlying error: %s", resp.Body)
	}
}
