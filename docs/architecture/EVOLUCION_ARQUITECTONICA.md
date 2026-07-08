# Evolución arquitectónica de RaceFlow

> Mapeo del sistema real de RaceFlow contra los estilos arquitectónicos de comunicación
> distribuida trabajados en el Taller Integrador ARSW 2026-I (Sockets TCP → HTTP → RMI →
> gRPC → Microservicios → API Gateway), con evidencia de funcionamiento real, no solo
> teórica.

## 1. Los 6 estilos, aplicados o justificadamente descartados

| Estilo | ¿Lo usa RaceFlow? | Dónde / por qué |
|---|---|---|
| **Sockets TCP crudos** | No | RaceFlow necesita interoperar con un navegador (fetch/WebSocket) y con clientes REST estándar. Un protocolo de texto propio sobre sockets (como `MOVIE:1`) obligaría a reimplementar manualmente framing, parsing, timeouts y manejo de errores que HTTP y WebSocket ya resuelven — sin ninguna ganancia a cambio en este dominio. |
| **HTTP** | **Sí** | `auth-service` (`/auth/register`, `/auth/login`, `/auth/me`) y `realtime-service` (`/rooms/create`, `/rooms/join`, `/rooms/{code}/state`) exponen REST sobre HTTP. Es el único estilo consumible directamente desde el navegador sin cliente especial. |
| **RMI** | No | RMI exige que cliente y servidor sean JVMs Java (stubs/skeletons generados, `rmiregistry`, classpath compartido). El cliente real de RaceFlow es una SPA React — RMI sencillamente no puede hablar con un navegador. Incluso para comunicación *interna* Java-a-Java se prefirió gRPC (ver más abajo) por ser políglota y no acoplar la evolución interna del sistema al ecosistema Java. |
| **gRPC** | **Sí** (interno) | Canal `realtime-service → auth-service` (`UserProfileService`, puerto 9090). Ver sección 3. |
| **Microservicios** | **Sí** | 6 servicios independientes y desplegables por separado: `auth-service` (8081), `room-service` (8082), `realtime-service` (8083), `session-service` (8084), `metrics-service` (8085), `api-gateway` (8080). Cada uno con su propio `pom.xml`, pipeline CI/CD y (donde aplica) su propia base de datos. |
| **API Gateway** | **Sí** | `raceflow-api-gateway` (Spring Cloud Gateway). Ver sección 2. |

## 2. API Gateway — de `routes: []` a enrutamiento real

Antes de este trabajo, `raceflow-api-gateway` compilaba y arrancaba, pero no enrutaba nada:
`spring.cloud.gateway.routes: []`. Era el hueco exacto que el taller enseña a resolver.

Rutas activas hoy:

```yaml
routes:
  - id: auth-service
    uri: ${AUTH_SERVICE_URL:http://localhost:8081}
    predicates: [Path=/api/auth/**]
    filters: [RewritePath=/api/auth/(?<segment>.*), /auth/${segment}]
  - id: realtime-rooms
    uri: ${REALTIME_SERVICE_URL:http://localhost:8083}
    predicates: [Path=/api/rooms/**]
    filters: [RewritePath=/api/rooms/(?<segment>.*), /rooms/${segment}]
```

**Decisión consciente**: el WebSocket de `realtime-service` (`/ws/room/{roomCode}`) **no** pasa
por el Gateway. Spring Cloud Gateway puede proxiar WebSocket, pero añade una capa reactiva
adicional (buffering, timeouts distintos, reconexión) que no aporta valor proporcional al
alcance de este ejercicio — el frontend conecta el WS directo a `realtime-service:8083`. Es
el mismo tipo de trade-off que el taller pide identificar explícitamente ("¿Qué complejidad
agrega el Gateway al sistema?").

### Evidencia

```bash
$ curl -X POST http://localhost:8080/api/auth/register \
    -H "Content-Type: application/json" \
    -d '{"email":"gateway-test@raceflow.dev","password":"secret123","name":"Gateway Test","sport":"running"}'

{"token":"eyJhbGciOiJIUzI1NiJ9...","email":"gateway-test@raceflow.dev","name":"Gateway Test"}
```

Mismo resultado que pegarle directo a `auth-service:8081/auth/register` — el cliente ya no
necesita conocer el puerto 8081, solo el Gateway (8080).

## 3. gRPC interno — resolver un gap real, no un ejemplo de juguete

**El problema real**: `realtime-service` no tenía ninguna fuente de verdad para el nombre de
un atleta. `RoomManager.createRoom`/`joinRoom` confiaban ciegamente en el campo `name` que
mandaba el cliente HTTP — cualquiera podía crear una sala como "Cristiano Ronaldo" sin que el
backend lo verificara contra nada, a pesar de que `auth-service` ya tiene el nombre real del
usuario en Postgres desde el registro.

Esto es exactamente lo que RPC con contrato fuerte resuelve: comunicación interna
servicio-a-servicio, tipada, sin que el cliente externo pueda falsificarla.

### Contrato (`user_profile.proto`, idéntico en ambos repos)

```proto
service UserProfileService {
  rpc GetProfile (ProfileRequest) returns (ProfileResponse);
}
message ProfileRequest  { string email = 1; }
message ProfileResponse { bool found = 1; string email = 2; string name = 3; string sport = 4; }
```

- **`auth-service`** expone el servicio en el puerto **9090** (servidor gRPC manual,
  `ServerBuilder.forPort(9090).addService(...).build().start()`, arrancado desde un
  `@PostConstruct` no bloqueante para no interferir con el arranque de Spring Boot).
- **`realtime-service`** consume vía `GrpcAuthClient` (`ManagedChannel` + stub bloqueante,
  timeout de 2s). Si la llamada falla (auth-service caído, timeout, `UNAVAILABLE`), **no
  rompe la creación de la sala**: cae de vuelta al nombre que mandó el cliente y deja un
  `log.warn`. Es un patrón de resiliencia real, no solo un checkbox académico.

### Evidencia end-to-end (no solo compilación)

```bash
# 1. Registrar con el nombre REAL
$ curl -X POST http://localhost:8080/api/auth/register -d '{
    "email":"grpc-proof@raceflow.dev","password":"secret123",
    "name":"Nombre Real De Auth","sport":"natacion"}'
→ token: eyJhbGci...

# 2. Crear sala mandando un nombre DISTINTO en el body
$ curl -X POST http://localhost:8083/rooms/create -H "Authorization: Bearer <token>" \
    -d '{"name":"NOMBRE FALSO DEL CLIENTE"}'
→ {"roomCode":"2B9FB9","createdBy":"grpc-proof@raceflow.dev"}

# 3. Consultar el estado de la sala
$ curl http://localhost:8083/rooms/2B9FB9/state -H "Authorization: Bearer <token>"
→ {"roomCode":"2B9FB9","athletes":[{
     "email":"grpc-proof@raceflow.dev",
     "name":"Nombre Real De Auth",   ← ganó el dato autoritativo vía gRPC, no el del cliente
     ...
   }]}
```

El nombre guardado es el que vive en Postgres (consultado vía gRPC), no el que mandó el
`POST /rooms/create`. Esa es la prueba de que el canal gRPC realmente se está usando en el
flujo de creación de salas.

## 4. Diagrama actualizado

```
                         ┌──────────────────┐
   Atleta (navegador) ──▶│  raceflow-frontend │
                         └────────┬──────────┘
                                  │
                    ┌─────────────┼──────────────────────┐
                    │ HTTPS (REST)│           WS directo  │
                    ▼             │                       ▼
           ┌─────────────────┐   │            ┌───────────────────┐
           │  api-gateway    │   │            │  realtime-service  │
           │ (Spring Cloud   │   │            │  :8083 (WS+REST)   │
           │  Gateway) :8080 │   │            └─────────┬──────────┘
           └────────┬────────┘   │                      │
                     │            │                      │ gRPC interno
        ┌────────────┴────┐       │                      │ (:9090, UserProfileService)
        ▼                  ▼      │                      ▼
 ┌──────────────┐  ┌──────────────┴───┐         ┌──────────────────┐
 │ auth-service │◀─┘                  └────────▶│   auth-service    │
 │ :8081 (REST) │                                │ :9090 (gRPC)      │
 └──────┬───────┘                                └─────────┬─────────┘
        │                                                    │
        ▼                                                    ▼
   PostgreSQL (auth)                                  (mismo Postgres)
```

## 5. Reflexión — ¿por qué no un monolito?

Un monolito habría sido más simple de arrancar para RaceFlow, pero rompe rápido con las
necesidades reales del dominio: `realtime-service` necesita escalar horizontalmente de forma
independiente durante picos de carga (muchas salas activas transmitiendo GPS en simultáneo),
mientras que `auth-service` es de baja frecuencia y alta sensibilidad (credenciales, JWT). Un
monolito acoplaría el ciclo de despliegue de ambos, y un bug en el cálculo de ranking podría
tumbar el login de todo el sistema.

La contrapartida — y es real, no retórica — es que ahora RaceFlow paga los costos que el
taller advierte en cada estilo: el Gateway es un punto único de fallo si no se replica; el
canal gRPC agrega una dependencia de red donde antes había una llamada de método en memoria
(por eso el fallback ante fallo de auth-service no es opcional, es obligatorio); y la
observabilidad (trazas, métricas, logs) tiene que correlacionar eventos across 6 procesos en
vez de leer un solo stack trace. Ninguna de estas decisiones es gratis — son trade-offs
conscientes, tomados porque el dominio (entrenamiento en tiempo real, con salas efímeras y
alta frecuencia de escritura) los justifica más que la simplicidad operativa de un monolito.
