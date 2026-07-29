package visits

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// updaterFunc adapts a plain function to Updater, the way http.HandlerFunc
// adapts a function to http.Handler. Each test supplies behaviour inline
// instead of declaring a struct per case.
type updaterFunc func(context.Context, *dynamodb.UpdateItemInput, ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)

func (f updaterFunc) UpdateItem(ctx context.Context, in *dynamodb.UpdateItemInput, opts ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	return f(ctx, in, opts...)
}

func countOutput(v string) *dynamodb.UpdateItemOutput {
	return &dynamodb.UpdateItemOutput{
		Attributes: map[string]types.AttributeValue{
			"visits": &types.AttributeValueMemberN{Value: v},
		},
	}
}

func TestIncrement(t *testing.T) {
	tests := []struct {
		name    string
		out     *dynamodb.UpdateItemOutput
		err     error
		want    int64
		wantErr bool
	}{
		{name: "returns the updated count", out: countOutput("42"), want: 42},
		{name: "first visit against an empty table", out: countOutput("1"), want: 1},
		{name: "dynamodb call fails", err: errors.New("throughput exceeded"), wantErr: true},
		{name: "response carries no attributes", out: &dynamodb.UpdateItemOutput{}, wantErr: true},
		{name: "count is unparseable", out: countOutput("twelve"), wantErr: true},
		{
			name: "count comes back as a string",
			out: &dynamodb.UpdateItemOutput{
				Attributes: map[string]types.AttributeValue{
					"visits": &types.AttributeValueMemberS{Value: "42"},
				},
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := NewCounter(updaterFunc(func(context.Context, *dynamodb.UpdateItemInput, ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
				return tt.out, tt.err
			}), "test-table")

			got, err := c.Increment(context.Background())

			if tt.wantErr {
				if err == nil {
					t.Fatalf("want error, got count %d", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Errorf("count = %d, want %d", got, tt.want)
			}
		})
	}
}

// Fails if anyone replaces the atomic add with a read followed by a write.
func TestIncrementSendsOneAtomicAdd(t *testing.T) {
	var sent *dynamodb.UpdateItemInput

	c := NewCounter(updaterFunc(func(_ context.Context, in *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
		sent = in
		return countOutput("1"), nil
	}), "visits-table")

	if _, err := c.Increment(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if got := *sent.TableName; got != "visits-table" {
		t.Errorf("table = %q, want %q", got, "visits-table")
	}
	if got := *sent.UpdateExpression; got != "ADD visits :one" {
		t.Errorf("expression = %q, want %q", got, "ADD visits :one")
	}
	if sent.ReturnValues != types.ReturnValueUpdatedNew {
		t.Errorf("return values = %q, want %q", sent.ReturnValues, types.ReturnValueUpdatedNew)
	}

	key, ok := sent.Key["id"].(*types.AttributeValueMemberS)
	if !ok {
		t.Fatalf("key id = %T, want a string attribute", sent.Key["id"])
	}
	if key.Value != "site" {
		t.Errorf("key id = %q, want %q", key.Value, "site")
	}
}

// atomicDB stands in for DynamoDB. The read and the write happen inside one
// lock, which is what UpdateItem guarantees on the server.
type atomicDB struct {
	mu sync.Mutex
	n  int64
}

func (d *atomicDB) UpdateItem(context.Context, *dynamodb.UpdateItemInput, ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.n++
	return countOutput(strconv.FormatInt(d.n, 10)), nil
}

// racyDB is the handler that increments in Go instead: GetItem, add one,
// PutItem. Each half holds the lock, so this is not a data race and -race
// reports nothing. The sleep only widens a window that exists without it,
// making a timing dependent bug reproduce on demand.
type racyDB struct {
	mu sync.Mutex
	n  int64
}

func (d *racyDB) UpdateItem(context.Context, *dynamodb.UpdateItemInput, ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	d.mu.Lock()
	current := d.n
	d.mu.Unlock()

	time.Sleep(time.Millisecond)

	d.mu.Lock()
	defer d.mu.Unlock()

	d.n = current + 1
	return countOutput(strconv.FormatInt(d.n, 10)), nil
}

const concurrentVisitors = 500

// Releases every goroutine at once so the calls genuinely overlap rather than
// trickling out in launch order.
func hammer(t *testing.T, db Updater) {
	t.Helper()

	c := NewCounter(db, "test-table")
	start := make(chan struct{})

	var wg sync.WaitGroup
	for range concurrentVisitors {
		wg.Go(func() {
			<-start
			if _, err := c.Increment(context.Background()); err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}

	close(start)
	wg.Wait()
}

func TestAtomicAddKeepsEveryVisit(t *testing.T) {
	db := &atomicDB{}
	hammer(t, db)

	if db.n != concurrentVisitors {
		t.Errorf("count = %d, want %d", db.n, concurrentVisitors)
	}
}

func TestReadModifyWriteLosesVisits(t *testing.T) {
	db := &racyDB{}
	hammer(t, db)

	if db.n >= concurrentVisitors {
		t.Fatalf("count = %d, expected lost updates below %d", db.n, concurrentVisitors)
	}

	t.Logf("read modify write lost %d of %d visits", concurrentVisitors-db.n, concurrentVisitors)
}
