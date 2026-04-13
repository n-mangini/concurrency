# TP2 - Analisis de ApacheBench

- Generado: `2026-03-31T21:15:41Z`
- Endpoint base: `http://127.0.0.1:8080/pi`
- Requests por corrida: `500`
- Iteraciones: `10000,100000,1000000`
- Concurrencias: `1,10,50`

## Tabla base

| i | c | req/s | mean ms | p95 ms | failed |
| --- | --- | --- | --- | --- | --- |
| 10000 | 1 | 2140.87 | 0.47 | 1.00 | 0 |
| 10000 | 10 | 7358.46 | 1.36 | 3.00 | 0 |
| 10000 | 50 | 7707.25 | 6.49 | 9.00 | 0 |
| 100000 | 1 | 834.65 | 1.20 | 2.00 | 0 |
| 100000 | 10 | 5386.65 | 1.86 | 3.00 | 0 |
| 100000 | 50 | 6166.52 | 8.11 | 12.00 | 0 |
| 1000000 | 1 | 147.79 | 6.77 | 8.00 | 0 |
| 1000000 | 10 | 847.21 | 11.80 | 15.00 | 0 |
| 1000000 | 50 | 950.27 | 52.62 | 98.00 | 0 |

## Tabla derivada

| i | speedup c=10 | speedup c=50 | p95 penalty c=10 | p95 penalty c=50 |
| --- | --- | --- | --- | --- |
| 10000 | 3.44 | 3.60 | 3.00 | 9.00 |
| 100000 | 6.45 | 7.39 | 1.50 | 6.00 |
| 1000000 | 5.73 | 6.43 | 1.88 | 12.25 |

## Analisis automatico

- i=10000: mejora moderada hasta c=10 (speedup 3.44x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=100000: mejora clara hasta c=10 (speedup 6.45x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=1000000: mejora clara hasta c=10 (speedup 5.73x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion

## Conclusion

- No se observaron failed requests: el servidor fue robusto en el rango probado.
- En general el servidor escala bien al menos hasta la primera concurrencia evaluada por encima de c=1.
- A concurrencias altas aparece saturacion: el throughput deja de crecer en proporcion y la latencia aumenta.
- Hay un tradeoff visible entre throughput y latencia: aun cuando mejora el req/s, el p95 crece de forma apreciable.
