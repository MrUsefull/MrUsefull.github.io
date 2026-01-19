+++
title = 'Common Go Footguns: Appending to slices'
date = 2024-08-25
toc = true
tags = ["go", "golang", "footguns", "performance"]
featured_image="/images/2024-05-29-golang-coverage-mocks/gopher.png"
summary = "This is the second post in a series on common Go footguns. This post demonstrates the performance impacts of appending a known number of elements to a slice without doing any pre-allocation. This is one of the most common and easily fixed performance issues I see in pull requests on a regular basis."
+++

This is the second post in a series on common Go footguns. This post demonstrates the performance impacts of appending a known number of elements to a slice without doing any pre-allocation. This is one of the most common and easily fixed performance issues I see in pull requests on a regular basis.

## Scenario

Consider the relatively common scenario of converting one iterable type into a slice. A simple example is to collect a slice of all keys in a map.

```go
func Keys(in map[string]string) []string {
    out := []string{}
    for key := range in {
        out = append(out, key)
    }
    return out
}
```

The Keys function correctly creates a slice of all keys in the map, but is surprisingly slow.

## Initial benchmarks

```go
func BenchmarkKeys(b *testing.B) {
    const size int = 1000000
    bigMap := createBigMap(size)
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        got := Keys(bigMap)
        if len(got) != size {
            b.Fail()
        }
    }
}

func createBigMap(size int) map[string]string {
    out := make(map[string]string, size)
    for i := 0; i < size; i++ {
        out[fmt.Sprintf("key%d", i)] = fmt.Sprintf("value%d", i)
    }
    return out
}
```

The results on my machine, notice the 38 allocations/operation here.

```text
cpu: Intel(R) Core(TM) i7-9850H CPU @ 2.60GHz
BenchmarkKeys-12              19      58427273 ns/op    88017264 B/op          38 allocs/op
PASS
```

## The adjustment

If we simply pre-allocate our slice's maximum size, we'll see a significant performance improvement.

```go
func Keys(in map[string]string) []string {
    // create a slice of length 0 with the underlying array 
    // having an initial max size of len(in)
    out := make([]string, 0, len(in)) 
    for key := range in {
        out = append(out, key)
    }
    return out
}
```

Re-running the benchmarks, we see a roughly 70% performance improvement with only a single allocation per operation.

```text
cpu: Intel(R) Core(TM) i7-9850H CPU @ 2.60GHz
BenchmarkKeys-12              93      17152376 ns/op    16007169 B/op           1 allocs/op
PASS
```

## Why is it like this?

Slices are really just [dynamic arrays](https://en.wikipedia.org/wiki/Dynamic_array). Under the hood slices are backed by simple arrays. Slices have a length and a capacity. The length is the number of elements a slice contains. The capacity is the maximum number of elements the slice can contain before needing to be resized. You can check the capacity of a slice with `cap(sliceVarHere)`. If the current maximum capacity of a slice is N elements, and you try to append N+1 elements then the entire backing array must be replaced.

For example, let's say you start with the following maximally populated array:

```text
[val1][val2][val3]
```

This example array has a capacity of 3, and a length of 3.

Appending to this array requires a larger array. This means we must first allocate a new array, copy all of the values from the first array, then we can add the new item to the first open spot. A typical approach to implementing a dynamic array is to double the maximum size of the array every time we run out of space.

New Array:

```text
[][][][][][]
```

With old array copied over:

```text
[val1][val2][val3][][][]
```

With the appended value:

```text
[val1][val2][val3][val4][][]
```

After appending, the final dynamic array has a capacity of 6 and a length of 4.

You can clearly see that not pre-allocating your slice is far more expensive than some would expect.

Pre-allocation is worth it even when knowing the size of the slice is an expensive operation: [Common Go Footguns: Appending to slices #2](/posts/2026-01-18-go-append-slice-big-o/)