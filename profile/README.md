# RaceFlowECI

> Organización GitHub del proyecto **RaceFlow** — ECI · Arquitecturas de Software (ARSW)

---

## Contenido

- [Descripción](#descripción)
- [Repositorios](#repositorios)
- [Stack tecnológico](#stack-tecnológico)
- [Cómo ejecutar la demo localmente](#cómo-ejecutar-la-demo-localmente)
- [Qué mostrar en la demo](#qué-mostrar-en-la-demo)
- [Arquitectura (C4)](#arquitectura-c4)
- [Observabilidad](#observabilidad)

---

## Descripción

**RaceFlow** es una plataforma web de **salas de entrenamiento colaborativas en tiempo real**
para deportes de cronometraje (ciclismo, atletismo, triatlón).

Los atletas crean o se unen a salas mediante un código, transmiten su posición GPS en vivo
desde el navegador, ven un mapa compartido con todos los participantes, consultan el ranking
actualizado al instante y envían reacciones durante la sesión.

Al finalizar, cada sesión queda persistida y disponible como historial para análisis posterior.

**Contexto académico:** proyecto integrador de la materia *Arquitecturas de Software (ARSW)*
de la Escuela Colombiana de Ingeniería Julio Garavito.

---

## Repositorios

| Repositorio | Puerto | Responsabilidad |
|---|---|---|
| [`raceflow-frontend`](https://github.com/RaceFlowECI/raceflow-frontend) | — | SPA React + TypeScript + Leaflet.js: mapa en vivo, ranking, reacciones, historial |
| [`raceflow-api-gateway`](https://github.com/RaceFlowECI/raceflow-api-gateway) | 8080 | Punto de entrada único — enruta REST y WebSocket, valida JWT |
| [`raceflow-auth-service`](https://github.com/RaceFlowECI/raceflow-auth-service) | 8081 | Registro, login y emisión de tokens JWT |
| [`raceflow-room-service`](https://github.com/RaceFlowECI/raceflow-room-service) | 8082 | Ciclo de vida de salas: creación, ingreso por código, participantes |
| [`raceflow-realtime-service`](https://github.com/RaceFlowECI/raceflow-realtime-service) | 8083 | WebSocket + cómputo de ranking + difusión en tiempo real (escala horizontal) |
| [`raceflow-session-service`](https://github.com/RaceFlowECI/raceflow-session-service) | 8084 | Persistencia de sesiones finalizadas e historial |
| [`raceflow-metrics-service`](https://github.com/RaceFlowECI/raceflow-metrics-service) | 8085 | KPIs de negocio calculados desde eventos del broker |
| [`raceflow-observability`](https://github.com/RaceFlowECI/raceflow-observability) | — | Stack Docker Compose: Prometheus, Grafana, Loki, Tempo, Alertmanager |

---

## Stack tecnológico

### Backend

| Tecnología | Rol |
|---|---|
| Java 21 + Spring Boot 3.2.5 | Base de todos los microservicios |
| Spring Cloud Gateway | API Gateway — enrutamiento y autenticación JWT |
| Spring WebSocket | Canal de tiempo real para posiciones y ranking |
| Spring Data JPA + PostgreSQL | Persistencia relacional (auth, rooms, sessions, metrics) |
| Spring Data Redis | Estado compartido de salas y ranking entre réplicas |
| Spring AMQP + RabbitMQ | Bus de eventos asíncronos entre servicios |
| Micrometer + Prometheus | Métricas de negocio y técnicas |
| Logstash Logback Encoder | Logs estructurados JSON |
| OpenTelemetry Java Agent | Trazas distribuidas (api-gateway, room, realtime) |

### Frontend

| Tecnología | Rol |
|---|---|
| React 18 + TypeScript | Framework UI |
| Vite 5 | Build tool y dev server |
| React Router 6 | Navegación SPA |
| Leaflet.js + OpenStreetMap | Mapa interactivo con posiciones GPS en vivo |

### Infraestructura y observabilidad

| Tecnología | Versión | Rol |
|---|---|---|
| Docker + Docker Compose | — | Contenerización y orquestación local |
| Prometheus | v2.51.0 | Scraping de métricas cada 15 s |
| Grafana | 10.4.0 | Dashboards y alerting |
| Loki | 2.9.4 | Almacenamiento de logs |
| Promtail | 2.9.4 | Recolección de logs JSON |
| Tempo | 2.4.0 | Backend de trazas OTLP |
| Alertmanager | v0.27.0 | Enrutamiento de alertas |

---

## Cómo ejecutar la demo localmente

> ⚠️ **Importante**: la lógica de negocio (registro/login, salas, WebSocket, ranking, Gateway,
> gRPC interno) todavía vive en **ramas feature abiertas**, no en `develop`. Hasta que esos PRs
> se mergeen, hay que clonar y hacer checkout a las ramas indicadas abajo — `develop`/`main`
> por sí solos no levantan la demo completa.

### 0. Requisitos

- Java 21, Maven, Node 18+, Docker Desktop
- Los 4 repos clonados como carpetas **hermanas** dentro de una misma carpeta padre (ej. `Proyecto/`)

```
Proyecto/
├── raceflow-auth-service/
├── raceflow-realtime-service/
├── raceflow-api-gateway/
├── raceflow-frontend/
└── docker-compose.dev.yml   ← crear este archivo (contenido abajo)
```

### 1. Ramas a usar por repo

| Repo | Rama | PR |
|---|---|---|
| `raceflow-auth-service` | `feature/grpc-user-profile` | [#12](https://github.com/RaceFlowECI/raceflow-auth-service/pull/12) + [#13](https://github.com/RaceFlowECI/raceflow-auth-service/pull/13) |
| `raceflow-realtime-service` | `feature/grpc-user-profile` | [#14](https://github.com/RaceFlowECI/raceflow-realtime-service/pull/14) + [#15](https://github.com/RaceFlowECI/raceflow-realtime-service/pull/15) |
| `raceflow-api-gateway` | `feature/gateway-routing` | [#13](https://github.com/RaceFlowECI/raceflow-api-gateway/pull/13) |
| `raceflow-frontend` | `feature/connect-backend` | [#6](https://github.com/RaceFlowECI/raceflow-frontend/pull/6) |

```bash
git clone https://github.com/RaceFlowECI/raceflow-auth-service.git      && cd raceflow-auth-service      && git checkout feature/grpc-user-profile && cd ..
git clone https://github.com/RaceFlowECI/raceflow-realtime-service.git  && cd raceflow-realtime-service  && git checkout feature/grpc-user-profile && cd ..
git clone https://github.com/RaceFlowECI/raceflow-api-gateway.git       && cd raceflow-api-gateway       && git checkout feature/gateway-routing   && cd ..
git clone https://github.com/RaceFlowECI/raceflow-frontend.git          && cd raceflow-frontend          && git checkout feature/connect-backend   && cd ..
```

### 2. Infraestructura (Postgres, Redis, RabbitMQ)

Crear `docker-compose.dev.yml` en la carpeta padre con este contenido:

```yaml
services:
  postgres-auth:
    image: postgres:15-alpine
    container_name: raceflow-postgres-auth
    environment:
      POSTGRES_DB: auth
      POSTGRES_USER: raceflow
      POSTGRES_PASSWORD: secret
    ports: ["5432:5432"]

  redis:
    image: redis:7-alpine
    container_name: raceflow-redis
    ports: ["6379:6379"]

  rabbitmq:
    image: rabbitmq:3-management
    container_name: raceflow-rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: raceflow
      RABBITMQ_DEFAULT_PASS: raceflow2026
    ports: ["5672:5672", "15672:15672"]
```

```bash
docker compose -f docker-compose.dev.yml up -d
```

### 3. Levantar los 3 backends (una terminal por servicio)

```bash
# Terminal 1 — auth-service (REST :8081 + gRPC server :9090)
cd raceflow-auth-service && mvn spring-boot:run

# Terminal 2 — realtime-service (REST+WS :8083, cliente gRPC hacia auth-service)
cd raceflow-realtime-service && mvn spring-boot:run

# Terminal 3 — api-gateway (:8080, enruta a los dos anteriores)
cd raceflow-api-gateway && mvn spring-boot:run
```

Esperar a ver `Started AuthApplication`, `Started RealtimeApplication` y `Started GatewayApplication`
en cada consola (y en la de auth-service, la línea `gRPC server started on 9090`).

### 4. Levantar el frontend

```bash
cd raceflow-frontend
npm install
npm run dev
```

Abrir **http://localhost:5173**

### 5. Verificación rápida (opcional, antes de mostrarlo)

```bash
curl http://localhost:8081/actuator/health   # auth-service   -> {"status":"UP"}
curl http://localhost:8083/actuator/health   # realtime-service -> {"status":"UP"}
curl http://localhost:8080/actuator/health   # api-gateway    -> {"status":"UP"}
```

---

## Qué mostrar en la demo

1. **Registro/login real** en http://localhost:5173 — abrir DevTools → Network para que se vea
   la llamada HTTP real al backend (no datos mockeados).
2. **Crear una sala** → mapa Leaflet con tu posición GPS real (o el aviso de fallback si no das
   permiso de ubicación).
3. **Segunda pestaña/navegador**, unirse a la misma sala con otra cuenta → ambos se ven en el
   mapa y en el ranking en tiempo real vía WebSocket.
4. **Prueba del canal gRPC interno** (lo más fuerte de la demo arquitectónica): registrar un
   usuario con un nombre real, y crear la sala mandando un nombre *distinto* directo por
   `curl`/Postman a `POST :8083/rooms/create`. Al consultar `GET :8083/rooms/{code}/state` se ve
   que ganó el nombre real (consultado por gRPC contra `auth-service:9090`), no el que mandó el
   cliente — prueba que `realtime-service` valida internamente contra la fuente de verdad en vez
   de confiar en el request.
5. **Gateway real**: repetir el registro pero pegándole a `POST :8080/api/auth/register` en vez
   de `:8081/auth/register` — mismo resultado, demuestra que el Gateway enruta de verdad
   (`spring.cloud.gateway.routes` dejó de estar vacío).
6. **CI/CD como evidencia de calidad**: cualquiera de los PRs listados arriba, mostrando los
   checks en verde — `Tests + JaCoCo (85%)` y `SonarCloud Code Analysis` — no solo "funciona en
   mi máquina".
7. Mapeo completo de los 6 estilos de comunicación distribuida (Sockets, HTTP, RMI, gRPC,
   Microservicios, API Gateway) contra la arquitectura real: [`docs/architecture/EVOLUCION_ARQUITECTONICA.md`](../docs/architecture/EVOLUCION_ARQUITECTONICA.md).

---

## Arquitectura (C4)

Los diagramas siguen el [modelo C4](https://c4model.com/) y fueron generados con
[Structurizr Lite](https://structurizr.com/help/lite).
El modelo fuente está en [`docs/architecture/workspace.dsl`](../docs/architecture/workspace.dsl).

### Nivel 1 — Contexto del sistema

> Muestra los actores externos (Atleta, Servicio de Mapas, API de Geolocalización)
> y su relación de alto nivel con la plataforma RaceFlow.

![Diagrama de Contexto](https://raw.githubusercontent.com/RaceFlowECI/.github/main/docs/architecture/export/structurizr-Contexto.png)

### Nivel 2 — Contenedores

> Desglosa el sistema en sus contenedores desplegables:
> la SPA React, el API Gateway, los 5 microservicios Spring Boot,
> Redis, RabbitMQ y las 4 bases de datos PostgreSQL.

![Diagrama de Contenedores](https://raw.githubusercontent.com/RaceFlowECI/.github/main/docs/architecture/export/structurizr-Contenedores.png)

### Nivel 3 — Componentes del Realtime Service

> Zoom en el servicio más crítico de RaceFlow.
> Muestra los componentes internos: `RoomWebSocketHandler`, `PositionIngestor`,
> `RankingService`, `RankingStrategy` (Strategy pattern), `RoomStateClient` y `EventPublisher`.

![Diagrama de Componentes — Realtime Service](https://raw.githubusercontent.com/RaceFlowECI/.github/main/docs/architecture/export/structurizr-Componentes_Realtime.png)

> Para editar los diagramas, ver [`docs/architecture/README.md`](../docs/architecture/README.md).

---

## Observabilidad

El laboratorio de observabilidad instrumenta los 6 microservicios con la tríada:
**métricas + logs + trazas**.

| Pilar | Tecnología | Detalle |
|---|---|---|
| Métricas | Micrometer → Prometheus | Endpoint `/actuator/prometheus` en cada servicio. SLO: ranking p99 ≤ 1 s |
| Logs | Logstash Logback Encoder → Loki | JSON estructurado con rotación diaria. Consultas con LogQL |
| Trazas | OpenTelemetry Java Agent → Tempo | Adjunto vía Dockerfile multi-stage en api-gateway, room y realtime |

**3 alertas activas:**

| Alerta | Condición | Severidad |
|---|---|---|
| `RaceFlowServiceDown` | `up == 0` por 1 min | critical |
| `RaceFlowHighErrorRate` | 5xx > 5% por 2 min | warning |
| `RaceFlowRankingLatencyHigh` | ranking p99 > 1 s por 3 min | critical |

Documentación completa: [`raceflow-observability/OBSERVABILIDAD.md`](https://github.com/RaceFlowECI/raceflow-observability/blob/develop/OBSERVABILIDAD.md)