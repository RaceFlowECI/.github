# Despliegue en producción — RaceFlow

> Última actualización: 2026-07-09. Sistema completo verificado funcionando end-to-end en producción (registro, salas, mapa y ranking probados desde dispositivo móvil real).

## Visión general

Todo el sistema corre en **Microsoft Azure** bajo una sola suscripción y un solo grupo de recursos (`rg-raceflow-prod`, región Mexico Central). El despliegue de los 7 repositorios (6 microservicios + frontend) sigue el mismo patrón uniforme:

```
push a main  →  GitHub Actions  →  Azure
```

Ningún artefacto se despliega manualmente: el pipeline compila, ejecuta pruebas (JaCoCo ≥85%), pasa el Quality Gate de SonarCloud y solo entonces despliega.

```
                        ┌─────────────────────────────┐
   Usuario (móvil/web)  │  Azure Static Web Apps      │
  ──────────────────────►  raceflow-frontend (React)  │
                        └──────────┬──────────────────┘
                                   │ HTTPS (REST)          WSS (WebSocket)
                                   ▼                          │
                        ┌─────────────────────┐               │
                        │  API Gateway :8080  │               │
                        │  /api/auth/**  ─────┼──► auth-service :8081
                        │  /api/rooms/** ─────┼──► realtime-service :8083 ◄──┘
                        └─────────────────────┘         │        ▲
                                                        │ gRPC :9090
                                                        ▼        │
                                              auth-service (UserProfileService)
```

## Recursos de Azure

| Recurso | Tipo | Notas |
|---|---|---|
| `raceflow-asp` | App Service Plan (Linux, **Basic B3**) | Aloja las 6 apps backend. Empezó en B1, se subió a B2 y finalmente a B3 (~7 GB RAM) porque 6 JVMs de Spring Boot concurrentes saturaban los tiers menores (memoria al 90-98%). |
| `raceflow-gateway` | Web App (Java 21) | Puerto 8080. Spring Cloud Gateway (WebFlux). |
| `raceflow-auth-svc` | Web App (Java 21) | Puerto 8081. También expone gRPC interno en 9090. |
| `raceflow-room-svc` | Web App (Java 21) | Puerto 8082. |
| `raceflow-realtime-svc` | Web App (Java 21) | Puerto 8083. WebSockets habilitados. |
| `raceflow-session-svc` | Web App (Java 21) | Puerto 8084. |
| `raceflow-metrics-svc` | Web App (Java 21) | Puerto 8085. |
| `raceflow-frontend` | **Static Web App** (Free) | React + Vite servido desde CDN global. |
| `raceflow-db-server` | PostgreSQL Flexible Server | 4 bases: `raceflow_auth_db`, `raceflow_room_db`, `raceflow_session_db`, `raceflow_metrics_db`. |
| `raceflow-redis` | Azure Redis Enterprise | TLS obligatorio + clave de acceso. |
| `raceflow-rabbitmq` | Container Instance | Broker AMQP (5672) + consola de administración (15672). |
| `raceflow-keyvault` | Key Vault (RBAC) | Secretos: JWT, contraseña de BD, credenciales RabbitMQ, clave Redis. Las 5 apps de negocio acceden vía Managed Identity con rol `Key Vault Secrets User`. |

### URLs de producción

| Componente | URL |
|---|---|
| **Frontend** | https://lively-rock-0066b1e0f.7.azurestaticapps.net |
| API Gateway | https://raceflow-gateway-g8csc0dfh0dxhcax.mexicocentral-01.azurewebsites.net |
| auth-service | https://raceflow-auth-svc-etcwe5asgrhtfqad.mexicocentral-01.azurewebsites.net |
| room-service | https://raceflow-room-svc-aqgybpeffvb0cvbn.mexicocentral-01.azurewebsites.net |
| realtime-service | https://raceflow-realtime-svc-h4fvhydkd2gthheb.mexicocentral-01.azurewebsites.net |
| session-service | https://raceflow-session-svc-fedte8c0f7frf2dp.mexicocentral-01.azurewebsites.net |
| metrics-service | https://raceflow-metrics-svc-d9bxepdgbpfnf2fe.mexicocentral-01.azurewebsites.net |

> Nota: Azure genera hostnames con sufijo único (`-g8csc0dfh0dxhcax`, etc.). Los hostnames "cortos" (`raceflow-gateway.azurewebsites.net`) **no existen** — ver lección #5 abajo.

## Pipeline de CI/CD (backend, idéntico en los 6 repos)

```
PR o push a main
  ├─ 1. Compile          (mvn compile, Java 21)
  ├─ 2. Tests + JaCoCo    (gate: ≥85% cobertura de líneas)
  ├─ 3. SonarCloud        (Quality Gate obligatorio)
  └─ 4. Deploy a Azure    (solo en push a main; azure/webapps-deploy@v3
                           con publish profile por repo)
```

Ramas: `feature/*` → PR a `develop` → PR `develop` → `main`. El deploy solo se dispara desde `main`.

## Pipeline del frontend

`.github/workflows/azure-swa-deploy.yml` en `raceflow-frontend`:

1. `pnpm install --frozen-lockfile` (el proyecto usa **pnpm**, no npm)
2. `pnpm run build` — el build de Vite incrusta las URLs de producción:
   - `VITE_API_AUTH` → auth-service
   - `VITE_API_RT` → realtime-service
   - `VITE_WS_URL` → `wss://` realtime-service
3. `Azure/static-web-apps-deploy` (anclada a SHA de commit, exigencia de SonarCloud S7637) sube `dist/` con el token guardado como secret `AZURE_STATIC_WEB_APPS_API_TOKEN`.

Los PRs generan **entornos de preview** efímeros que se destruyen al cerrar el PR. `staticwebapp.config.json` define el fallback SPA (`/index.html`) para que las rutas de React Router funcionen al recargar.

## Justificación: ¿por qué Azure Static Web Apps y no Vercel?

Decisión evaluada explícitamente:

- **Coherencia**: todo el backend ya corre en Azure. Un solo proveedor significa una consola, una identidad, una facturación y una historia arquitectónica consistente.
- **Mismo patrón de CI/CD**: GitHub Actions → Azure, idéntico a los 6 microservicios.
- **Costo**: tier Free (CDN global, SSL, 100 GB/mes) dentro de la misma suscripción de estudiante.
- Vercel/Netlify/Firebase Hosting son plataformas robustas y válidas, pero su ventaja (DX para Next.js, ecosistema propio) no aplica aquí y habrían introducido un segundo proveedor sin necesidad técnica.

## Configuración crítica por servicio (App Settings)

Cada Web App define, entre otras:

- `WEBSITES_PORT` — puerto real del servicio (8080–8085). **Sin esto, Azure asume el 80 y la app nunca responde** (lección #1).
- `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` — conexión a PostgreSQL (password vía Key Vault reference).
- `SPRING_REDIS_HOST/PORT/PASSWORD/SSL` — Redis Enterprise exige TLS y clave.
- `RABBITMQ_HOST/PORT/USERNAME/PASSWORD` — el broker rechaza el usuario `guest` en conexiones remotas.
- `JWT_SECRET` — vía Key Vault reference.
- Gateway: `AUTH_SERVICE_URL`, `REALTIME_SERVICE_URL` con los hostnames **completos** (con sufijo).

## Lecciones aprendidas (problemas reales resueltos durante el despliegue)

1. **`WEBSITES_PORT` ausente** → las 6 apps daban timeout total aunque el deploy era "exitoso". Azure enruta al puerto 80 por defecto; hay que declarar el puerto real de cada servicio.
2. **HTTP 200 engañoso** → la página placeholder de Azure ("Hey, Java developers!") responde 200 en cualquier ruta. Verificar siempre el *cuerpo* de la respuesta, no solo el código.
3. **Memoria insuficiente** → 6 JVMs Spring Boot no caben en B1 (~1.75 GB) ni cómodamente en B2 (~3.5 GB). B3 estabilizó la memoria en ~30%.
4. **Nombres de variables de entorno inconsistentes** → los servicios leían `RABBITMQ_USER`/`REDIS_HOST` pero Azure provisionaba `RABBITMQ_USERNAME`/`SPRING_REDIS_HOST`. Sin la credencial, Spring cae al default (`guest`/localhost) y el health check marca `DOWN`. Moraleja: contrato de nombres de env vars único y documentado.
5. **Hostnames con sufijo único** → el gateway apuntaba a `raceflow-auth-svc.azurewebsites.net` (no existe). Azure genera `raceflow-auth-svc-<sufijo>.<región>.azurewebsites.net`.
6. **JAR corrupto por colisión de operaciones** → un deploy concurrente con un restart/resize dejó un `app.jar` truncado (~21 MB menos) que el contenedor no podía arrancar. Se resolvió re-ejecutando el workflow de deploy.
7. **Health checks de Actuator como fuente de verdad** → `/actuator/health` agrega el estado de BD, Redis y RabbitMQ; un `DOWN` señala exactamente qué dependencia falla (visible con detalle en los logs de la app).
8. **CI verde ≠ código actual en producción** → el frontend desplegado mostraba datos hardcodeados (salas y atletas de maqueta) aunque el pipeline estaba verde: la versión conectada al backend real se había fusionado a `develop` pero nunca se promovió a `main`, y el deploy sale de `main`. El pipeline desplegaba, correctamente, código viejo. Se corrigió promoviendo `develop` → `main` (PR raceflow-frontend#10), eliminando de paso la lista mock de "salas activas" (no existe endpoint para listar salas). Bonus: al pasar el código real por el pipeline, SonarCloud bloqueó una vulnerabilidad genuina (código de sala y token insertados sin validar en la URL del WebSocket, regla S8480) que se corrigió con validación de formato y encoding. Moraleja doble: verificar el *contenido* funcional desplegado (probar el flujo real, no solo el status del pipeline) y mantener la promoción `develop` → `main` como paso explícito del proceso de release.

## Verificación end-to-end realizada

- Los 7 componentes responden HTTP 200 con contenido real.
- Los 6 backend reportan `{"status":"UP"}` en `/actuator/health` (BD + Redis + RabbitMQ conectados).
- Enrutamiento del gateway verificado: `POST /api/auth/login` a través del gateway devuelve exactamente la misma respuesta que auth-service directo.
- Preflight CORS verificado desde el dominio del frontend contra auth-service.
- Flujo funcional completo (registro → login → crear sala → unirse → mapa → ranking en vivo por WebSocket) probado desde un dispositivo móvil real.
