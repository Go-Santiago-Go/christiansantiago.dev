// Package visits increments and reports the site's visit count.
package visits

import (
	"context"
	"fmt"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// Updater is the one DynamoDB operation this package performs. Declaring it
// here rather than accepting *dynamodb.Client is what lets the tests supply a
// fake: the signature matches the SDK's method exactly, so the real client
// satisfies it without knowing this interface exists.
type Updater interface {
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
}

// Fails to compile if the SDK client ever stops satisfying Updater.
var _ Updater = (*dynamodb.Client)(nil)

// Counter is safe for concurrent use and is built once per Lambda container,
// so warm invocations reuse the SDK client and its connection pool.
type Counter struct {
	db    Updater
	table string
}

func NewCounter(db Updater, table string) *Counter {
	return &Counter{db: db, table: table}
}

// Increment adds one to the stored count and returns the new value.
func (c *Counter) Increment(ctx context.Context) (int64, error) {
	out, err := c.db.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(c.table),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: "site"},
		},
		UpdateExpression: aws.String("ADD visits :one"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":one": &types.AttributeValueMemberN{Value: "1"},
		},
		// Returns only what the ADD touched, so the new count comes back in the
		// same call rather than costing a second read.
		ReturnValues: types.ReturnValueUpdatedNew,
	})
	if err != nil {
		return 0, fmt.Errorf("update visit count: %w", err)
	}

	// DynamoDB puts numbers on the wire as decimal strings to preserve a
	// precision no Go numeric type covers, so the count arrives needing a parse.
	attr, ok := out.Attributes["visits"].(*types.AttributeValueMemberN)
	if !ok {
		return 0, fmt.Errorf("update returned no visits number")
	}

	n, err := strconv.ParseInt(attr.Value, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse visits: %w", err)
	}

	return n, nil
}
