# TP2 - Analisis de ApacheBench

- Generado: `2026-03-31T01:56:44Z`
- Endpoint base: `http://127.0.0.1:8080/pi`
- Requests por corrida: `500`
- Iteraciones: `10000,100000,1000000`
- Concurrencias: `1,10,50`

## Tabla base

| i | c | req/s | mean ms | p95 ms | failed |
| --- | --- | --- | --- | --- | --- |
| 10000 | 1 | 2581.47 | 0.39 | 0.00 | 0 |
| 10000 | 10 | 9877.52 | 1.01 | 1.00 | 0 |
| 10000 | 50 | 8797.71 | 5.68 | 7.00 | 0 |
| 100000 | 1 | 779.26 | 1.28 | 2.00 | 0 |
| 100000 | 10 | 4134.49 | 2.42 | 3.00 | 0 |
| 100000 | 50 | 4815.05 | 10.38 | 14.00 | 0 |
| 1000000 | 1 | 131.29 | 7.62 | 9.00 | 0 |
| 1000000 | 10 | 419.36 | 23.85 | 29.00 | 0 |
| 1000000 | 50 | 578.75 | 86.39 | 145.00 | 0 |

## Tabla derivada

| i | speedup c=10 | speedup c=50 | p95 penalty c=10 | p95 penalty c=50 |
| --- | --- | --- | --- | --- |
| 10000 | 3.83 | 3.41 | inf | inf |
| 100000 | 5.31 | 6.18 | 1.50 | 7.00 |
| 1000000 | 3.19 | 4.41 | 3.22 | 16.11 |

## Analisis automatico

- i=10000: mejora moderada hasta c=10 (speedup 3.83x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=100000: mejora clara hasta c=10 (speedup 5.31x), y a c=50 la latencia empeora fuerte (p95 x7.00)
- i=1000000: mejora moderada hasta c=10 (speedup 3.19x), y a c=50 la latencia empeora fuerte (p95 x16.11)

## Conclusion

- No se observaron failed requests: el servidor fue robusto en el rango probado.
- En general el servidor escala bien al menos hasta la primera concurrencia evaluada por encima de c=1.
- A concurrencias altas aparece saturacion: el throughput deja de crecer en proporcion y la latencia aumenta.
- Hay un tradeoff visible entre throughput y latencia: aun cuando mejora el req/s, el p95 crece de forma apreciable.
