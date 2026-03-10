### 1️⃣ Qué pasa con dos requests simultáneas

Tu servidor es **secuencial**.

Entonces si llega:

```
curl /pi/200000000
```

y tarda mucho, y en paralelo llega otro:

```
curl /pi/10
```

el segundo request **espera** hasta que termine el primero.

Porque el servidor procesa las conexiones así:

```
accept -> handle_client -> accept -> handle_client
```

Es decir, **una detrás de la otra**.

---

### 2️⃣ Por qué pasa eso

Porque:

- todo el servidor corre en **un único thread**
- el cálculo de π es **CPU-bound**
- mientras `calculate_pi()` se ejecuta, el servidor **no puede aceptar ni procesar otras conexiones**

En otras palabras, el thread del servidor queda **bloqueado ejecutando el cálculo** hasta terminar.

---

### 3️⃣ Cómo solucionarlo usando solo `std`

La solución típica es introducir **concurrencia usando threads**.

Cada conexión puede manejarse en un thread distinto:

```
listener.accept()
    ↓
thread::spawn(handle_client)
```

Entonces el flujo pasa a ser:

```
main thread -> acepta conexiones
worker threads -> procesan requests
```

De esta forma múltiples requests pueden ejecutarse **en paralelo**.

Una mejora adicional sería usar un **thread pool**, para evitar crear un número ilimitado de threads si llegan muchas requests simultáneamente.