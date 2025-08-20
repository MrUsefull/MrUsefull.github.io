+++
title = 'Common Go Footguns: Debug Logging'
date = 2025-07-28
draft = false
toc = true
tags = ["Go","Golang","Footguns"]
summary = "This is the third post in a series on common go footguns about how debug logging can have surprising performance impacts"
+++

Technically, the problem discussed in this post is not really about debug logging. Debug logging is just the main place where I see this misunderstanding manifest. It is also not specific to Go, I've run across this issue while working in many languages at multiple companies. I've also been paged too many times for this exact problem bringing down a production environment.

Let's start with an example. Assume we have a structured logging library, and that library works as one would expect. An example debug log statement may be:

```go
func AddTwoInts(a int, b int) int {
    // log output from this line would be something like:
    // my values { "a": 123, "b": 456 }
    logging.Debug("my values", logging.Int("a", a), logging.Int("b", b))
    return a+b
}
```

The above snippet is really perfectly fine. If debug logging is enabled, you get a log message. There's not really any noticeable overhead compared to just returning `a + b`.

Let's introduce the problem.


```go
func AddTwoInts(a int, b int) int {
    logging.Debug(complexString(a, b), logging.Int("a", a), logging.Int("b", b))
    return a+b
}

func complexString(a int, b int) string {
    out := ""
    for i := range a {
        for j := range b {
            out += fmt.Sprintf("i=%d,j=%d", i, j)
        }
    }
    return out
}
```

There are a few problems with the new change. The most obvious one is that complexString gives us a garbage string which is useless for actually debugging any issues with our complicated `a + b` function.

The issue more important to this post is that complexString will be fully evaluated before the logging library ever gets a chance to determine if debug logging is enabled or not. This is because arguments to functions must be evaluated prior to the function being evaluated. In some languages, this issue can be avoided with [Lazy Loading](https://en.wikipedia.org/wiki/Lazy_loading). Go does not have that ability.

What happens is that `complexString` is executed, then we enter `logging.Debug`. Inside `logging.Debug`, the library checks if debug logging is enabled or disabled. When enabled, we get a log message. It doesn't matter if debug logging is disabled here, we've already paid the heavy price of calculating `complexString`. Even with debug logging disabled, the code will always pay the price of calling `complexString`.

The worst example of this problem that I've ever seen actually took an algorithm that was `O(n)` prior to debug logging, and turned the function into `O(n!)`. That obviously had disastrous results when deployed to production.

How can we avoid this performance problem, and still have oh-so-useful debug logs given by `complexString`?

```go
func AddTwoInts(a int, b int) int {
    if logging.IsDebugEnabled() {
        logging.Debug(complexString(a, b), logging.Int("a", a), logging.Int("b", b))
    }
    return a+b
}
```

Every single log library that I've ever worked with has the ability to check if a log level is enabled. By hoisting the check to be around the Debug call, we prevent paying the price for `complexString`.

Debug logging issues like this can also be caught and potentially automatically fixed with static analysis, a topic for another time.
