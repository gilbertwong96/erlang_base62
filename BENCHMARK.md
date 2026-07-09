# Benchmarks

The following numbers were produced by `just bench-compare` on an
Apple M1 Pro running OTP 29. The `base62` column is the optimized
implementation; `legacy` is the frozen pre-optimization snapshot
under `bench/legacy/base62_legacy.erl`.

Each row is the faster of the two (bolded). `ips` = iterations per
second; `mean`/`median`/`p99` are per-operation latency; `memory` is
the size of the result binary per operation.

## Encode (64 B)

| Library    | ips      | mean          | median        | p99         | memory   |
|------------|----------|---------------|---------------|-------------|----------|
| **base62** | **1.5M** | **679.22 ns** | **500.00 ns** | **3.13 μs** | **91 B** |
| legacy     | 675.5K   | 1.48 μs       | 1.21 μs       | 4.96 μs     | 91 B     |

## Decode (64 B)

| Library    | ips        | mean        | median        | p99         | memory   |
|------------|------------|-------------|---------------|-------------|----------|
| **base62** | **860.6K** | **1.16 μs** | **959.00 ns** | **4.00 μs** | **64 B** |
| legacy     | 643.1K     | 1.55 μs     | 1.29 μs       | 5.71 μs     | 64 B     |

## Encode (1 KB)

| Library    | ips        | mean        | median      | p99          | memory      |
|------------|------------|-------------|-------------|--------------|-------------|
| **base62** | **104.1K** | **9.60 μs** | **9.08 μs** | **16.92 μs** | **1.40 KB** |
| legacy     | 42.9K      | 23.33 μs    | 20.88 μs    | 48.13 μs     | 1.40 KB     |

## Decode (1 KB)

| Library    | ips       | mean         | median       | p99          | memory      |
|------------|-----------|--------------|--------------|--------------|-------------|
| **base62** | **69.8K** | **14.32 μs** | **13.92 μs** | **20.92 μs** | **1.00 KB** |
| legacy     | 44.5K     | 22.49 μs     | 22.08 μs     | 29.13 μs     | 1.00 KB     |

## Encode (16 KB)

| Library    | ips      | mean          | median        | p99           | memory       |
|------------|----------|---------------|---------------|---------------|--------------|
| **base62** | **3.9K** | **254.92 μs** | **253.38 μs** | **304.75 μs** | **22.36 KB** |
| legacy     | 3.0K     | 336.67 μs     | 331.83 μs     | 381.96 μs     | 22.36 KB     |

## Decode (16 KB)

| Library    | ips      | mean          | median        | p99           | memory       |
|------------|----------|---------------|---------------|---------------|--------------|
| **base62** | **3.6K** | **278.71 μs** | **270.54 μs** | **367.75 μs** | **16.00 KB** |
| legacy     | 2.6K     | 384.82 μs     | 377.58 μs     | 470.96 μs     | 16.00 KB     |

## Encode (64 KB)

| Library    | ips       | mean        | median      | p99         | memory       |
|------------|-----------|-------------|-------------|-------------|--------------|
| **base62** | **935.3** | **1.07 ms** | **1.05 ms** | **1.51 ms** | **89.38 KB** |
| legacy     | 729.0     | 1.37 ms     | 1.35 ms     | 1.60 ms     | 89.38 KB     |

## Decode (64 KB)

| Library    | ips       | mean        | median      | p99         | memory       |
|------------|-----------|-------------|-------------|-------------|--------------|
| **base62** | **889.0** | **1.12 ms** | **1.11 ms** | **1.26 ms** | **64.00 KB** |
| legacy     | 651.1     | 1.54 ms     | 1.52 ms     | 1.72 ms     | 64.00 KB     |

## Running the benchmarks

```sh
just bench          # current base62 only
just bench-compare  # A/B against the frozen legacy snapshot
```

The `bench-compare` recipe builds `bench/legacy/base62_legacy.beam`
on demand if it does not already exist.
