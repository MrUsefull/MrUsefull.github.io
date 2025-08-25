+++
title = 'Refactoring: Preventing a copy-pasta nightmare'
date = 2025-08-25
toc = true
tags = ["Go", "Golang", "Projects"]
summary = 'An example of how I go about extracting generic usable functionality from existing code'
+++

The goal of this post is to show an example of how to refactor existing code to gain better
reusability, modularization, and generalization.

## Initial Context

Recently I was working on a project to lint debug log statements. The project goals include out of the box
support for multiple popular logging libraries, as well as the ability to configure the linter to work
with any logging library.

For this linter, I want to automatically detect safe functions when possible. A reasonable starting point is linting [zap](https://github.com/uber-go/zap).
For zap specifically, safe functions include `zap.String`, `zap.Int`, `zap.Int64`, `zap.Any` and so on.

The starting code provided below works for one case. But that's not good enough. I know
that I'll need to be able to work with an arbitrary number of logging libraries, and
there's no way I'm maintaining code for every library.

## Starting Code

From funcs package - included for reference

```go
// Description contains a description of a Function.
// Description is used instead of *types.Func for
// ease of configuration.
type Description struct {
  // Package is the package the function is declared in.
  // Should be the full package path.
  Package string
  // Name is the name of the function.
  Name string
}
```

The actual zap field finding code. This is the code we'll be iterating on.

```go
import (
  "debuglint/internal/funcs"
  "go/types"

  "github.com/hashicorp/go-set/v3"
  "golang.org/x/tools/go/packages"
)

const (
  zapPackagePath = "go.uber.org/zap"
  zapFieldType   = "go.uber.org/zap.Field"
)


// AllowedZapFnCalls returns the default zap function calls that are allowed.
func AllowedZapFnCalls() *set.Set[funcs.Description] {
  pkgs, err := packages.Load(
    &packages.Config{
      Mode: packages.NeedTypes | packages.NeedTypesInfo,
    },
    zapPackagePath,
  )
  if err != nil {
    panic(err)
  }

  return findZapFieldFunctions(pkgs)
}

// findZapFieldFunctions discovers all functions in the zap package that return zap.Field.
// These functions (like zap.String, zap.Int, etc.) are considered "safe" for use in
// debug log arguments since they don't perform expensive computations themselves.
// This enables automatic discovery rather than maintaining a hardcoded allowlist.
func findZapFieldFunctions(pkgs []*packages.Package) *set.Set[funcs.Description] {
  s := set.New[funcs.Description](1)

  for _, pkg := range pkgs {
    scope := pkg.Types.Scope()
    for _, name := range scope.Names() {
      obj := scope.Lookup(name)
      if fn, ok := obj.(*types.Func); ok {
        results := fn.Signature().Results()
        if results.Len() == 1 {
          rType := results.At(0).Type().String()
          if rType == zapFieldType {
            s.Insert(
              funcs.Description{
                Package: zapPackagePath,
                Name:    fn.Name(),
              },
            )
          }
        }
      }
    }
  }

  return s
}
```

### Issues and goal

To be clear, the above code works and is reasonably testable. It is by no means terrible code.

But there are some issues.

1. In order to support slog or other logging libraries, the above code would need to either be refactored
  or copy and pasted. Copy and paste is almost never a good pattern to follow.
2. This code depends on internal data structures for this particular project. Not exactly a deal breaker, since
  we are talking about code used internally for a specific project. But it does not need to be this way.
3. The code depends on external data structures from the package set. This again is not a big deal, since
  most of the project also uses set.Set. It just doesn't need to be this way.

So let's try and make our code a little more general and modular.

## First Pass

### Start With Tests

Seriously, you already had tests, right?

The first step should be to write tests for the outermost function whose behavior we do not want to change.
In this case, that function is `AllowedZapFnCalls`. This function happened to already be tested, and exported
functions should generally come with dedicated unit tests anyway.

Included here is a minimal test for correctness.

```go
func TestAllowedZapFnCalls(t *testing.T) {
  t.Parallel()

  tests := []struct {
    name        string
    wantInclude []funcs.Description
    wantNotInclude []funcs.Description
  }{
    {
      name: "Spot check functions",
      wantInclude: []funcs.Description{
        {
          Package: zapPackagePath,
          Name:    "Int",
        },
        {
          Package: zapPackagePath,
          Name:    "String",
        },
      },
      wantNotInclude: []funcs.Description{
        {
          Package: zapPackagePath,
          Name:    "LevelFlag",
        },
      },
    },
  }
  for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
      t.Parallel()

      got := AllowedZapFnCalls()
      // We use ContainsSlice instead of checking for all possible
      // functions because the zap API can change. It's just not
      // reasonable to check every single function.
      assert.True(t, got.ContainsSlice(tt.wantInclude), "Got: %v\nWant:%v\n", got, tt.wantInclude)
      assert.False(t, got.ContainsSlice(tt.wantNotInclude), "Got: %v\nWant:%v\n", got, tt.wantNotInclude)
    })
  }
}
```

### Make the code re-usable within the same package

Create a new file `func_find.go`

```go
package configs

import (
  "debuglint/internal/funcs"
  "go/types"

  "github.com/hashicorp/go-set/v3"
  "golang.org/x/tools/go/packages"
)

func findFuncsThatReturn(pkgPath string, returnType string) *set.Set[funcs.Description] {
  pkgs, err := packages.Load(
    &packages.Config{
      Mode: packages.NeedTypes | packages.NeedTypesInfo,
    },
    pkgPath,
  )
  if err != nil {
    panic(err)
  }

  return scanPkgForFuncs(pkgs, pkgPath, returnType)
}

// scanPkgForFuncs discovers all functions in the pkgPath package that return returnType and only returnType.
func scanPkgForFuncs(pkgs []*packages.Package, pkgPath string, returnType string) *set.Set[funcs.Description] {
  s := set.New[funcs.Description](1)

  for _, pkg := range pkgs {
    scope := pkg.Types.Scope()
    for _, name := range scope.Names() {
      obj := scope.Lookup(name)
      if fn, ok := obj.(*types.Func); ok {
        results := fn.Signature().Results()
        if results.Len() == 1 {
          rType := results.At(0).Type().String()
          if rType == returnType {
            s.Insert(
              funcs.Description{
                Package: pkgPath,
                Name:    fn.Name(),
              },
            )
          }
        }
      }
    }
  }

  return s
}
```

Alter `AllowedZapFnCalls` to use the new altered code.

```go
// AllowedZapFnCalls returns the default zap function calls that are allowed.
func AllowedZapFnCalls() *set.Set[funcs.Description] {
  return findFuncsThatReturn(zapPackagePath, zapFieldType)
}
```

At this point, we now have a fairly general `findFuncsThatReturn` function that can be reused
to support other log libraries. By providing both the package path and return type, we can
support packages such as [slog](https://pkg.go.dev/log/slog). In fact, here's a working slog implementation:

```go
// AllowedSlogCalls is the default set of allowed slog
// structured field calls.
func AllowedSlogCalls() *set.Set[funcs.Description] {
  return findFuncsThatReturn(slogPackagePath, slogFieldType)
}
```

This refactoring is starting to look pretty good. Any new logging libraries will be quite easy to support.

This code is a reasonable place to stop much of the time. For many projects, if I were reviewing a PR with this code, I would happily approve the code!

However, this particular piece of code can be made more reusable without adding undue
burden. There's no need for the code that does the searching to depend on `set.Set` or `funcs.Description` in any way.

We're going to have to flip the dependency relationship.

## Iterator approach

The [iter](https://pkg.go.dev/iter) package introduced in go1.23 lets us remove the data type dependencies from our functionality.

```go
func Returning(pkgPath string, returnType string) (iter.Seq[*types.Func], error) {
  pkgs, err := packages.Load(
    &packages.Config{
      Mode: packages.NeedTypes | packages.NeedTypesInfo,
    },
    pkgPath,
  )
  if err != nil {
    return nil, fmt.Errorf("load package %s: %w", pkgPath, err)
  }

  return scanPkgForFuncs(pkgs, returnType), nil
}

// scanPkgForFuncs discovers all functions in the loaded pkgs package that return returnType and only returnType.
func scanPkgForFuncs(pkgs []*packages.Package, returnType string) iter.Seq[*types.Func] {
  return func(yield func(*types.Func) bool) {
    for _, pkg := range pkgs {
      scope := pkg.Types.Scope()
      for _, name := range scope.Names() {
        obj := scope.Lookup(name)
        if fn, ok := obj.(*types.Func); ok {
          if shouldYield(fn, returnType) && !yield(fn) {
            return
          }
        }
      }
    }
  }
}

func shouldYield(fn *types.Func, returnType string) bool {
  results := fn.Signature().Results()
  if results.Len() != 1 {
    return false
  }

  rType := results.At(0).Type().String()

  return rType == returnType
}
```

This change does several things.

1. Rename the function to Returning. At this point I'm planning to move this to a single purpose package called `funcfind`.
  `funcfind.Returning` is nicer to use.
2. Utilizes iterators to yield a Seq of *types.Func. Naturally, the calling code must also change a little

    ```go
    func findStructuredLogFns(pkgPath string, returnType string) *set.Set[funcs.Description] {
      fnIter, err := funcfind.Returning(pkgPath, returnType)
      if err != nil {
        panic(err)
      }

      s := set.New[funcs.Description](1)
      for fn := range fnIter {
        s.Insert(
          funcs.Description{
            Package: pkgPath,
            Name:    fn.Name(),
          },
        )
      }

      return s
    }
    ```

    The immediate downside of this change is the new need for iterating and building the collection outside of the
    newly renamed `Returning` function. That should be considered OK, since the core logic of `Returning` is
    now focused entirely on finding functions returning a specific type. The newly created funcfind package
    is now doing one thing, and one thing only.

3. `shouldYield` is pulling a bit of somewhat complex decision making into a single place. The change reduces the
  cyclomatic complexity of the calling function, as well as making an easy place to make more complex decisions
  should multiple return values ever be supported (They [are](https://pkg.go.dev/github.com/MrUsefull/FuncFind/pkg/funcfind) now)

### Tradeoffs

The iterator approach does have some tradeoffs. As previously mentioned, the caller must write
a little more code. Developers calling the package must also understand how iterators work.

The upsides however, are significant. By using iterators we remove dependencies on external
data types and focus on the one thing this section of code is supposed to do. It's potentially
more memory efficient, the caller can inspect a single item at a time instead of needing to
load the full data set into memory for processing and manipulation. It's more flexible in that
the caller can decide when or if to continue processing the dataset. Iterators are also composable.
Here's a quick example of finding function names that only start with String:

  ```go
  funcs, _ := funcfind.Returning("go.uber.org/zap", "go.uber.org/zap.Field")
  // onlyStartsWithString is a []string containing all functions that
  // start with String
  onlyStartsWithString := slices.Collect(
    iter.Map(
      iter.Filter(
        funcs,
        func(fn *types.Func) bool {
          return strings.HasPrefix(fn.Name(), "String")
        },
      ),
      func (fn *types.Func) string {
        return fn.Name()
      }
    )
  )
  ```

## Final Look

At this point we have very generic code providing function finding capabilities. In fact, it's so generic I've published it as a [standalone package](https://pkg.go.dev/github.com/MrUsefull/FuncFind/pkg/funcfind)
