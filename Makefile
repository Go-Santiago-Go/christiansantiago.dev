.PHONY: counter test e2e fmt plan apply destroy

BINARY := counter/bin/bootstrap

# Cross compiled for the Lambda runtime, which supplies an OS and no libc, so
# the binary has to be static. Stripping symbols and debug info halves the
# upload, and the upload has to be pulled before a cold start can begin.
counter:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build -C counter -trimpath -ldflags="-s -w" -o bin/bootstrap ./cmd/counter

test:
	go test -C counter -race -cover ./...

# Runs against the deployed site, so it asserts on whatever is live right now
# rather than on the working tree. Point SITE_URL elsewhere to retarget it.
e2e:
	npm --prefix e2e test

fmt:
	go fmt -C counter ./...
	terraform -chdir=infra fmt

# Terraform packages the binary but cannot build it, so every path that reads
# the archive builds it first.
plan: counter
	terraform -chdir=infra plan

apply: counter
	terraform -chdir=infra apply

destroy:
	terraform -chdir=infra destroy
