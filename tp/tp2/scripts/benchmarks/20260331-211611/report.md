# TP2 - Analisis de ApacheBench

- Generado: `2026-03-31T21:16:11Z`
- Endpoint base: `http://127.0.0.1:8080/pi`
- Requests por corrida: `500`
- Iteraciones: `10000,100000,1000000`
- Concurrencias: `1,10,50`

## Tabla base

| i | c | req/s | mean ms | p95 ms | failed |
| --- | --- | --- | --- | --- | --- |
| 10000 | 1 | 2530.74 | 0.40 | 0.00 | 0 |
| 10000 | 10 | 9401.68 | 1.06 | 2.00 | 0 |
| 10000 | 50 | 8604.96 | 5.81 | 7.00 | 0 |
| 100000 | 1 | 879.93 | 1.14 | 1.00 | 0 |
| 100000 | 10 | 5877.03 | 1.70 | 2.00 | 0 |
| 100000 | 50 | 6394.03 | 7.82 | 11.00 | 0 |
| 1000000 | 1 | 148.41 | 6.74 | 7.00 | 0 |
| 1000000 | 10 | 789.81 | 12.66 | 16.00 | 0 |
| 1000000 | 50 | 949.41 | 52.66 | 100.00 | 0 |

## Tabla derivada

| i | speedup c=10 | speedup c=50 | p95 penalty c=10 | p95 penalty c=50 |
| --- | --- | --- | --- | --- |
| 10000 | 3.71 | 3.40 | inf | inf |
| 100000 | 6.68 | 7.27 | 2.00 | 11.00 |
| 1000000 | 5.32 | 6.40 | 2.29 | 14.29 |

## Analisis automatico

- i=10000: mejora moderada hasta c=10 (speedup 3.71x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=100000: mejora clara hasta c=10 (speedup 6.68x), pero a c=50 el throughput casi no mejora frente a c=10 y la latencia aumenta, indicando saturacion
- i=1000000: mejora clara hasta c=10 (speedup 5.32x), y a c=50 la latencia empeora fuerte (p95 x14.29)

## Conclusion

- No se observaron failed requests: el servidor fue robusto en el rango probado.
- En general el servidor escala bien al menos hasta la primera concurrencia evaluada por encima de c=1.
- A concurrencias altas aparece saturacion: el throughput deja de crecer en proporcion y la latencia aumenta.
- Hay un tradeoff visible entre throughput y latencia: aun cuando mejora el req/s, el p95 crece de forma apreciable.
