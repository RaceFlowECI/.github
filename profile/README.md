# RaceFlowECI

> Organización GitHub del proyecto **RaceFlow** — ECI · Arquitecturas de Software (ARSW)

---

## Contenido

- [Descripción](#descripción)
- [Repositorios](#repositorios)
- [Stack tecnológico](#stack-tecnológico)
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