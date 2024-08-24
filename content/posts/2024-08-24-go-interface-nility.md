+++
title = 'Common Go Footguns: Interface Nility'
date = 2024-08-24
toc = true
tags = ["go", "golang", "footguns"]
summary = "Describing the common footgun of checking an interface for nil"
featured_image="/images/2024-05-29-golang-coverage-mocks/gopher.png"
+++

This post is the first in a series about common Go footguns that I regularly see in code reviews, or in this case footguns that get me on occasion.

## Go interfaces are surprising

Consider this simple code sample ([go playground](https://go.dev/play/p/gbRgUIJR7mS))

```go
package main

import "fmt"

type SillyIntf interface {
    DoSilly()
}

type SillyImpl struct {
    printStr string
}

func (s *SillyImpl) DoSilly() {
    fmt.Println(s.printStr)
}

func callDoSilly(silly SillyIntf) {
    if silly != nil {
        silly.DoSilly()
    }
}

func main() {
    var silly *SillyImpl
    callDoSilly(silly)
}

```

At first glance, it appears that callDoSilly is safe to call with the nil silly pointer. We do check for nil after all! The most sensible outcome from running this code would be to print an empty line. Unfortunately if you actually run the code it will panic. This behavior is surprising, and in my opinion quite the flaw in the language.

## Why is it like this?

Go interfaces are pointers that point at a "thing" that implements the interface. In this case, a pointer to a `SillyImpl` implements `SillyIntf` with `DoSilly`. Because we access the receiver pointer `s` in the `DoSilly` function, and s is nil, we panic.

The version of the code below would actually be quite safe to run ([playground](https://go.dev/play/p/lmelkf9hZVr)):

```go
package main

import "fmt"

type SillyIntf interface {
    DoSilly()
}

type SillyImpl struct {
}

func (s *SillyImpl) DoSilly() {
    fmt.Println("Perfectly safe to call")
}

func callDoSilly(silly SillyIntf) {
    if silly != nil {
        silly.DoSilly()
    }
}

func main() {
    var silly *SillyImpl
    callDoSilly(silly)
}
```

This version of the code results in `"Perfectly safe to call"` being printed. While not nearly as bad a panic, this is still likely not the authors intention.

## What should be done?

If we were able to redesign the calling code to explicitly pass nil to callDoSilly instead of a nil pointer value the problem would vanish. This approach is actually a typical pattern in Go, which is why this particular footgun doesn't come up that often.

We can't always update the code that calls our functions. We still need to check for nil, so reflection is really the only safe way to check for interface nility.

```go
// IsNil returns true if i is nil, or is an interface that points
// to a nil implementation
func IsNil(i any) bool {
    if i == nil {
        return true
    }
    v := reflect.ValueOf(i)
    if !v.IsValid() {
        return true
    }
    switch v.Kind() {
    case reflect.Ptr, reflect.Slice, reflect.Map, reflect.Func, reflect.Interface:
        return v.IsNil()
    default:
    return false
    }
}
```
