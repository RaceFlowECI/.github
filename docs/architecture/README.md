# RaceFlow — Documentación de Arquitectura (C4)

Diagramas de arquitectura del sistema usando el [modelo C4](https://c4model.com/)
y [Structurizr Lite](https://structurizr.com/help/lite).

> Para el mapeo de los estilos de comunicación distribuida (sockets, HTTP, RMI, gRPC,
> microservicios, API Gateway) contra la arquitectura real de RaceFlow, ver
> [EVOLUCION_ARQUITECTONICA.md](EVOLUCION_ARQUITECTONICA.md).

## Diagramas exportados

### Nivel 1 — Contexto del sistema

> El Atleta interactúa con la plataforma RaceFlow a través de HTTPS y WebSocket.
> RaceFlow consume el Servicio de Mapas (OpenStreetMap) y la API de Geolocalización del navegador.

![Contexto](export/structurizr-Contexto.png)

### Nivel 2 — Contenedores

> Detalla los contenedores desplegables: la SPA React, el API Gateway (Spring Cloud Gateway),
> los 5 microservicios Spring Boot, Redis, RabbitMQ y las 4 bases de datos PostgreSQL.

![Contenedores](export/structurizr-Contenedores.png)

### Nivel 3 — Componentes del Realtime Service

> Zoom interno del servicio más crítico: `RoomWebSocketHandler` → `PositionIngestor`
> → `RankingService` → `RankingStrategy` (Strategy) → `RoomStateClient` (Redis) → `EventPublisher` (RabbitMQ).

![Componentes Realtime](export/structurizr-Componentes_Realtime.png)

---

## Editar y visualizar los diagramas

**Requisito:** Docker Desktop instalado.

Desde esta carpeta (`docs/architecture/`):

```bash
docker compose up
```

Abrir en el navegador: **http://localhost:8080**

Para detenerlo:

```bash
docker compose down
```

## Editar el DSL y ver cambios en vivo

1. Edita [`workspace.dsl`](workspace.dsl) con cualquier editor de texto.
2. Guarda el archivo.
3. Refresca **http://localhost:8080** — Structurizr Lite detecta los cambios automáticamente.

No es necesario reiniciar el contenedor.

## Vistas disponibles

| Vista | ID | Descripción |
|---|---|---|
| **System Context** | `Contexto` | Actores externos y relación de alto nivel con RaceFlow |
| **Containers** | `Contenedores` | SPA + Gateway + 5 microservicios + Redis + RabbitMQ + 4 DBs |
| **Component** | `Componentes_Realtime` | Componentes internos del Realtime/Ranking Service |

## Estructura

```
docs/architecture/
├── workspace.dsl       ← modelo C4 en DSL de Structurizr
├── workspace.json      ← estado generado por Structurizr Lite
├── docker-compose.yml  ← levanta Structurizr Lite en :8080
├── README.md           ← este archivo
└── export/
    ├── structurizr-Contexto.png
    ├── structurizr-Contexto.mmd
    ├── structurizr-Contenedores.png
    ├── structurizr-Contenedores.mmd
    ├── structurizr-Componentes_Realtime.png
    └── structurizr-Componentes_Realtime.mmd
```

## Referencia rápida del DSL

| Elemento | Descripción |
|---|---|
| `softwareSystem` | Sistema completo o sistema externo |
| `container` | Proceso/aplicación desplegable dentro del sistema |
| `component` | Unidad de código dentro de un contenedor |
| `person` | Actor humano que interactúa con el sistema |
| `autoLayout lr` | Disposición automática izquierda → derecha |
| tag `"Database"` | Renderiza el shape como cilindro |
| tag `"Cache"` | Cilindro rojo (Redis) |
| tag `"Broker"` | Pipe (RabbitMQ) |