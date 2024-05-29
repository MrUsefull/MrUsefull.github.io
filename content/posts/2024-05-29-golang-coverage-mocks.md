+++
title = 'Golang Coverage Mocks'
date = 2024-05-29
toc = true
tags = ["go", "golang", "coverage", "mocks", "build"]
featured_image="/images/2024-05-29-golang-coverage-mocks/gopher.png"
summary = "Excluding generated mocks from code coverage"
+++

Some projects make rather heavy use of gomock for testing, and I've noticed the command that I had been using to run all tests and generate coverage included the mocks in coverage and brought the numbers down.

We can't allow numbers to go down! Here's an altered Makefile snippet to generate test coverage.

## Command

```makefile
test:
    $(eval COV_PKGS=$(shell go list ./... | grep -v mock_ | tr '\n' ','))
    go test ./... -race -cover -covermode=atomic -coverprofile=build/cover.out -coverpkg $(COV_PKGS) 
    go tool cover -func build/cover.out | grep total

```

## Explanation

All of the mocks for this project are under sub packages with the pattern `mock_${PKG_HERE}`. Some important interface in package thingy will have a mock in the package `path/to/thingy_pkg/mock_thingy_pkg/thingy.go`.

Explanation of the commands:

1. eval a variable `COV_PKGS`
    * execute `go list ./...`
    * Filter all packages that contain `mock_` with `grep -v`
    * Replace the newline in the output with a `,`

2. Tell go to only calculate coverage on the packages in `${COV_PKGS}`
