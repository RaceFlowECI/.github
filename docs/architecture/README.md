# TechCup Fútbol — Documentación de Arquitectura (C4)

Diagramas de arquitectura del sistema usando el [modelo C4](https://c4model.com/) y [Structurizr Lite](https://structurizr.com/help/lite).

## Requisitos previos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y en ejecución.

## Levantar el diagrama

Desde esta misma carpeta (`docs/architecture/`):

```bash
docker compose up
```

Luego abre tu navegador en: **http://localhost:8080**

Para detenerlo:

```bash
docker compose down
```

## Editar el DSL y ver cambios

1. Edita [`workspace.dsl`](workspace.dsl) con cualquier editor de texto.
2. Guarda el archivo.
3. Refresca la página en http://localhost:8080 — Structurizr Lite detecta los cambios automáticamente.

No es necesario reiniciar el contenedor.

## Vistas disponibles

| Vista | ID | Descripción |
|---|---|---|
| **System Context** | `SystemContext` | Muestra a los actores externos (Jugador, Organizador) y su relación de alto nivel con la plataforma TechCup y Azure. |
| **Containers** | `Containers` | Desglosa el sistema en sus contenedores: la SPA React, el API Gateway, los 5 microservicios Spring Boot y las bases de datos PostgreSQL/MongoDB. |

## Estructura del workspace

```
techcup-futbol-dosw/.github
└── docs/
    └── architecture/
        ├── workspace.dsl       ← modelo C4 en DSL de Structurizr
        ├── docker-compose.yml  ← levanta Structurizr Lite
        └── README.md           ← este archivo
```

## Referencia rápida del DSL

| Elemento | Descripción |
|---|---|
| `softwareSystem` | Sistema completo o sistema externo |
| `container` | Proceso/aplicación desplegable dentro del sistema |
| `person` | Actor humano que interactúa con el sistema |
| `autoLayout lr` | Disposición automática izquierda → derecha |
| tag `"Database"` | Renderiza el shape como cilindro (base de datos) |
| tag `"Web Browser"` | Renderiza el shape como ventana de navegador |
