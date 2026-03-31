# TP2 - Analisis de ApacheBench

- Generado: `2026-03-31T01:56:29Z`
- Endpoint base: `http://127.0.0.1:8080/pi`
- Requests por corrida: `500`
- Iteraciones: `10000,100000,1000000`
- Concurrencias: `1,10,50`

## Tabla base

| i | c | req/s | mean ms | p95 ms | failed |
| --- | --- | --- | --- | --- | --- |
| 10000 | 1 | 2574.85 | 0.39 | 0.00 | 0 |
| 10000 | 10 | 10493.62 | 0.95 | 1.00 | 0 |
| 10000 | 50 | 9836.71 | 5.08 | 6.00 | 0 |
| 100000 | 1 | 865.00 | 1.16 | 1.00 | 0 |
| 100000 | 10 | 4125.86 | 2.42 | 3.00 | 0 |
| 100000 | 50 | 4559.88 | 10.96 | 15.00 | 0 |
| 1000000 | 1 | 137.82 | 7.26 | 9.00 | 0 |
| 1000000 | 10 | 609.97 | 16.39 | 21.00 | 0 |
| 1000000 | 50 | 649.56 | 76.98 | 122.00 | 0 |

## Tabla derivada

| i | speedup c=10 | speedup c=50 | p95 penalty c=10 | p95 penalty c=50 |
| --- | --- | --- | --- | --- |
| 10000 | 4.08 | 3.82 | inf | inf |
| 100000 | 4.77 | 5.27 | 3.00 | 15.00 |
| 1000000 | 4.43 | 4.71 | 2.33 | 13.56 |

## Analisis automatico

- i=10000: mejora moderada hasta c=10 (speedup 4.08x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=100000: mejora moderada hasta c=10 (speedup 4.77x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=1000000: mejora clara hasta c=10 (speedup 4.43x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion

## Conclusion

- No se observaron failed requests: el servidor fue robusto en el rango probado.
- En general el servidor escala bien al menos hasta la primera concurrencia evaluada por encima de c=1.
- A concurrencias altas aparece saturacion: el throughput deja de crecer en proporcion y la latencia aumenta.
- Hay un tradeoff visible entre throughput y latencia: aun cuando mejora el req/s, el p95 crece de forma apreciable.
