# RaceFlow — Checklist de Demo

> Ten esta pestaña abierta durante la presentación. Todo lo de abajo ya fue probado y funciona.

---

## ✅ Antes de empezar — verificar que todo esté arriba

```bash
curl http://localhost:8081/actuator/health   # auth-service   -> {"status":"UP"}
curl http://localhost:8083/actuator/health   # realtime-service -> {"status":"UP"}
curl http://localhost:8080/actuator/health   # api-gateway    -> {"status":"UP"}
docker ps                                     # postgres, redis, rabbitmq -> Up
```

Si algo NO responde `UP`, ir a la sección **"Levantar todo desde cero"** al final de este archivo.

**Si la demo es contra producción (Azure)**, verificar también:

```bash
# Los backend deben responder {"status":"UP"} (mirar el CUERPO, no solo el HTTP 200):
curl https://raceflow-gateway-g8csc0dfh0dxhcax.mexicocentral-01.azurewebsites.net/actuator/health
curl https://raceflow-auth-svc-etcwe5asgrhtfqad.mexicocentral-01.azurewebsites.net/actuator/health
curl https://raceflow-realtime-svc-h4fvhydkd2gthheb.mexicocentral-01.azurewebsites.net/actuator/health
```

⚠️ **Verificar que el frontend muestre datos REALES, no maqueta** (lección aprendida: una vez
producción sirvió la UI vieja con salas inventadas porque `develop` no se había promovido a
`main` — con el CI en verde): abrir https://lively-rock-0066b1e0f.7.azurestaticapps.net, crear
una sala y confirmar que el código que aparece **lo generó el backend** (cambia en cada
creación). Si aparece una lista de "salas activas" precargada o atletas que nadie registró,
producción está sirviendo código viejo → revisar que `main` de `raceflow-frontend` tenga el
último merge de `develop`.

---

## 🎬 Guion de la demo (en orden)

### 1. Registro real
- [ ] Abrir **http://localhost:5173**
- [ ] Abrir DevTools (F12) → pestaña **Network**
- [ ] Registrarse con email real (ej. `demo@raceflow.dev`)
- [ ] **Señalar**: `POST /auth/register` en Network, status 201, JWT real en la respuesta

### 2. Crear sala + mapa
- [ ] Click "Crear sala"
- [ ] Aceptar permiso de ubicación del navegador
- [ ] **Señalar**: el mapa Leaflet se centra en el GPS real, no en un punto fijo

### 3. Tiempo real con dos usuarios — flujo social (amigos + invitación)
- [ ] Ventana de incógnito: registrar un segundo usuario
- [ ] Usuario 2: **Salas → 👥 Amigos** → buscar al usuario 1 por nombre → "+ Agregar"
- [ ] Usuario 1: **Salas → 👥 Amigos** → aparece la solicitud → "Aceptar"
- [ ] Usuario 1 (dentro de su sala, pantalla Ranking): **"👥 Invitar amigos a esta sala"** → Invitar al usuario 2
- [ ] Usuario 2: en Salas aparece el banner **"📩 [nombre] te invitó a su sala"** (se refresca solo, máx. 8 s) → **Unirse**
- [ ] **Señalar**: entró sin teclear ningún código — amistades persistentes (Postgres/auth) + invitaciones efímeras (memoria/realtime); el código de 6 caracteres sigue disponible como opción manual de respaldo
- [ ] **Señalar**: ambas ventanas ven los dos marcadores y el ranking sincronizado en vivo (WebSocket)
- [ ] Bonus: ambos pulsan **"🎙 Unirse a la llamada"** en Ranking → chat de voz P2P (WebRTC) en vivo

### 4. 🔥 La prueba fuerte — gRPC interno funcionando de verdad

```bash
# 1. Registrar con nombre REAL
curl -X POST http://localhost:8081/auth/register -H "Content-Type: application/json" -d "{\"email\":\"prueba-grpc@raceflow.dev\",\"password\":\"secret123\",\"name\":\"Nombre Verdadero\",\"sport\":\"ciclismo\"}"
```
- [ ] Copiar el `token` de la respuesta

```bash
# 2. Crear sala mandando un nombre FALSO
curl -X POST http://localhost:8083/rooms/create -H "Authorization: Bearer PEGA_TOKEN" -H "Content-Type: application/json" -d "{\"name\":\"Nombre Falso Que Invento\"}"
```
- [ ] Copiar el `roomCode` de la respuesta

```bash
# 3. Consultar el estado de la sala
curl http://localhost:8083/rooms/PEGA_ROOMCODE/state -H "Authorization: Bearer PEGA_TOKEN"
```
- [ ] **Señalar**: el nombre guardado es **"Nombre Verdadero"**, NO el falso — `realtime-service` verificó contra `auth-service` vía gRPC (puerto 9090) antes de guardar, en vez de confiar en el request del cliente.

### 5. El Gateway enrutando de verdad

```bash
curl -X POST http://localhost:8080/api/auth/register -H "Content-Type: application/json" -d "{\"email\":\"via-gateway@raceflow.dev\",\"password\":\"secret123\",\"name\":\"Via Gateway\"}"
```
- [ ] **Señalar**: mismo resultado que pegarle directo a `:8081`, pero pasó por el punto de entrada único `:8080`

### 6. Evidencia de calidad (CI/CD)
- [ ] Abrir https://github.com/RaceFlowECI/raceflow-auth-service (badge/Actions en verde)
- [ ] Abrir https://github.com/RaceFlowECI/raceflow-realtime-service (badge/Actions en verde)
- [ ] **Señalar**: tests con cobertura ≥85% (JaCoCo) + análisis estático (SonarCloud) — no solo "compila"

### 7. Documento de arquitectura (si preguntan por el análisis formal)
- [ ] Mostrar https://github.com/RaceFlowECI/.github/blob/main/docs/architecture/EVOLUCION_ARQUITECTONICA.md
- [ ] Mapeo de los 6 estilos de comunicación distribuida (Sockets, HTTP, RMI, gRPC, Microservicios, API Gateway) contra lo que RaceFlow usa realmente, con justificación de lo que NO se usó y por qué

---

## 🔧 Levantar todo desde cero (si algo se cayó)

Orden estricto — cada uno en su propia terminal, esperar el mensaje de "listo" antes de pasar al siguiente:

**1. Docker Desktop + infraestructura**
```bash
cd "C:\Users\jsegu\Documents\2026\Proyecto"
docker compose -f docker-compose.dev.yml up -d
```

**2. auth-service** — esperar `gRPC server started on 9090` y `Started AuthApplication`
```bash
cd "C:\Users\jsegu\Documents\2026\Proyecto\raceflow-auth-service"
mvn spring-boot:run
```

**3. realtime-service** — esperar `Started RealtimeApplication`
```bash
cd "C:\Users\jsegu\Documents\2026\Proyecto\raceflow-realtime-service"
mvn spring-boot:run
```

**4. api-gateway** — esperar `Started GatewayApplication`
```bash
cd "C:\Users\jsegu\Documents\2026\Proyecto\raceflow-api-gateway"
mvn spring-boot:run
```

**5. Frontend** — esperar `Local: http://localhost:5173/`
```bash
cd "C:\Users\jsegu\Documents\2026\Proyecto\raceflow-frontend"
npm run dev
```

**6. Verificar** con los 3 `curl` de la sección "Antes de empezar" antes de presentar.

---

## 📌 Notas rápidas por si preguntan

- **Todo está promovido a `main` y desplegado en producción**: los 6 backend en Azure App Service y el frontend en Azure Static Web Apps (https://lively-rock-0066b1e0f.7.azurestaticapps.net), verificado end-to-end desde celular. Detalle completo en `docs/architecture/DESPLIEGUE.md`.
- **La demo puede ser local o contra producción** — el flujo es idéntico. Ojo: en producción el gRPC realtime→auth usa el fallback (App Service no expone el puerto 9090 entre apps sin VNet), así que la prueba fuerte del gRPC (paso #4) conviene hacerla en local.
- **Puertos**: Gateway 8080, Auth 8081 (REST) + 9090 (gRPC), Room 8082, Realtime 8083, Session 8084, Metrics 8085, Frontend 5173.
